extends SceneTree
## Turns a 3x3-terrain PNG export into a Godot `TileSet` with real terrain bits.
##
##     godot --headless --path . --script res://tools/build_terrain_tileset.gd
##
## ## The peering bits are read out of the art, not assumed
##
## Every tileset exporter lays its 3x3 set out differently, and the usual way to
## import one is to look up the tool's convention and trust it. That is a guess
## that fails silently: a wrong bit does not error, it just makes the autotiler
## pick the wrong corner piece somewhere in the middle of a map, months later.
##
## So this reads each tile instead. For a tile, nine points are sampled — the
## centre and the eight peering positions — and each is classified as one of the
## two terrains by colour. The bitmask is then a *description of the picture*,
## which means it cannot disagree with it.
##
## The two terrain colours are not hard-coded either. They are found by
## 2-means over the sampled pixels, so the same script handles grass/dirt and
## grass/water without being told which is which.

const TILE := 64
const SOURCES: Array = [
	# png, tileset path, terrain set name, the two terrain names. The order of
	# the names does not matter: which cluster is which is decided by the art,
	# and `_name_clusters` puts the greener one first so "grass" is terrain 0
	# in both files.
	["res://art/tilesets/sandy dirt ↗ field grass-godot.png",
		"res://resources/tilesets/grass_dirt.tres", "grass_dirt", ["grass", "dirt"]],
	["res://art/tilesets/forest pond ↗ field grass-godot.png",
		"res://resources/tilesets/grass_water.tres", "grass_water", ["grass", "water"]],
]

## Where in a tile each peering bit is sampled, as a fraction of the tile.
## Corners are pulled in from the very edge so a one-pixel outline does not
## decide a whole bit.
## Where each peering bit is sampled, as a fraction of the tile.
##
## **Four corners, not eight neighbours**, and the count is what told me so.
## Sampling all eight produced 14 distinct masks out of 192 tiles, and 14 is
## suspiciously close to 16 — which is 2^4, every arrangement of four corners.
## 192 is 12 x 16. This art is a **four-corner Wang set** with twelve variants
## of each tile, not the 47-tile blob set that `MATCH_CORNERS_AND_SIDES`
## expects, and asking it for side bits was asking a question the tiles do not
## answer.
##
## Chasing that as a sampling problem cost two passes — probes moved inward,
## then hard against the edges — and neither moved the number, because the
## information was never missing. It was never there.
const PROBES := {
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Vector2(0.06, 0.06),
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Vector2(0.94, 0.06),
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Vector2(0.94, 0.94),
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Vector2(0.06, 0.94),
}

## A probe averages this many pixels square. Small: at 9 a corner probe bled
## into the side next to it, so the two bits stopped being able to disagree —
## which is half of how the mask count collapsed.
const PATCH := 5

## Every arrangement of four corners is 2^4 = 16. Not asserted as an equality,
## because an export need not draw all of them, but a build landing far short is
## a build whose bits are not carrying information — worth failing over rather
## than discovering in a screenshot three weeks later.
const MASKS_EXPECTED := 14


func _init() -> void:
	for entry in SOURCES:
		_build(entry[0], entry[1], entry[2], entry[3])
	quit()


func _build(png_path: String, out_path: String, set_name: String, names: Array) -> void:
	var texture := load(png_path) as Texture2D
	if texture == null:
		push_error("build_terrain_tileset: no texture at %s" % png_path)
		return
	var image := texture.get_image()
	var cols := image.get_width() / TILE
	var rows := image.get_height() / TILE

	var samples := _sample_all(image, cols, rows)
	var centres := _two_means(samples)
	centres = _name_clusters(centres)

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_terrain_set()
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	for i in names.size():
		tileset.add_terrain(0, i)
		tileset.set_terrain_name(0, i, String(names[i]))
		tileset.set_terrain_color(0, i, centres[i])

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)

	var counts := [0, 0]
	var masks := {}
	for y in rows:
		for x in cols:
			var at := Vector2i(x, y)
			source.create_tile(at)
			var data := source.get_tile_data(at, 0)
			var centre := _classify(_patch(image, at, Vector2(0.5, 0.5)), centres)
			data.terrain_set = 0
			data.terrain = centre
			counts[centre] += 1
			var signature := str(centre)
			for bit in PROBES:
				var side := _classify(_patch(image, at, PROBES[bit]), centres)
				data.set_terrain_peering_bit(bit, side)
				signature += ",%d" % side
			masks[signature] = true

	@warning_ignore("return_value_discarded")
	tileset.add_source(source, 0)
	var err := ResourceSaver.save(tileset, out_path)
	if err != OK:
		push_error("build_terrain_tileset: could not write %s (%d)" % [out_path, err])
		return
	print("%s: %dx%d tiles, terrain set '%s' [%s], centres %s / %s"
		% [out_path.get_file(), cols, rows, set_name, ", ".join(names),
			centres[0].to_html(false), centres[1].to_html(false)])
	print("    tile centres: %d %s, %d %s" % [counts[0], names[0], counts[1], names[1]])
	# **The check that should have come first.** Notching in a render is a
	# symptom; this is the disease, and it is one number.
	print("    distinct masks: %d of ~%d wanted" % [masks.size(), MASKS_EXPECTED])
	if masks.size() < MASKS_EXPECTED:
		push_error("build_terrain_tileset: only %d distinct masks in %s — the peering bits are not discriminating between tiles."
			% [masks.size(), out_path.get_file()])


## The average colour of a small patch, which is what a probe actually reads.
static func _patch(image: Image, cell: Vector2i, where: Vector2) -> Color:
	var origin := cell * TILE + Vector2i(where * float(TILE))
	var total := Vector3.ZERO
	var taken := 0
	var half := PATCH / 2
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var px := origin + Vector2i(dx, dy)
			if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
				continue
			var c := image.get_pixelv(px)
			total += Vector3(c.r, c.g, c.b)
			taken += 1
	if taken == 0:
		return Color.BLACK
	total /= float(taken)
	return Color(total.x, total.y, total.z)


func _sample_all(image: Image, cols: int, rows: int) -> Array:
	var out: Array = []
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			out.append(_patch(image, cell, Vector2(0.5, 0.5)))
			for bit in PROBES:
				out.append(_patch(image, cell, PROBES[bit]))
	return out


## Two-means over the sampled colours. Seeded with the two most distant samples
## rather than at random, so the result is the same every run — this writes a
## committed file, and a generator whose output moves between runs is a
## generator nobody can review a diff of.
static func _two_means(samples: Array) -> Array:
	var a: Color = samples[0]
	var b: Color = samples[0]
	var far := -1.0
	# Distance from one arbitrary point finds one extreme; distance from that
	# finds the other. Cheaper than all-pairs and good enough for two clusters.
	for s in samples:
		var d := _distance(samples[0], s)
		if d > far:
			far = d
			a = s
	far = -1.0
	for s in samples:
		var d := _distance(a, s)
		if d > far:
			far = d
			b = s

	for pass_number in 12:
		var sum_a := Vector3.ZERO
		var sum_b := Vector3.ZERO
		var count_a := 0
		var count_b := 0
		for s in samples:
			if _distance(s, a) <= _distance(s, b):
				sum_a += Vector3(s.r, s.g, s.b)
				count_a += 1
			else:
				sum_b += Vector3(s.r, s.g, s.b)
				count_b += 1
		if count_a > 0:
			sum_a /= float(count_a)
			a = Color(sum_a.x, sum_a.y, sum_a.z)
		if count_b > 0:
			sum_b /= float(count_b)
			b = Color(sum_b.x, sum_b.y, sum_b.z)
	return [a, b]


## Greenest cluster first, so terrain 0 is grass in every file this builds and a
## map author does not have to remember which way round a given export came out.
static func _name_clusters(centres: Array) -> Array:
	var first: Color = centres[0]
	var second: Color = centres[1]
	var green_first := first.g - maxf(first.r, first.b)
	var green_second := second.g - maxf(second.r, second.b)
	return centres if green_first >= green_second else [second, first]


static func _classify(colour: Color, centres: Array) -> int:
	return 0 if _distance(colour, centres[0]) <= _distance(colour, centres[1]) else 1


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length_squared()
