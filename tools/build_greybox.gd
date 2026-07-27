extends SceneTree
## Builds the greybox TileSet and the Ambry village scene.
##
##     godot --headless --path . --script res://tools/build_greybox.gd
##
## Run after `python3 tools/gen_greybox_tileset.py`. Both outputs are committed,
## so this only needs re-running when the tile list or the village layout below
## changes — and after that, the scene is a normal Godot scene you can open and
## edit by hand.
##
## Why a script instead of hand-written `.tres` / `.tscn`: a TileSet's atlas
## sources and per-tile collision polygons, and a TileMapLayer's packed cell
## data, are formats that are easy to get subtly wrong by hand and produce
## silent breakage rather than a parse error. Building them through the engine's
## own API means they are correct by construction.

const TILE := 64
const ATLAS_COLS := 4

const TILESET_PATH := "res://resources/tilesets/greybox.tres"
const TEXTURE_PATH := "res://art/tilesets/greybox_64.png"
const VILLAGE_PATH := "res://levels/ambry/ambry.tscn"

# Must match tools/gen_greybox_tileset.py, in order.
const TILES: Array = [
	["dirt_path", false], ["grass_yard", false], ["cobble", false], ["floorboards", false],
	["wall", true], ["wall_inner", true], ["roof", false], ["fence", true],
	["door", false], ["window", true], ["hearth", false], ["well", true],
	["plot_empty", false], ["plot_ruined", false], ["stockpile", true], ["bed_save", false],
	["gate", true], ["npc_marker", false], ["blight_creep", true], ["void", true],
]

# --------------------------------------------------------------------------
# Ambry.
#
# Laid out rather than drawn: buildings are rects with a door, paths are runs
# between them. That keeps the layout editable as intent ("move the smith two
# tiles east") instead of as a wall of characters.
#
# The shape is doing narrative work. The gate is south, so the player arrives
# from the valley and the blight is always behind them at the north edge,
# visible and closer than anyone would like. The square with its well and hearth
# is dead centre, because the warmth pillar wants a place the player returns to
# without being sent. Ruined plots sit on the north side — the town has already
# lost ground, and rebuilding pushes back toward the thing.
# --------------------------------------------------------------------------

const MAP_W := 40
const MAP_H := 30

## name, rect (x, y, w, h), door offset along the south wall, plot id, state
## state: "built" | "ruined" | "empty"
const BUILDINGS: Array = [
	["inn",        Rect2i(4, 17, 8, 6),  3, "inn",        "built"],
	["smith",      Rect2i(28, 17, 7, 6), 3, "smith",      "built"],
	["magistrate", Rect2i(15, 4, 10, 6), 4, "magistrate", "built"],
	["apothecary", Rect2i(4, 5, 7, 5),   3, "apothecary", "ruined"],
	["chapel",     Rect2i(29, 5, 7, 5),  3, "chapel",     "ruined"],
	["market",     Rect2i(14, 22, 6, 4), 2, "market",     "empty"],
	["watchpost",  Rect2i(23, 22, 5, 4), 2, "watchpost",  "empty"],
]

## Where each named NPC stands. Ids match the §7 cast.
const NPCS: Array = [
	["magistrate", Vector2i(20, 11)],
	["smith", Vector2i(31, 23)],
	["innkeeper", Vector2i(8, 23)],
	["child", Vector2i(17, 15)],
	["apothecary", Vector2i(7, 11)],
	["reluctant_guard", Vector2i(20, 27)],
	["unrepentant", Vector2i(25, 16)],
	["hidden_case", Vector2i(12, 13)],
	["fox", Vector2i(24, 13)],
]

var _index := {}


func _init() -> void:
	for i in TILES.size():
		_index[TILES[i][0]] = Vector2i(i % ATLAS_COLS, i / ATLAS_COLS)

	var tileset := _build_tileset()
	_save(tileset, TILESET_PATH)
	_build_village(tileset)
	quit()


# ------------------------------------------------------------------ tileset

func _build_tileset() -> TileSet:
	var texture: Texture2D = load(TEXTURE_PATH)
	if texture == null:
		push_error("missing %s — run tools/gen_greybox_tileset.py first" % TEXTURE_PATH)
		quit(1)
		return null

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer(0)
	# Layer 1 is World (GDD §10). Static geometry collides with nothing itself.
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])

	for i in TILES.size():
		var coords: Vector2i = Vector2i(i % ATLAS_COLS, i / ATLAS_COLS)
		source.create_tile(coords)
		if TILES[i][1]:
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)

	tileset.add_source(source, 0)
	print("tileset: %d tiles, %d solid" % [TILES.size(), TILES.filter(func(t): return t[1]).size()])
	return tileset


# ------------------------------------------------------------------ village

func _build_village(tileset: TileSet) -> void:
	var ground := _new_layer("Ground", tileset, 0)
	var objects := _new_layer("Objects", tileset, 1)
	var overhead := _new_layer("Overhead", tileset, 2)
	objects.y_sort_enabled = true

	# Ground: grass everywhere, then a cobbled square, then paths.
	_fill(ground, Rect2i(0, 0, MAP_W, MAP_H), "grass_yard")
	_fill(ground, Rect2i(13, 11, 14, 9), "cobble")

	# The blight has already reached the north edge. It is visible from the
	# square, which is the point — the threat is never off-screen in the one
	# place that is supposed to feel safe.
	_fill(ground, Rect2i(0, 0, MAP_W, 2), "blight_creep")
	for x in range(0, MAP_W, 3):
		_put(ground, Vector2i(x, 2), "blight_creep")

	# Roads: a spine from the south gate to the square, and a ring around it.
	_fill(ground, Rect2i(19, 20, 2, 10), "dirt_path")
	_fill(ground, Rect2i(2, 10, MAP_W - 4, 1), "dirt_path")
	_fill(ground, Rect2i(2, 16, MAP_W - 4, 1), "dirt_path")

	# Town edge: fences along the sides, a gate south.
	for x in range(1, MAP_W - 1):
		_put(objects, Vector2i(x, MAP_H - 1), "fence")
	for y in range(3, MAP_H - 1):
		_put(objects, Vector2i(1, y), "fence")
		_put(objects, Vector2i(MAP_W - 2, y), "fence")
	for x in [19, 20]:
		_put(objects, Vector2i(x, MAP_H - 1), "gate")
		_put(ground, Vector2i(x, MAP_H - 1), "dirt_path")

	# The square: a well, and a hearth. Light is hearths, not glare.
	_fill(objects, Rect2i(18, 13, 2, 2), "well")
	_fill(objects, Rect2i(22, 15, 2, 2), "hearth")

	for entry in BUILDINGS:
		_place_building(ground, objects, overhead, entry)

	var root := Node2D.new()
	root.name = "Ambry"
	root.y_sort_enabled = true
	for layer in [ground, objects, overhead]:
		root.add_child(layer)
		layer.owner = root

	_add_markers(root)

	var packed := PackedScene.new()
	packed.pack(root)
	_save(packed, VILLAGE_PATH)
	# The tool builds these nodes outside any tree, so nothing else will free
	# them and the engine reports leaked RIDs on exit.
	root.free()
	print("village: %dx%d tiles (%dx%d px), %d buildings, %d npc markers"
		% [MAP_W, MAP_H, MAP_W * TILE, MAP_H * TILE, BUILDINGS.size(), NPCS.size()])


func _place_building(ground: TileMapLayer, objects: TileMapLayer, overhead: TileMapLayer,
		entry: Array) -> void:
	var rect: Rect2i = entry[1]
	var door_offset: int = entry[2]
	var state: String = entry[4]

	if state == "empty":
		# Nothing here yet — a marked site waiting to be built.
		_fill(ground, rect, "plot_empty")
		return
	if state == "ruined":
		# Lost to the blight. Walkable, so the player can stand in it and be
		# told what used to be here.
		_fill(ground, rect, "plot_ruined")
		for x in range(rect.position.x, rect.end.x):
			_put(objects, Vector2i(x, rect.position.y), "wall_inner")
		return

	# Standing building: floor, walls, a door in the south face, roof above.
	_fill(ground, rect, "floorboards")
	for x in range(rect.position.x, rect.end.x):
		_put(objects, Vector2i(x, rect.position.y), "wall")
		_put(objects, Vector2i(x, rect.end.y - 1), "wall")
	for y in range(rect.position.y, rect.end.y):
		_put(objects, Vector2i(rect.position.x, y), "wall")
		_put(objects, Vector2i(rect.end.x - 1, y), "wall")

	var door := Vector2i(rect.position.x + door_offset, rect.end.y - 1)
	_put(objects, door, "door")
	_put(ground, door, "floorboards")
	_put(ground, door + Vector2i(0, 1), "dirt_path")

	# Windows either side of the door, so a facade reads as a facade.
	if door_offset >= 2:
		_put(objects, door - Vector2i(2, 0), "window")
	if door_offset + 2 < rect.size.x - 1:
		_put(objects, door + Vector2i(2, 0), "window")

	# Roof on the overhead layer: drawn above the player, no collision, so
	# walking "inside" reads correctly once interiors matter.
	_fill(overhead, Rect2i(rect.position.x, rect.position.y - 1, rect.size.x, 1), "roof")


func _add_markers(root: Node2D) -> void:
	var plots := Node2D.new()
	plots.name = "BuildingPlots"
	root.add_child(plots)
	plots.owner = root
	for entry in BUILDINGS:
		var rect: Rect2i = entry[1]
		var marker := Marker2D.new()
		marker.name = "Plot_" + String(entry[3])
		marker.position = Vector2(
			(rect.position.x + rect.size.x * 0.5) * TILE,
			(rect.end.y + 1) * TILE
		)
		marker.set_meta("plot_id", entry[3])
		marker.set_meta("state", entry[4])
		plots.add_child(marker)
		marker.owner = root

	var npcs := Node2D.new()
	npcs.name = "NpcMarkers"
	root.add_child(npcs)
	npcs.owner = root
	for entry in NPCS:
		var marker := Marker2D.new()
		marker.name = "Npc_" + String(entry[0])
		marker.position = Vector2(entry[1]) * TILE + Vector2(TILE, TILE) * 0.5
		marker.set_meta("npc_id", entry[0])
		npcs.add_child(marker)
		marker.owner = root

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	# Just inside the south gate: the player always enters Ambry the same way.
	spawn.position = Vector2(19.5, MAP_H - 3) * TILE
	root.add_child(spawn)
	spawn.owner = root


# ------------------------------------------------------------------ helpers

func _new_layer(layer_name: String, tileset: TileSet, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z
	return layer


func _put(layer: TileMapLayer, cell: Vector2i, tile_name: String) -> void:
	if not _index.has(tile_name):
		push_error("unknown tile '%s'" % tile_name)
		return
	layer.set_cell(cell, 0, _index[tile_name])


func _fill(layer: TileMapLayer, rect: Rect2i, tile_name: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_put(layer, Vector2i(x, y), tile_name)


func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("failed to save %s (%d)" % [path, error])
		quit(1)
	else:
		print("wrote %s" % path)
