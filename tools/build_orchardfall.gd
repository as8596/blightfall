extends SceneTree
## Builds Orchardfall — the valley outside Ambry's south gate.
##
##     godot --headless --path . --script res://tools/build_orchardfall.gd
##
## Run after `tools/build_greybox.gd`, which writes the shared tileset.
##
## **Six areas, not one field.** A zone that is a single large rectangle is a
## room with a long walk in it: you can see the whole thing from the middle, so
## there is nothing to find and no reason to remember where anything was. Six
## connected areas with a loop in them give the place a shape you learn.
##
## The graph is deliberately not a tree:
##
##     [ AMBRY ] ─── south gate
##          │
##     valley_road ──── E ──── millpond
##          │ S                    │ S
##     orchard_rows ─── E ──── terraces
##          │ S                    │ S
##     cider_yard ───── E ──── deep_rows
##
## Eight edges, every one of them two-way, and a circuit through the middle
## four. Getting back is never a matter of retracing your steps exactly, which
## is most of what makes a place feel navigable rather than remembered.
##
## Edges are walked into, not pressed (`world/gateway.gd`). Each exit emits a
## `Gateways` marker on the outermost row of the opening, and an `Edge_<facing>`
## marker two tiles inside it — that second one is where you land arriving from
## the other direction, and being two tiles clear of the trigger is what stops
## an arrival from immediately bouncing back.

const PROP_SCENE: PackedScene = preload("res://world/prop.tscn")

const AMBRY_LEVEL := "res://levels/ambry/ambry_level.tscn"
const ZONE_DIR := "res://levels/orchardfall"

## Fixed, so the same command always writes the same valley. Scatter that moves
## between runs would make every layout assertion below a coin toss.
const SEED := 0xB117FA11

## Opposite edges, for deriving which arrival marker an exit points at. Walking
## south out of one area arrives at the next one's northern edge.
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

## Wolf packs per area. Two wolves each where there is room for two.
const PACKS_MIN := 2
const PACKS_MAX := 3
## No wolf within this many tiles of anywhere the player can arrive. Six tiles
## is just under the wolf's 480px aggro range, so you get a moment to see the
## place you are standing in before anything starts moving toward you.
const SAFE_TILES := 6
## And this far apart, so two packs do not read as one large one.
const PACK_GAP := 8

## Tiles that are drawn as `world/prop.tscn` instances instead of as squares.
##
## **The tile stays.** It keeps its collision and its place in the flood fill;
## the layer holding it simply stops drawing. That is what lets real art in
## without touching a single assertion: reachability, the border, and the exits
## are all still measured against exactly the cells they were measured against
## before, and the picture on top is free to be any shape it likes.
##
## Doing it the other way — deleting the tile and blocking with the prop's own
## 28px trunk collider — would have been tidier and would have quietly changed
## what "this area is fully connected" means, since a row of trunks is walkable
## between and a row of tiles is not.
const CANOPY: Dictionary = {
	"orchard_tree": ["pine_tree"],
	"dead_tree": ["pine_tree"],
}

## The blocking footprint of a tree, in pixels: the trunk, not the canopy. Only
## cosmetic here — the tile underneath is what actually stops you — but it keeps
## the props honest if the tiles are ever dropped.
const TRUNK := Vector2(30, 18)

## Trees are drawn at double size.
##
## The art is 128px tall and the player is 96, so at 1:1 a pine stands a head
## taller than a man — which reads as a shrub he could step over rather than as a
## tree. Doubling puts it at four tiles, near three times his height, which is
## about right for a conifer.
##
## The cost is real and worth naming: the tree's pixels are twice the size of the
## player's, so the wood is visibly chunkier than the man walking through it. A
## tree authored at 256px would be strictly better and is the fix; this is the
## version that works with the art that exists.
const TREE_SCALE := 2.0

## Ground the undergrowth stays off. Paths first — a road with bushes growing
## down the middle of it is not a road, and the paths are the one thing in the
## zone that has to read as deliberate from across the screen. Water and floors
## for the obvious reasons.
const BARE_GROUND: Array = ["dirt_path", "bridge", "cobble", "floorboards",
	"water", "shallows", "hearth"]

## Undergrowth. Pure decoration: no tile, no collision, no effect on anything the
## assertions measure. Scattered on open ground the player can already walk, so a
## clearing reads as a clearing rather than as a flat green rectangle.
const UNDERGROWTH: Array = ["sage_bush", "hedge_shrub", "round_hedge",
	"thorn_bush", "cypress_shrub"]
const UNDERGROWTH_DENSITY := 0.055

# --------------------------------------------------------------------------
# The valley. Each area is: what the ground is, what fences it in, where the
# ways out are, and then the specific things worth walking to.
#
# Order matters in `_build_area`: ground, then patches, then scatter, then the
# paths are carved *through* the scatter, then the border. Carving last is what
# makes reachability structural rather than lucky — a road cannot be blocked by
# a tree that was placed before the road was.
#
# exits: [facing, offset along that edge, span in tiles, target area id]
# --------------------------------------------------------------------------

const AREAS: Array = [
	{
		"id": "valley_road",
		"title": "The Valley Road",
		"size": Vector2i(30, 24),
		"ground": "grass_yard",
		"border": "dead_tree",
		# North is the way home. The player arrives here on their first trip out
		# and every trip after, so it is the one area that has to be legible in
		# three seconds: a road, a fork, and a sign.
		"exits": [
			["north", 14, 2, "ambry"],
			["south", 14, 2, "orchard_rows"],
			["east", 11, 2, "millpond"],
		],
		"paths": [
			Rect2i(14, 0, 2, 24),          # the road, gate to orchard
			Rect2i(15, 11, 15, 2),         # the spur east to the millpond
		],
		"patches": [
			[Rect2i(3, 4, 8, 5), "crop_row", "ground"],
			[Rect2i(20, 16, 7, 5), "tall_grass", "ground"],
		],
		"scatter": [
			["dead_tree", Rect2i(2, 2, 11, 9), 0.18],
			["dead_tree", Rect2i(18, 2, 10, 8), 0.16],
			["rock", Rect2i(3, 15, 9, 7), 0.10],
		],
		"features": [
			["signpost", Vector2i(16, 10)],
			["rock", Vector2i(13, 6)],
		],
		"pois": [
			["valley_signpost", Vector2i(16, 11), "Ambry north, the rows south, the mill east"],
		],
	},
	{
		"id": "orchard_rows",
		"title": "The Orchard Rows",
		"size": Vector2i(34, 28),
		"ground": "crop_row",
		"border": "orchard_tree",
		"exits": [
			["north", 16, 2, "valley_road"],
			["east", 13, 2, "terraces"],
			["south", 8, 2, "cider_yard"],
		],
		"paths": [
			Rect2i(16, 0, 2, 15),
			Rect2i(8, 13, 10, 2),
			Rect2i(8, 14, 2, 14),
			Rect2i(17, 13, 17, 2),
		],
		"patches": [
			[Rect2i(2, 2, 30, 10), "crop_row", "ground"],
			[Rect2i(2, 16, 30, 10), "crop_row", "ground"],
		],
		# Planted, not scattered — rows are what the place is named for, and a
		# random spray of trees reads as woodland rather than as an orchard
		# somebody laid out and then lost.
		"rows": [
			[Rect2i(2, 2, 30, 10), 3, 2, "orchard_tree"],
			[Rect2i(2, 16, 30, 10), 3, 2, "orchard_tree"],
		],
		"scatter": [
			["dead_tree", Rect2i(20, 17, 12, 9), 0.14],
		],
		"features": [],
		"pois": [
			["orchard_heart", Vector2i(24, 8), "the rows still stand; nothing on them does"],
		],
	},
	{
		"id": "millpond",
		"title": "The Millpond",
		"size": Vector2i(26, 26),
		"ground": "grass_yard",
		"border": "rock",
		"exits": [
			["west", 12, 2, "valley_road"],
			["south", 12, 2, "terraces"],
		],
		"paths": [
			Rect2i(0, 12, 14, 2),
			Rect2i(12, 13, 2, 13),
		],
		"patches": [
			[Rect2i(15, 5, 8, 7), "water", "ground"],
			[Rect2i(14, 4, 10, 1), "shallows", "ground"],
			[Rect2i(14, 12, 10, 1), "shallows", "ground"],
			[Rect2i(14, 5, 1, 7), "shallows", "ground"],
			[Rect2i(23, 5, 1, 7), "shallows", "ground"],
			[Rect2i(4, 17, 7, 6), "tall_grass", "ground"],
		],
		"scatter": [
			["rock", Rect2i(3, 3, 9, 7), 0.12],
			["dead_tree", Rect2i(16, 16, 8, 8), 0.16],
		],
		# The mill is on the **far** shore, and the bridge is the short way to
		# it. A bridge with nothing on the other side is scenery pretending to
		# be a route — you can still walk round the pond, which is what makes
		# the bridge a shortcut rather than a gate.
		"features": [
			["ruin_wall", Vector2i(15, 3)], ["ruin_wall", Vector2i(16, 3)],
			["ruin_wall", Vector2i(21, 3)], ["ruin_wall", Vector2i(22, 3)],
		],
		"bridges": [Rect2i(18, 4, 2, 9)],
		"pois": [
			["mill_ruin", Vector2i(18, 3), "the wheel is still in the water"],
			["millpond_shore", Vector2i(18, 13), "clean, or looks it"],
		],
	},
	{
		"id": "terraces",
		"title": "The Terraces",
		"size": Vector2i(30, 30),
		"ground": "grass_yard",
		"border": "ruin_wall",
		"exits": [
			["north", 12, 2, "millpond"],
			["west", 15, 2, "orchard_rows"],
			["south", 14, 2, "deep_rows"],
		],
		"paths": [
			Rect2i(12, 0, 2, 16),
			Rect2i(0, 15, 14, 2),
			Rect2i(13, 15, 2, 15),
		],
		"patches": [
			[Rect2i(3, 3, 24, 3), "crop_row", "ground"],
			[Rect2i(3, 9, 24, 3), "crop_row", "ground"],
			[Rect2i(16, 20, 11, 7), "tall_grass", "ground"],
		],
		# Stepped retaining walls with gaps, so the climb reads as terraces
		# rather than as three fences.
		"terraces": [
			[Rect2i(2, 6, 26, 1), "ruin_wall", [11, 12, 13, 14]],
			[Rect2i(2, 12, 26, 1), "ruin_wall", [11, 12, 13, 14]],
			[Rect2i(2, 19, 26, 1), "ruin_wall", [12, 13, 14, 15]],
		],
		"scatter": [
			["rock", Rect2i(3, 20, 9, 8), 0.14],
			["blight_creep", Rect2i(17, 21, 10, 7), 0.20],
		],
		"features": [],
		"pois": [
			["terrace_top", Vector2i(20, 4), "the valley, all of it, from here"],
		],
	},
	{
		"id": "cider_yard",
		"title": "The Cider Yard",
		"size": Vector2i(24, 20),
		"ground": "dirt_path",
		"border": "orchard_tree",
		"exits": [
			["north", 11, 2, "orchard_rows"],
			["east", 10, 2, "deep_rows"],
		],
		"paths": [
			Rect2i(11, 0, 2, 11),
			Rect2i(11, 10, 13, 2),
		],
		"patches": [
			[Rect2i(2, 13, 20, 5), "tall_grass", "ground"],
		],
		"scatter": [
			["stockpile", Rect2i(3, 13, 18, 4), 0.12],
			["orchard_tree", Rect2i(15, 2, 7, 6), 0.20],
		],
		"features": [],
		# The one interior in the zone. A door, which means it is pressed —
		# inside and outside are different places, and the fade should be
		# something the player asked for.
		"building": {
			"rect": Rect2i(3, 3, 8, 6), "door_offset": 4,
			"interior": ZONE_DIR + "/interiors/cider_house_level.tscn",
		},
		"pois": [
			["cider_house", Vector2i(7, 9), "the press, and whatever is left of it"],
		],
	},
	{
		"id": "deep_rows",
		"title": "The Deep Rows",
		"size": Vector2i(32, 26),
		"ground": "plot_ruined",
		"border": "dead_tree",
		"exits": [
			["north", 15, 2, "terraces"],
			["west", 12, 2, "cider_yard"],
		],
		"paths": [
			Rect2i(15, 0, 2, 13),
			Rect2i(0, 12, 17, 2),
			# The spur to the stone. It has to be carved rather than left to the
			# scatter: `blight_creep` is solid, and at this density it closed the
			# route to the one thing in the area worth walking to. The assertion
			# below caught it, which is the entire reason the assertion exists.
			Rect2i(15, 13, 2, 9),
			Rect2i(16, 20, 10, 2),
		],
		"patches": [
			[Rect2i(3, 3, 12, 8), "crop_row", "ground"],       # the last rows planted
			[Rect2i(18, 15, 12, 8), "tall_grass", "ground"],
		],
		# The deepest blight in the zone — and still scattered rather than laid
		# down as ground, for two reasons. `blight_creep` is **solid**, so a
		# ground patch of it is an invisible wall the size of the patch; and
		# GDD §8 makes it the one saturated colour in the game, which only works
		# while it is an accent. Half a screen of it is wallpaper.
		"scatter": [
			["blight_creep", Rect2i(3, 15, 26, 8), 0.13],
			["blight_creep", Rect2i(20, 3, 10, 8), 0.15],
			["dead_tree", Rect2i(3, 2, 12, 9), 0.18],
		],
		"features": [
			["shrine", Vector2i(25, 20)],
		],
		"pois": [
			["warden_stone", Vector2i(25, 21), "the Warden's Hook — GDD §6, not placed yet"],
		],
	},
]

## The zone's one interior. id, room size, door offset, features, POIs.
const INTERIORS: Array = [
	["cider_house", Vector2i(10, 7), 4,
		[["stockpile", Vector2i(2, 2)], ["stockpile", Vector2i(3, 2)],
			["chest", Vector2i(7, 2)]],
		[["cider_press", Vector2i(7, 3), "somebody has been here since"]]],
]

var map := GreyboxMap.new()
var _rng := RandomNumberGenerator.new()
var _by_id := {}


func _init() -> void:
	for area in AREAS:
		_by_id[area["id"]] = area

	var tileset: TileSet = load(GreyboxMap.TILESET_PATH)
	if tileset == null:
		map.fail("missing %s — run tools/build_greybox.gd first" % GreyboxMap.TILESET_PATH)
		_finish()
		return

	_assert_graph()
	for area in AREAS:
		_build_area(tileset, area)
	for entry in INTERIORS:
		_build_interior(tileset, entry)
	_finish()


func _finish() -> void:
	if map.failures > 0:
		push_error("build_orchardfall: %d assertion(s) failed" % map.failures)
		quit(1)
		return
	print("orchardfall: %d areas, %d interiors" % [AREAS.size(), INTERIORS.size()])
	quit()


## Every exit must have a matching exit coming back.
##
## Checked before a single tile is written, because the failure is otherwise
## invisible from inside the game: a one-way edge looks exactly like a two-way
## one until somebody walks through it and cannot get back, and by then they are
## standing in an area with a full satchel and no way home.
func _assert_graph() -> void:
	var broken: Array[String] = []
	var seen := {}
	for area in AREAS:
		var here: String = area["id"]
		for exit in area["exits"]:
			var facing: String = exit[0]
			var there: String = exit[3]
			seen[here + ">" + there] = facing
			if there == "ambry":
				continue
			if not _by_id.has(there):
				broken.append("%s exits %s to '%s', which does not exist" % [here, facing, there])
				continue
			var back := false
			for other in _by_id[there]["exits"]:
				if String(other[3]) == here and String(other[0]) == OPPOSITE[facing]:
					back = true
			if not back:
				broken.append("%s exits %s to %s, and %s has no %s exit back"
					% [here, facing, there, there, OPPOSITE[facing]])
	if broken.is_empty():
		print("zone graph: %d exits, every one of them paired" % seen.size())
	else:
		map.fail("one-way edges: %s" % [broken])

	# ...and the whole thing has to be one place. An area nothing reaches is
	# content nobody will ever see, and it would build without complaint.
	var reached := {"valley_road": true}
	var queue: Array[String] = ["valley_road"]
	while not queue.is_empty():
		var here: String = queue.pop_back()
		for exit in _by_id[here]["exits"]:
			var there: String = exit[3]
			if there == "ambry" or reached.has(there):
				continue
			reached[there] = true
			queue.append(there)
	if reached.size() != AREAS.size():
		var lost: Array[String] = []
		for area in AREAS:
			if not reached.has(area["id"]):
				lost.append(area["id"])
		map.fail("unreachable from the valley road: %s" % [lost])
	else:
		print("zone graph: all %d areas reachable from the gate" % AREAS.size())


# --------------------------------------------------------------------- areas

func _build_area(tileset: TileSet, area: Dictionary) -> void:
	var id: String = area["id"]
	var size: Vector2i = area["size"]
	_rng.seed = hash(id) ^ SEED

	var ground := map.new_layer("Ground", tileset, GreyboxMap.Z_GROUND)
	var objects := map.new_layer("Objects", tileset, GreyboxMap.Z_OBJECTS)
	var overhead := map.new_layer("Overhead", tileset, GreyboxMap.Z_OVERHEAD)
	objects.y_sort_enabled = true

	# Trees live here: solid, flooded over, and transparent. See CANOPY.
	# Transparent rather than `visible = false`, because a hidden TileMapLayer is
	# one refactor away from somebody disabling its collision too, and the whole
	# point of this layer is that its collision is the real thing.
	var canopy := map.new_layer("Canopy", tileset, GreyboxMap.Z_OBJECTS)
	canopy.y_sort_enabled = true
	canopy.modulate = Color(1.0, 1.0, 1.0, 0.0)

	map.fill(ground, Rect2i(0, 0, size.x, size.y), String(area["ground"]))
	for patch in area.get("patches", []):
		var layer: TileMapLayer = ground if String(patch[2]) == "ground" else objects
		map.fill(layer, patch[0], String(patch[1]))

	for row in area.get("rows", []):
		_plant_rows(_layer_for(String(row[3]), objects, canopy),
			row[0], int(row[1]), int(row[2]), String(row[3]))
	for entry in area.get("scatter", []):
		_scatter(_layer_for(String(entry[0]), objects, canopy),
			entry[1], float(entry[2]), String(entry[0]))
	for terrace in area.get("terraces", []):
		_terrace(objects, terrace[0], String(terrace[1]), terrace[2])

	# Carved last, and carving clears whatever the scatter put there. This is
	# what makes "you can walk from any exit to any other" true by construction
	# rather than by luck.
	for path in area.get("paths", []):
		map.fill(ground, path, "dirt_path")
		for y in range(path.position.y, path.end.y):
			for x in range(path.position.x, path.end.x):
				objects.erase_cell(Vector2i(x, y))
				canopy.erase_cell(Vector2i(x, y))

	for feature in area.get("features", []):
		map.put(objects, feature[1], String(feature[0]))
	for bridge in area.get("bridges", []):
		map.fill(ground, bridge, "bridge")
		for y in range(bridge.position.y, bridge.end.y):
			for x in range(bridge.position.x, bridge.end.x):
				objects.erase_cell(Vector2i(x, y))
				canopy.erase_cell(Vector2i(x, y))

	var building: Dictionary = area.get("building", {})
	if not building.is_empty():
		_place_building(ground, objects, overhead, building)

	_border(_layer_for(String(area["border"]), objects, canopy), ground, size,
		String(area["border"]), area["exits"], canopy)

	var root := Node2D.new()
	root.name = id.to_pascal_case()
	root.y_sort_enabled = true
	for layer in [ground, objects, canopy, overhead]:
		root.add_child(layer)
		layer.owner = root

	_add_markers(root, area)

	var layers: Array[TileMapLayer] = [ground, objects, canopy]
	_plant_props(root, canopy, layers, size)
	_add_wolves(root, area, layers)
	_assert_area(layers, area, overhead)

	var map_path := "%s/%s.tscn" % [ZONE_DIR, id]
	@warning_ignore("return_value_discarded")
	map.save_scene(root, map_path)
	@warning_ignore("return_value_discarded")
	map.save_level(map_path, "%s/%s_level.tscn" % [ZONE_DIR, id],
		id.to_pascal_case() + "Level", "PlayerSpawn", false)
	print("area %s: %dx%d tiles, %d exits, %d POIs"
		% [id, size.x, size.y, area["exits"].size(), area["pois"].size()])


## Which layer a tile is drawn on: the transparent canopy if a prop will stand in
## for it, the ordinary Objects layer otherwise.
static func _layer_for(tile: String, objects: TileMapLayer,
		canopy: TileMapLayer) -> TileMapLayer:
	return canopy if CANOPY.has(tile) else objects


## Stand a `Prop` on every canopy cell, then sprinkle undergrowth on the ground
## between them.
##
## Read from the finished layer rather than recorded during placement, so a tree
## carved away by a path cannot leave its picture behind — the path erases the
## cell, and a cell that is not there grows nothing. Sorted, because `get_used_cells`
## has no order to speak of and the choice of picture is drawn from the seeded
## generator: unsorted, the same seed would plant a different wood each run.
func _plant_props(root: Node2D, canopy: TileMapLayer, layers: Array[TileMapLayer],
		size: Vector2i) -> void:
	var grove := map.group(root, "Props")
	# Load-bearing. Y-sorting only reaches a node if every ancestor between it
	# and the sorting root also has it: without this the whole grove sorts as one
	# item at y=0, which puts all 229 trees behind the player at once — including
	# the ones he is standing behind.
	grove.y_sort_enabled = true
	var cells := canopy.get_used_cells()
	cells.sort()
	for cell in cells:
		var tile := map.tile_at(layers, cell)
		var choices: Array = CANOPY.get(tile, [])
		if choices.is_empty():
			continue
		_stand(root, grove, "Tree", cell,
			String(choices[_rng.randi_range(0, choices.size() - 1)]), TRUNK, TREE_SCALE)

	# Undergrowth goes only where the player can already walk, and blocks
	# nothing. It is there so a clearing reads as a clearing; a bush that stopped
	# you would be a wall you can see over, which is the most annoying kind.
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			var cell := Vector2i(x, y)
			if map.solid_at(layers, cell) or BARE_GROUND.has(map.tile_at(layers, cell)):
				continue
			# Rolled after the exclusions, not before, so skipping the paths
			# thins the bushes rather than shifting every later roll and
			# rearranging the whole area.
			if _rng.randf() >= UNDERGROWTH_DENSITY:
				continue
			_stand(root, grove, "Bush", cell,
				String(UNDERGROWTH[_rng.randi_range(0, UNDERGROWTH.size() - 1)]),
				Vector2.ZERO)


func _stand(root: Node2D, parent: Node2D, prefix: String, cell: Vector2i,
		texture: String, footprint: Vector2, zoom: float = 1.0) -> void:
	var prop: Prop = PROP_SCENE.instantiate()
	prop.name = "%s_%d_%d" % [prefix, cell.x, cell.y]
	prop.texture = load("res://art/sprites/props/%s.png" % texture)
	prop.solid = footprint != Vector2.ZERO
	prop.footprint = footprint if prop.solid else Vector2(2, 2)
	# Half of them mirrored, so a planted row is not the same photograph
	# thirty times.
	prop.flip = _rng.randf() < 0.5
	prop.art_scale = zoom
	parent.add_child(prop)
	prop.owner = root
	prop.position = GreyboxMap.centre(cell)


## Orchard planting: a tree every `step` columns, in bands `gap` rows apart, so
## the aisles run one way and you can see down them.
func _plant_rows(objects: TileMapLayer, rect: Rect2i, step: int, gap: int, tile: String) -> void:
	var band := 0
	for y in range(rect.position.y, rect.end.y):
		band += 1
		if band % (gap + 1) != 0:
			continue
		for x in range(rect.position.x, rect.end.x, step):
			map.put(objects, Vector2i(x, y), tile)


func _scatter(objects: TileMapLayer, rect: Rect2i, density: float, tile: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _rng.randf() < density:
				map.put(objects, Vector2i(x, y), tile)


## A retaining wall with numbered gaps in it — the gaps are the route up.
func _terrace(objects: TileMapLayer, rect: Rect2i, tile: String, gaps: Array) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x in gaps:
				objects.erase_cell(Vector2i(x, y))
				continue
			map.put(objects, Vector2i(x, y), tile)


func _place_building(ground: TileMapLayer, objects: TileMapLayer, overhead: TileMapLayer,
		building: Dictionary) -> void:
	var rect: Rect2i = building["rect"]
	map.fill(ground, rect, "floorboards")
	for x in range(rect.position.x, rect.end.x):
		map.put(objects, Vector2i(x, rect.position.y), "wall")
		map.put(objects, Vector2i(x, rect.end.y - 1), "wall")
	for y in range(rect.position.y, rect.end.y):
		map.put(objects, Vector2i(rect.position.x, y), "wall")
		map.put(objects, Vector2i(rect.end.x - 1, y), "wall")
	var door := _door_cell(building)
	map.put(objects, door, "door")
	map.put(ground, door + Vector2i(0, 1), "dirt_path")
	# Roofed everywhere but the south face, so the door and the windows still
	# read from the street. Same rule and same reason as Ambry's — see
	# `tools/build_greybox.gd`.
	map.fill(overhead, Rect2i(rect.position, Vector2i(rect.size.x, rect.size.y - 1)), "roof")


static func _door_cell(building: Dictionary) -> Vector2i:
	var rect: Rect2i = building["rect"]
	return Vector2i(rect.position.x + int(building["door_offset"]), rect.end.y - 1)


## Two rings of the area's own material around the edge, punched through where
## the ways out are.
##
## Two rather than one, and the material rather than `void`: a single dark line
## reads as the engine running out of map, and two rows of the thing the place
## is made of reads as the valley continuing past what you can see. The outer
## ring is where the gateway sits.
func _border(objects: TileMapLayer, ground: TileMapLayer, size: Vector2i,
		tile: String, exits: Array, canopy: TileMapLayer) -> void:
	var openings := {}
	for exit in exits:
		var facing: String = exit[0]
		for i in range(int(exit[2])):
			var along: int = int(exit[1]) + i
			for depth in range(2):
				openings[_edge_cell(size, facing, along, depth)] = true

	for x in range(size.x):
		for depth in range(2):
			for cell in [Vector2i(x, depth), Vector2i(x, size.y - 1 - depth)]:
				if openings.has(cell):
					continue
				map.put(objects, cell, tile)
	for y in range(size.y):
		for depth in range(2):
			for cell in [Vector2i(depth, y), Vector2i(size.x - 1 - depth, y)]:
				if openings.has(cell):
					continue
				map.put(objects, cell, tile)

	# The road keeps going through the gap rather than stopping at it.
	for cell in openings:
		objects.erase_cell(cell)
		canopy.erase_cell(cell)
		map.put(ground, cell, "dirt_path")


## A cell on the given edge: `along` across the opening, `depth` in from the
## outside. depth 0 is the outermost row, which is where the trigger goes.
static func _edge_cell(size: Vector2i, facing: String, along: int, depth: int) -> Vector2i:
	match facing:
		"north": return Vector2i(along, depth)
		"south": return Vector2i(along, size.y - 1 - depth)
		"east": return Vector2i(size.x - 1 - depth, along)
		_: return Vector2i(depth, along)


# ------------------------------------------------------------------- markers

func _add_markers(root: Node2D, area: Dictionary) -> void:
	var size: Vector2i = area["size"]
	var gateways := map.group(root, "Gateways")
	var doors := map.group(root, "Doorways")

	for exit in area["exits"]:
		var facing: String = exit[0]
		var at: int = int(exit[1])
		var span: int = int(exit[2])
		var target: String = exit[3]

		# On the outermost row, centred across the opening.
		var outer := _edge_cell(size, facing, at, 0)
		var pos := _span_centre(outer, facing, span)
		var target_scene := AMBRY_LEVEL if target == "ambry" \
			else "%s/%s_level.tscn" % [ZONE_DIR, target]
		map.marker_at(root, gateways, "Gateway_" + facing, pos, {
			"target_scene": target_scene,
			"target_spawn": "Edge_" + OPPOSITE[facing],
			"facing": facing,
			"span": span,
		})

		# ...and where you land coming the other way: the same opening, two rows
		# in, which is far enough that the trigger you arrived through is not
		# still under your feet.
		var inner := _edge_cell(size, facing, at, 2)
		map.marker_at(root, root, "Edge_" + facing, _span_centre(inner, facing, span))

	var pois := map.group(root, "PointsOfInterest")
	for entry in area["pois"]:
		map.marker(root, pois, "Poi_" + String(entry[0]), entry[1], {
			"poi_id": entry[0], "note": entry[2], "district": "orchardfall",
		})

	var building: Dictionary = area.get("building", {})
	if not building.is_empty():
		var door := _door_cell(building)
		map.marker(root, doors, "Doorway_cider_house", door, {
			"target_scene": String(building["interior"]),
			"target_spawn": "PlayerSpawn",
			"prompt": "Enter",
		})
		map.marker(root, root, "Door_cider_house", door + Vector2i(0, 1))

	# Every area is somewhere the player can be sent directly — by a save, by a
	# death, by the debug spawner — so every one needs a default.
	var first: Array = area["exits"][0]
	map.marker_at(root, root, "PlayerSpawn",
		_span_centre(_edge_cell(size, String(first[0]), int(first[1]), 2),
			String(first[0]), int(first[2])))


## Wolves, scattered.
##
## **Placed at build time, not at run time.** The randomness goes through the
## builder's seeded generator like everything else in the map (GDD §12 rule 5),
## so "random" here means *arbitrary but identical on every run* — which is the
## only kind of random a map can have and still be a place. Two players
## describing the same clearing are describing the same clearing, and a bug that
## only happens with a wolf in the doorway can be reproduced.
##
## The rules are all about where they may **not** go. Random placement with no
## exclusions puts one on the tile you arrive on, which reads as the game
## cheating rather than as the wood being dangerous.
func _add_wolves(root: Node2D, area: Dictionary, layers: Array[TileMapLayer]) -> void:
	var size: Vector2i = area["size"]
	var first: Array = area["exits"][0]
	var arrival := _edge_cell(size, String(first[0]), int(first[1]), 2)
	var reached := map.flood(layers, arrival, size)
	if reached.is_empty():
		return

	# Every tile the player can be standing on the instant a scene loads: the
	# default spawn and the far side of every edge they can walk in through.
	var arrivals: Array[Vector2i] = [arrival]
	for exit in area["exits"]:
		for i in range(int(exit[2])):
			arrivals.append(_edge_cell(size, String(exit[0]), int(exit[1]) + i, 2))
			arrivals.append(_edge_cell(size, String(exit[0]), int(exit[1]) + i, 0))
	var building: Dictionary = area.get("building", {})
	if not building.is_empty():
		arrivals.append(_door_cell(building) + Vector2i(0, 1))

	var candidates: Array[Vector2i] = []
	for cell in reached:
		var at: Vector2i = cell
		if at.x < 2 or at.y < 2 or at.x >= size.x - 2 or at.y >= size.y - 2:
			continue
		var clear := true
		for spot in arrivals:
			if _tile_distance(at, spot) < SAFE_TILES:
				clear = false
				break
		if not clear:
			continue
		# Not standing on the thing the player came to look at, either.
		for entry in area["pois"]:
			if _tile_distance(at, entry[1]) < 2:
				clear = false
				break
		if clear:
			candidates.append(at)
	candidates.sort()                       # `flood` returns a set; order it or the
	                                        # seed stops meaning anything.
	if candidates.is_empty():
		map.fail("%s: nowhere to put a wolf that is not on top of the player"
			% [area["id"]])
		return

	var pack := map.group(root, "EnemyMarkers")
	var placed: Array[Vector2i] = []
	var wanted := _rng.randi_range(PACKS_MIN, PACKS_MAX)
	var guard := 0
	while placed.size() < wanted and guard < 400:
		guard += 1
		var lead: Vector2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var too_close := false
		for other in placed:
			if _tile_distance(lead, other) < PACK_GAP:
				too_close = true
				break
		if too_close:
			continue
		placed.append(lead)

		# Pairs, per the roster line. The second wolf goes on an adjacent
		# walkable tile if there is one, and is simply skipped if there is not —
		# a lone wolf in a tight row of trees is better than one inside a tree.
		var pair: Array[Vector2i] = [lead]
		var nudges: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
		var beside: Vector2i = lead + nudges[_rng.randi_range(0, nudges.size() - 1)]
		if candidates.has(beside):
			pair.append(beside)

		for i in range(pair.size()):
			map.marker(root, pack, "Wolf_%d_%d" % [placed.size(), i], pair[i],
				{"enemy_id": "forest_wolf"})

	print("  %s: %d wolves in %d packs" % [area["id"], pack.get_child_count(), placed.size()])


static func _tile_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _span_centre(cell: Vector2i, facing: String, span: int) -> Vector2:
	var pos := GreyboxMap.centre(cell)
	var slide := (span - 1) * 0.5 * GreyboxMap.TILE
	if facing in ["north", "south"]:
		pos.x += slide
	else:
		pos.y += slide
	return pos


# ---------------------------------------------------------------- assertions

## Everything a screenshot of this area would not tell you.
func _assert_area(layers: Array[TileMapLayer], area: Dictionary,
		overhead: TileMapLayer) -> void:
	var id: String = area["id"]
	var size: Vector2i = area["size"]
	var first: Array = area["exits"][0]
	var from := _edge_cell(size, String(first[0]), int(first[1]), 2)

	var reached := map.flood(layers, from, size)
	if reached.is_empty():
		map.fail("%s: the arrival tile %s is inside something solid" % [id, from])
		return

	var stranded: Array[String] = []
	for exit in area["exits"]:
		# The trigger row itself: if the player cannot stand on it, the way out
		# is decorative.
		for i in range(int(exit[2])):
			var cell := _edge_cell(size, String(exit[0]), int(exit[1]) + i, 0)
			if not reached.has(cell):
				stranded.append("exit %s %s" % [exit[0], cell])
	for entry in area["pois"]:
		if not reached.has(entry[1]):
			stranded.append("poi %s %s" % [entry[0], entry[1]])
	var building: Dictionary = area.get("building", {})
	if not building.is_empty():
		# The doorstep, not the doorway — doors are solid.
		var step := _door_cell(building) + Vector2i(0, 1)
		if not reached.has(step):
			stranded.append("cider house doorstep %s" % step)
	if not stranded.is_empty():
		map.fail("%s: unreachable from the arrival point: %s" % [id, stranded])
		return

	# The border has to hold everywhere it is not an opening. A gap in it is an
	# invisible bug: the player walks into the trees, keeps going, and ends up
	# standing outside the map with the camera unclamped.
	var leaked: Array[Vector2i] = []
	for cell in reached:
		var at: Vector2i = cell
		var on_edge: bool = at.x == 0 or at.y == 0 or at.x == size.x - 1 or at.y == size.y - 1
		if not on_edge:
			continue
		var is_exit := false
		for exit in area["exits"]:
			for i in range(int(exit[2])):
				if _edge_cell(size, String(exit[0]), int(exit[1]) + i, 0) == at:
					is_exit = true
		if not is_exit:
			leaked.append(at)
	if not leaked.is_empty():
		map.fail("%s: the border is open at %d cells that are not exits, e.g. %s"
			% [id, leaked.size(), leaked.slice(0, 6)])
		return

	# Nothing on the Overhead layer may sit over ground the player can stand on.
	# It draws above the actors unconditionally, so one tile in the wrong place
	# erases the player from the waist down as they walk under it.
	var covered: Array[Vector2i] = []
	for cell in reached:
		var at2: Vector2i = cell
		if overhead.get_cell_atlas_coords(at2) != Vector2i(-1, -1):
			covered.append(at2)
	if not covered.is_empty():
		map.fail("%s: overhead tiles cover %d walkable cells, e.g. %s"
			% [id, covered.size(), covered.slice(0, 6)])
		return

	print("  %s: %d walkable cells, every exit and POI reachable, border holds"
		% [id, reached.size()])


# ------------------------------------------------------------------ interior

func _build_interior(tileset: TileSet, entry: Array) -> void:
	var id: String = entry[0]
	var size: Vector2i = entry[1]
	var door_offset: int = entry[2]

	var ground := map.new_layer("Ground", tileset, GreyboxMap.Z_GROUND)
	var objects := map.new_layer("Objects", tileset, GreyboxMap.Z_OBJECTS)
	objects.y_sort_enabled = true

	map.fill(ground, Rect2i(0, 0, size.x, size.y), "floorboards")
	for x in range(size.x):
		map.put(objects, Vector2i(x, 0), "wall")
		map.put(objects, Vector2i(x, size.y - 1), "wall")
	for y in range(size.y):
		map.put(objects, Vector2i(0, y), "wall")
		map.put(objects, Vector2i(size.x - 1, y), "wall")
	for x in [2, size.x - 3]:
		map.put(objects, Vector2i(x, 0), "window")

	var door := Vector2i(door_offset, size.y - 1)
	map.put(objects, door, "door")
	for feature in entry[3]:
		map.put(objects, feature[1], String(feature[0]))

	var root := Node2D.new()
	root.name = id.to_pascal_case()
	root.y_sort_enabled = true
	for layer in [ground, objects]:
		root.add_child(layer)
		layer.owner = root

	var pois := map.group(root, "PointsOfInterest")
	for poi in entry[4]:
		map.marker(root, pois, "Poi_" + String(poi[0]), poi[1], {
			"poi_id": poi[0], "note": poi[2], "district": "interior",
		})

	var doors := map.group(root, "Doorways")
	map.marker(root, doors, "Doorway_out", door, {
		"target_scene": ZONE_DIR + "/cider_yard_level.tscn",
		"target_spawn": "Door_cider_house",
		"prompt": "Leave",
	})
	map.marker(root, root, "PlayerSpawn", Vector2i(door_offset, size.y - 3))

	var layers: Array[TileMapLayer] = [ground, objects]
	var reached := map.flood(layers, Vector2i(door_offset, size.y - 3), size)
	if not reached.has(door + Vector2i(0, -1)):
		map.fail("%s: the doorstep is not reachable from the spawn" % id)

	var map_path := "%s/interiors/%s.tscn" % [ZONE_DIR, id]
	@warning_ignore("return_value_discarded")
	map.save_scene(root, map_path)
	@warning_ignore("return_value_discarded")
	map.save_level(map_path, "%s/interiors/%s_level.tscn" % [ZONE_DIR, id],
		id.to_pascal_case() + "Level")
	print("interior %s: %dx%d tiles" % [id, size.x, size.y])
