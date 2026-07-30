extends SceneTree
## Builds the greybox TileSet, the Ambry village scene, and its interiors.
##
##     godot --headless --path . --script res://tools/build_greybox.gd
##
## Run after `python3 tools/gen_greybox_tileset.py`. All outputs are committed,
## so this only needs re-running when the tile list or the village layout below
## changes — and after that, the scenes are normal Godot scenes you can open and
## edit by hand.
##
## Why a script instead of hand-written `.tres` / `.tscn`: a TileSet's atlas
## sources and per-tile collision polygons, and a TileMapLayer's packed cell
## data, are formats that are easy to get subtly wrong by hand and produce
## silent breakage rather than a parse error. Building them through the engine's
## own API means they are correct by construction.

const TILE := 64
const ATLAS_COLS := 4

## Draw order.
##
## **Objects must share the player's z_index, which is 0.** `z_index` is checked
## before y-sorting, so a props layer at z_index 1 draws over the player from
## every position — walk up to a wall and you vanish behind it. The layer is
## y-sorted instead, and the actors are ordinary participants in that sort.
##
## Ground goes below because it is never something you stand in front of.
## Overhead is roofs, which are always above and have no collision.
const Z_GROUND := -1
const Z_OBJECTS := 0
const Z_OVERHEAD := 1

const TILESET_PATH := "res://resources/tilesets/greybox.tres"
const TEXTURE_PATH := "res://art/tilesets/greybox_64.png"
const VILLAGE_PATH := "res://levels/ambry/ambry.tscn"
const INTERIOR_DIR := "res://levels/ambry/interiors"

# The single source of truth, shared with `tools/build_orchardfall.gd`. It must
# match `tools/gen_greybox_tileset.py`, in order.
const TILES: Array = GreyboxMap.TILES

# --------------------------------------------------------------------------
# Ambry — two districts. See docs/AMBRY.md.
#
# Laid out rather than drawn: buildings are rects with a door, paths are runs
# between them. That keeps the layout editable as intent ("move the smith two
# tiles east") instead of as a wall of characters.
#
# The shape is doing narrative work. The gate is south, so the player arrives
# from the valley and the blight is always beyond the north edge. The square
# with its well, hearth and bell is dead centre, because the warmth pillar wants
# a place the player returns to without being sent.
#
# The load-bearing structure is the wall at WALL_ROW. Ambry lost its northern
# half early; the breach was packed with rubble and everything behind it
# abandoned. **The north district is sealed until the breach is rebuilt** — the
# wall is a gate, not a stat, and repairing it is the largest single payoff in
# the game. There is an assertion below that it really is sealed, because a
# north district that is accidentally walkable from day one would be invisible
# to everything except a person walking it.
# --------------------------------------------------------------------------

const MAP_W := 48
const MAP_H := 42

## The wall dividing the village. Everything north of these rows is the locked
## district; everything south is where the player starts.
##
## Two rows thick, not one. A town wall the same thickness as a cottage's back
## wall does not read as the thing the whole northern half is lost behind — and
## at this zoom the difference between 64px and 128px of masonry is the
## difference between a boundary and a decision.
const WALL_ROWS: Array[int] = [14, 15]
const WALL_ROW := 14

## Where the wall is broken and packed with rubble. Rebuild project #5 opens it.
const BREACH_X: Array[int] = [22, 23, 24, 25]

## The spine. Runs the whole height of the village, gate to gate, and carries
## every entrance and exit in the game.
const ROAD_X: Array[int] = [23, 24]

## East–west paths. The player should never have to cross open ground to reach
## a door.
const SOUTH_RINGS: Array[int] = [16, 23, 31, 37]
const NORTH_RING := 12

## What came through the breach and was never pushed back. Kept off the north
## spine and off the north ring, so the district is genuinely walkable the day
## the wall goes up — the payoff has to be a place, not another obstacle.
const CREEP_PATCHES: Array = [
	Vector2i(19, 13), Vector2i(20, 13), Vector2i(21, 13), Vector2i(21, 11),
	Vector2i(26, 13), Vector2i(27, 13), Vector2i(28, 13), Vector2i(26, 11),
	Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 6),
	Vector2i(30, 6), Vector2i(31, 6), Vector2i(31, 7),
	Vector2i(41, 5), Vector2i(42, 6), Vector2i(43, 5),
	Vector2i(9, 11), Vector2i(33, 13), Vector2i(13, 13),
]

## name, rect (x, y, w, h), door offset along the south wall, plot id, state,
## district, interior scene ("" for a facade).
##
## state: "built" | "ruined" | "empty" | "derelict"
const BUILDINGS: Array = [
	# The first thing you build. The magistrate put a derelict's deed in your
	# name and never mentioned it; the carpenter was told to expect you and
	# assumes you already knew.
	["home",        Rect2i(3, 25, 8, 6),  3, "home",        "derelict", "south",
		INTERIOR_DIR + "/home_level.tscn"],
	["inn",         Rect2i(3, 32, 8, 5),  3, "inn",         "built",    "south",
		INTERIOR_DIR + "/inn_level.tscn"],
	["forge",       Rect2i(36, 25, 8, 6), 4, "forge",       "built",    "south",
		INTERIOR_DIR + "/forge_level.tscn"],
	["magistrate",  Rect2i(27, 18, 10, 5), 4, "magistrate", "built",    "south",
		INTERIOR_DIR + "/magistrate_hall_level.tscn"],
	# The general store, on the west side of the square. Open and trading from
	# the start, which every other useful building in Ambry is not — the player
	# needs somewhere to spend a coin before they have rebuilt anything.
	#
	# Door on offset 3, which is the only offset that works. At 2 the doorstep
	# lands within three tiles of the carpenter on the ring road; at 4 it lands
	# within three of the child at the well. The assertion below caught both, the
	# same way it caught the inn's eave — a shop whose prompt is stolen by a
	# villager standing outside it is a shop the player cannot enter.
	["sundries",    Rect2i(12, 25, 5, 5),  3, "sundries",    "built",    "south",
		INTERIOR_DIR + "/sundries_level.tscn"],
	["apothecary",  Rect2i(4, 18, 7, 5),  3, "apothecary",  "ruined",   "south", ""],
	["market",      Rect2i(13, 32, 6, 4), 2, "market",      "empty",    "south", ""],
	["watchpost",   Rect2i(36, 32, 5, 4), 2, "watchpost",   "empty",    "south", ""],
	# Shut door, drawn curtain. Nothing to interact with for most of the game,
	# and that is the interaction.
	["hidden_case", Rect2i(26, 32, 5, 5), 2, "hidden_case", "built",    "south", ""],
	# Behind the wall: a project behind a project.
	["archive",     Rect2i(15, 6, 8, 5),  3, "archive",     "ruined",   "north", ""],
]

## Permanent points of interest: id, cell, note, district.
##
## The cell is where the player **stands**, not where the object is — a marker
## sitting inside the well tile is a marker nobody can ever walk to, and the
## reachability assertion below would (correctly) refuse to build the village.
const POIS: Array = [
	["gate",       Vector2i(23, 40), "to the valley",                 "south"],
	# Between the gate and the town, so it is passed going out and coming back,
	# every run. Nobody makes the player look at it; it is where the road goes.
	["gallows",    Vector2i(27, 39), "sentenced here",                "south"],
	["well",       Vector2i(19, 28), "the child, the fox",            "south"],
	["hearth",     Vector2i(26, 26), "the town's fire",               "south"],
	["bell",       Vector2i(22, 25), "rang three times that morning", "south"],
	["allotment",  Vector2i(17, 19), "what the town still grows",     "south"],
	["lean_tos",   Vector2i(32, 27), "the visible cost of losing",    "south"],
	# District "wall": you stand on the *south* side to work on it, but it is
	# counted with the northern five in docs/AMBRY.md because it is the thing
	# that opens them.
	["breach",     Vector2i(23, 16), "rebuild: opens the north",      "wall"],
	["graves",     Vector2i(9, 9),   "the Liar is here",              "north"],
	["shrine",     Vector2i(38, 10), "older than the town",           "north"],
	["north_road", Vector2i(23, 5),  "the short way to Orchardfall",  "north"],
]

## The eight rebuild projects (GDD §15 A4 caps it at eight). id matches either a
## building plot or a POI; `requires` is another project id or "".
##
## The gallows is the important one: it costs materials, grants no capability,
## and what it buys is the town's reaction. Never dismantling it has to read as
## clearly as dismantling it — it is not a good/evil switch, and nothing scores
## it.
const PROJECTS: Array = [
	["home",       "trivial", ""],
	["apothecary", "low",     ""],
	["market",     "medium",  ""],
	["watchpost",  "medium",  ""],
	["breach",     "high",    ""],
	["archive",    "medium",  "breach"],
	["forge",      "high",    ""],
	["gallows",    "low",     ""],
]

## The graves, in the northern district, nearest the thing that made them. The
## list grows if the player is slow, which is the cheapest pressure mechanic
## available: no timer, no fail state, just a row that gets longer.
const GRAVES: Array = [
	Vector2i(6, 8), Vector2i(8, 8), Vector2i(10, 8), Vector2i(12, 8),
]

## Refugee lean-tos, pitched in the open ground east of the square where the
## fire is. Also a growing list: this is what losing looks like from inside the
## one place that is meant to be safe.
const LEAN_TOS: Array = [
	Vector2i(31, 26), Vector2i(34, 26), Vector2i(31, 29), Vector2i(34, 29),
]

## The town's stacked repair materials, piled against a breach it cannot afford
## to close. They are the reason the player knows what the wall wants.
const MATERIAL_PILES: Array = [
	Vector2i(20, 17), Vector2i(21, 17), Vector2i(26, 17),
]

## Interiors. id, room size in tiles, door offset along the south wall,
## features [tile, cell], points of interest [id, cell, note].
##
## Four rooms, not three: the home holds the chest and the bed and will be the
## most-visited room in the game. If four ever turns out to be one too many, the
## magistrate's hall is the one to drop back to a facade — it is narrative
## rather than mechanical.
const INTERIORS: Array = [
	["home", Vector2i(9, 7), 4,
		[["chest", Vector2i(2, 2)], ["bed_save", Vector2i(6, 2)]],
		[
			["home_chest", Vector2i(2, 3), "store the haul"],
			["home_bed", Vector2i(6, 3), "save + rest"],
		]],
	["inn", Vector2i(12, 8), 5,
		[["hearth", Vector2i(2, 2)], ["stockpile", Vector2i(5, 2)],
			["bed_save", Vector2i(8, 2)], ["bed_save", Vector2i(10, 2)]],
		[["inn_bed", Vector2i(8, 3), "save + rest, until your home is yours"]]],
	["forge", Vector2i(10, 7), 4,
		[["hearth", Vector2i(7, 2)], ["stockpile", Vector2i(2, 2)]],
		[["anvil", Vector2i(7, 3), "weapon damage, then reach"]]],
	["magistrate_hall", Vector2i(11, 7), 5,
		[["chest", Vector2i(5, 2)]],
		[["ledger", Vector2i(5, 3), "your name, wrongly, still open on the desk"]]],
	# Shelves down both long walls and a counter she stands behind. The crate by
	# the door is the one she tells you to mind, and it has been there four
	# months — a line of dialogue that costs one tile.
	["sundries", Vector2i(11, 7), 4,
		[["stockpile", Vector2i(2, 2)], ["stockpile", Vector2i(3, 2)],
			["stockpile", Vector2i(8, 2)], ["chest", Vector2i(6, 2)],
			["stockpile", Vector2i(2, 5)]],
		[["counter", Vector2i(6, 3), "Maren Tallow: buy and sell"]]],
]

## Where each named NPC stands: id, which map, cell. Ten of them — §2's cast
## plus the carpenter (GDD §15 A6).
##
## The carpenter stands at whatever you can build next, which makes him the
## quest marker without a quest log. He starts at your derelict.
const NPCS: Array = [
	# On the ring road, not on your doorstep. He belongs next to whatever you can
	# build next, and the first of those is your own front door — which is close
	# enough that he was stealing its prompt. The assertion below is what found
	# it, after `doorway_test` started failing for no visible reason.
	["carpenter",       "ambry", Vector2i(12, 31)],
	["child",           "ambry", Vector2i(18, 28)],
	["fox",             "ambry", Vector2i(21, 27)],
	["reluctant_guard", "ambry", Vector2i(22, 40)],
	["unrepentant",     "ambry", Vector2i(25, 39)],
	["hidden_case",     "ambry", Vector2i(28, 37)],
	["magistrate",      "magistrate_hall", Vector2i(5, 3)],
	["smith",           "forge", Vector2i(6, 3)],
	["innkeeper",       "inn", Vector2i(4, 3)],
	# Works out of the inn until her own building is rebuilt. Rebuilding visibly
	# moves a person rather than unlocking a menu.
	["apothecary",      "inn", Vector2i(7, 4)],
	# Behind her counter. The eleventh speaking part — see GDD §15 A11 for why
	# the cast budget moved, and `docs/AMBRY.md` for who she is.
	["shopkeeper",      "sundries", Vector2i(5, 3)],
]

var _index := {}
var _project := {}
var _failures := 0


func _init() -> void:
	for i in TILES.size():
		_index[TILES[i][0]] = Vector2i(i % ATLAS_COLS, i / ATLAS_COLS)
	for entry in PROJECTS:
		_project[entry[0]] = {"cost": entry[1], "requires": entry[2]}

	var tileset := _build_tileset()
	_save(tileset, TILESET_PATH)
	_build_village(tileset)
	for entry in INTERIORS:
		_build_interior(tileset, entry)

	if _failures > 0:
		push_error("build_greybox: %d assertion(s) failed" % _failures)
		quit(1)
		return
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

	# The atlas has to be big enough for the tile list, and Godot's importer
	# caches the old image — adding tiles to the Python generator without
	# reimporting leaves the last row missing. create_tile() then fails per tile
	# with an error that scrolls past, and everything downstream keeps going.
	var rows: int = ceili(float(TILES.size()) / ATLAS_COLS)
	var wanted := Vector2i(ATLAS_COLS * TILE, rows * TILE)
	if texture.get_size() != Vector2(wanted):
		_fail("%s is %s, expected %s for %d tiles — rerun tools/gen_greybox_tileset.py, then `godot --headless --path . --import`"
			% [TEXTURE_PATH, texture.get_size(), wanted, TILES.size()])
		return null

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)

	# Attach the source *before* touching per-tile collision. A TileData reaches
	# its physics layers through the TileSet that owns it, so on a detached
	# source add_collision_polygon(0) has no layer 0 to add to — it pushes an
	# error and does nothing, and the result is a tileset that looks complete
	# and has no collision at all.
	tileset.add_source(source, 0)

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])

	var solid := 0
	for i in TILES.size():
		var coords: Vector2i = Vector2i(i % ATLAS_COLS, i / ATLAS_COLS)
		source.create_tile(coords)
		# `y_sort_origin` is deliberately left at its default of 0 — the tile's
		# centre. It is tempting to move it to the tile's base, and that is
		# wrong here: a tile at row N would then sort at exactly the feet of a
		# player standing on row N+1, which is the one position players actually
		# occupy when walking along a wall. Ties resolve by tree order, so it
		# would work by accident rather than by rule.
		#
		# At the centre there is no reachable tie: a player below a wall sorts a
		# half-tile after it (in front), a player above it a half-tile before
		# (behind), and the row the wall occupies is solid so nobody stands
		# there. Revisit if wall art ever gets taller than one tile.
		if TILES[i][1]:
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
			if data.get_collision_polygons_count(0) > 0:
				solid += 1

	# Verified rather than assumed, because the failure above was silent in
	# every way that mattered.
	var expected_solid: int = TILES.filter(func(t): return t[1]).size()
	if solid != expected_solid:
		_fail("collision missing: %d of %d solid tiles have polygons" % [solid, expected_solid])
	else:
		print("collision: %d/%d solid tiles have polygons" % [solid, expected_solid])
	print("tileset: %d tiles, %d solid" % [TILES.size(), expected_solid])
	return tileset


# ------------------------------------------------------------------ village

func _build_village(tileset: TileSet) -> void:
	var ground := _new_layer("Ground", tileset, Z_GROUND)
	var objects := _new_layer("Objects", tileset, Z_OBJECTS)
	var overhead := _new_layer("Overhead", tileset, Z_OVERHEAD)
	objects.y_sort_enabled = true

	# Ground. Grass first, then roads, then the square on top of them — the
	# square should read as one cobbled surface, not as a road crossing it.
	_fill(ground, Rect2i(0, 0, MAP_W, MAP_H), "grass_yard")

	for row in SOUTH_RINGS:
		_fill(ground, Rect2i(2, row, MAP_W - 4, 1), "dirt_path")
	_fill(ground, Rect2i(2, NORTH_RING, MAP_W - 4, 1), "dirt_path")
	for x in ROAD_X:
		_fill(ground, Rect2i(x, 0, 1, MAP_H), "dirt_path")

	_fill(ground, Rect2i(17, 24, 13, 7), "cobble")
	_fill(ground, Rect2i(14, 18, 7, 4), "garden")

	# The blight beyond the north edge, and the tongue of it that came through
	# the breach and has never been pushed back.
	_fill(ground, Rect2i(0, 0, MAP_W, 2), "blight_creep")
	for x in range(0, MAP_W, 3):
		_put(ground, Vector2i(x, 2), "blight_creep")
	for x in ROAD_X:
		# The north road still runs out through it.
		_fill(ground, Rect2i(x, 0, 1, 3), "dirt_path")
	for cell in CREEP_PATCHES:
		_put(ground, cell, "blight_creep")

	# ---- the wall, the whole width, rubble where it is broken.
	for row in WALL_ROWS:
		for x in range(1, MAP_W - 1):
			_put(objects, Vector2i(x, row), "wall")
		for x in BREACH_X:
			_put(objects, Vector2i(x, row), "rubble_wall")
	for cell in MATERIAL_PILES:
		_put(objects, cell, "stockpile")

	# ---- edges. Fences inside, void outside: the outer columns are what stops
	# a player simply walking around the end of the wall.
	for y in range(MAP_H):
		_put(objects, Vector2i(0, y), "void")
		_put(objects, Vector2i(MAP_W - 1, y), "void")
	for y in range(4, MAP_H - 1):
		if y in WALL_ROWS:
			continue
		_put(objects, Vector2i(1, y), "fence")
		_put(objects, Vector2i(MAP_W - 2, y), "fence")
	for x in range(1, MAP_W - 1):
		_put(objects, Vector2i(x, MAP_H - 1), "fence")   # south edge
		_put(objects, Vector2i(x, 3), "fence")           # north edge

	# The south gate is **open**, and it is the only opening in Ambry's fence.
	# It used to be two solid `gate` tiles, which was correct while there was
	# nowhere to go: the town was the game. Now the valley is out there, so the
	# gate is a gap with a post either side, and walking into it leaves
	# (`world/gateway.gd`). No keypress — you are already walking south.
	for x in ROAD_X:
		objects.erase_cell(Vector2i(x, MAP_H - 1))
		_put(ground, Vector2i(x, MAP_H - 1), "dirt_path")
	_put(objects, Vector2i(ROAD_X[0] - 1, MAP_H - 1), "gate")
	_put(objects, Vector2i(ROAD_X[-1] + 1, MAP_H - 1), "gate")

	# The north road stays shut. It is behind the wall, so nobody can reach it
	# until the breach is rebuilt, and there is nothing on the far side yet —
	# it is the short way to Orchardfall (docs/AMBRY.md) and it is mid-game.
	for x in ROAD_X:
		_put(objects, Vector2i(x, 3), "gate")

	# ---- the square. Well and hearth flank the spine so the player walks
	# between them on the way in from the gate.
	_fill(objects, Rect2i(19, 26, 2, 2), "well")
	_fill(objects, Rect2i(26, 26, 2, 2), "hearth")
	_put(objects, Vector2i(22, 24), "bell")

	# ---- the gallows, on the road between the gate and the town.
	_fill(ground, Rect2i(26, 38, 3, 2), "plot_ruined")
	_put(objects, Vector2i(27, 38), "fence")

	for cell in GRAVES:
		_put(ground, cell, "plot_ruined")
		_put(objects, cell, "fence")
	for cell in LEAN_TOS:
		_put(objects, cell, "tent")
	_fill(objects, Rect2i(38, 8, 2, 2), "shrine")

	for entry in BUILDINGS:
		_place_building(ground, objects, overhead, entry)

	var root := Node2D.new()
	root.name = "Ambry"
	root.y_sort_enabled = true
	for layer in [ground, objects, overhead]:
		root.add_child(layer)
		layer.owner = root

	_add_markers(root)

	var layers: Array[TileMapLayer] = [ground, objects, overhead]
	_assert_road_clear(layers)
	_assert_layout(layers, overhead)

	var packed := PackedScene.new()
	packed.pack(root)
	_save(packed, VILLAGE_PATH)
	# The tool builds these nodes outside any tree, so nothing else will free
	# them and the engine reports leaked RIDs on exit.
	root.free()
	print("village: %dx%d tiles (%dx%d px), %d buildings, %d POIs, %d npc markers"
		% [MAP_W, MAP_H, MAP_W * TILE, MAP_H * TILE, BUILDINGS.size(), POIS.size(),
			_npcs_in("ambry").size()])


## The spine from the south gate to the square carries every entrance and exit
## in the game. Nothing may stand on it.
func _assert_road_clear(layers: Array[TileMapLayer]) -> void:
	var blocked: Array[Vector2i] = []
	for y in range(int(WALL_ROWS.max()) + 1, MAP_H - 1):
		for x in ROAD_X:
			var cell := Vector2i(x, y)
			if _solid_at(layers, cell):
				blocked.append(cell)
	if blocked.is_empty():
		print("road from the gate: clear")
	else:
		_fail("road from the gate is blocked at %s" % [blocked])


## Two things a screenshot cannot tell you, both of which would look completely
## correct until somebody walked them:
##
## 1. Every door in the south district is reachable on foot from the spawn.
## 2. The north district is **not** — it is behind an unrepaired breach, and if
##    it were accidentally open the whole point of the wall would be gone with
##    no visible symptom.
func _assert_layout(layers: Array[TileMapLayer], overhead: TileMapLayer) -> void:
	var spawn := Vector2i(ROAD_X[0], MAP_H - 3)
	var reached := _flood(layers, spawn)
	if reached.is_empty():
		_fail("the player spawn at %s is inside a wall" % [spawn])
		return

	var unreachable: Array[String] = []
	for entry in BUILDINGS:
		if String(entry[5]) != "south":
			continue
		# The doorstep, not the doorway. Doors are solid — they are a wall you
		# open with a keypress, not a gap you walk through — so what has to be
		# reachable is the tile you stand on to press it.
		var step := _door_cell(entry) + Vector2i(0, 1)
		if not reached.has(step):
			unreachable.append("%s doorstep %s" % [entry[0], step])
	for entry in POIS:
		if String(entry[3]) == "north":
			continue
		if not reached.has(entry[1]):
			unreachable.append("poi %s %s" % [entry[0], entry[1]])
	if unreachable.is_empty():
		print("every south door and POI: reachable")
	else:
		_fail("unreachable from the gate: %s" % [unreachable])

	var leaked: Array[Vector2i] = []
	for cell in reached:
		if cell.y < WALL_ROW:
			leaked.append(cell)
	if leaked.is_empty():
		print("north district: sealed (%d cells reachable, none past the wall)" % reached.size())
	else:
		_fail("the north district is walkable from the start — %d cells, e.g. %s"
			% [leaked.size(), leaked.slice(0, 6)])

	# ...and the other half of that promise: once the breach is repaired, every
	# northern POI has to actually be standable. The most expensive project in
	# the game opening onto a district you cannot cross would be a very quiet
	# way to waste the player's whole mid-game.
	# Nothing on the Overhead layer may sit over ground the player can stand on.
	# Overhead draws above the actors unconditionally, so a single tile in the
	# wrong place deletes the player's legs while they walk under it — which
	# looks like a sprite bug or a broken camera, and is neither. This is how
	# the inn's eave was found, after it had been sitting on the ring road
	# through a whole build.
	var covered: Array[String] = []
	for cell in reached:
		var atlas := overhead.get_cell_atlas_coords(cell)
		if atlas != Vector2i(-1, -1):
			covered.append("%s (%s)" % [cell, TILES[atlas.y * ATLAS_COLS + atlas.x][0]])
	if covered.is_empty():
		print("overhead layer: nothing drawn over walkable ground")
	else:
		_fail("overhead tiles cover %d walkable cells, e.g. %s"
			% [covered.size(), covered.slice(0, 6)])

	# Every built building has to be roofed. The failure is quiet — the village
	# still works, it just reads as a floor plan — and it is exactly the kind of
	# thing you stop noticing after the tenth screenshot.
	var open_topped: Array[String] = []
	for entry in BUILDINGS:
		if String(entry[4]) != "built":
			continue
		var rect: Rect2i = entry[1]
		for y in range(rect.position.y + 1, rect.end.y - 1):
			for x in range(rect.position.x + 1, rect.end.x - 1):
				if overhead.get_cell_atlas_coords(Vector2i(x, y)) == Vector2i(-1, -1):
					open_topped.append("%s open at %s" % [entry[0], Vector2i(x, y)])
	if open_topped.is_empty():
		print("roofs: every built building is covered")
	else:
		_fail("you can see the floor of: %s" % [open_topped.slice(0, 6)])

	# Nobody may stand close enough to a doorstep to take its prompt.
	# `InteractorComponent` offers the nearest thing it can find, and a villager
	# parked by a door is a door that cannot be opened — which looks like a
	# broken door, and is a person standing in the wrong place.
	var crowding: Array[String] = []
	for npc in _npcs_in("ambry"):
		for entry in BUILDINGS:
			if String(entry[6]) == "":
				continue
			var step := _door_cell(entry) + Vector2i(0, 1)
			if (Vector2(npc[2]) - Vector2(step)).length() < 3.0:
				crowding.append("%s at %s is on %s's doorstep %s" % [npc[0], npc[2], entry[3], step])
	if crowding.is_empty():
		print("doorsteps: clear of the cast")
	else:
		_fail("npcs standing in doorways: %s" % [crowding])

	var opened := {}
	for row in WALL_ROWS:
		for x in BREACH_X:
			opened[Vector2i(x, row)] = true
	var after := _flood(layers, spawn, opened)
	var stranded: Array[String] = []
	for entry in POIS:
		if String(entry[3]) != "north":
			continue
		if not after.has(entry[1]):
			stranded.append("%s %s" % [entry[0], entry[1]])
	for entry in BUILDINGS:
		if String(entry[5]) != "north":
			continue
		var rect: Rect2i = entry[1]
		var front := Vector2i(rect.position.x + int(entry[2]), rect.end.y)
		if not after.has(front):
			stranded.append("%s front %s" % [entry[0], front])
	if stranded.is_empty():
		print("north district: reachable once the breach is repaired (+%d cells)"
			% (after.size() - reached.size()))
	else:
		_fail("repairing the breach would not reach: %s" % [stranded])


## Four-way flood fill over everything not blocked by a solid tile on any layer.
## Cells in `opened` are treated as clear, which is how a rebuild is simulated
## without editing the map and putting it back.
func _flood(layers: Array[TileMapLayer], from: Vector2i, opened: Dictionary = {}) -> Dictionary:
	var seen := {}
	if _solid_at(layers, from, opened):
		return seen
	var queue: Array[Vector2i] = [from]
	seen[from] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= MAP_W or next.y >= MAP_H:
				continue
			if seen.has(next) or _solid_at(layers, next, opened):
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _solid_at(layers: Array[TileMapLayer], cell: Vector2i, opened: Dictionary = {}) -> bool:
	if opened.has(cell):
		return false
	for layer in layers:
		var atlas := layer.get_cell_atlas_coords(cell)
		if atlas == Vector2i(-1, -1):
			continue
		var index: int = atlas.y * ATLAS_COLS + atlas.x
		if index < TILES.size() and TILES[index][1]:
			return true
	return false


static func _door_cell(entry: Array) -> Vector2i:
	var rect: Rect2i = entry[1]
	return Vector2i(rect.position.x + int(entry[2]), rect.end.y - 1)


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

	var is_derelict := state == "derelict"

	# A derelict is a shell: footings on all four sides, a door frame, no roof
	# and no glass. It is a building you finish rather than a plot you conjure,
	# which is the whole difference between "your home" and "a construction
	# site" — and the reason the first build lands personally.
	var wall_tile := "wall_inner" if is_derelict else "wall"
	_fill(ground, rect, "plot_ruined" if is_derelict else "floorboards")
	for x in range(rect.position.x, rect.end.x):
		_put(objects, Vector2i(x, rect.position.y), wall_tile)
		_put(objects, Vector2i(x, rect.end.y - 1), wall_tile)
	for y in range(rect.position.y, rect.end.y):
		_put(objects, Vector2i(rect.position.x, y), wall_tile)
		_put(objects, Vector2i(rect.end.x - 1, y), wall_tile)

	var door := _door_cell(entry)
	_put(objects, door, "door")
	_put(ground, door, "plot_ruined" if is_derelict else "floorboards")
	_put(ground, door + Vector2i(0, 1), "dirt_path")

	if is_derelict:
		return

	# Windows either side of the door, so a facade reads as a facade.
	if door_offset >= 2:
		_put(objects, door - Vector2i(2, 0), "window")
	if door_offset + 2 < rect.size.x - 1:
		_put(objects, door + Vector2i(2, 0), "window")

	# **The roof.** Without it a building is an open-topped box and the player
	# can read its floorboards from the street, which makes the whole village
	# look like a floor plan rather than a place.
	#
	# It covers everything except the south face, so the wall you walk up to —
	# the door, the windows, the thing that tells you which building this is —
	# stays visible. That is the standard top-down read: roof from above, facade
	# from the front.
	#
	# Strictly inside the footprint, with no eave. There was an eave once and it
	# was a bug: the Overhead layer draws above the actors unconditionally, so a
	# tile of it over walkable ground erases the player from the waist down as
	# they walk past. `_assert_layout` refuses to build a village that does it
	# again — which is also what makes this safe, since a built building's
	# interior is enclosed by solid walls and a solid door, and nothing standing
	# in the street can be under it.
	#
	# A derelict gets none, and that is the point: your home is the one building
	# you can see straight into, because it has no roof yet and you are the one
	# who is going to put it on.
	_fill(overhead, Rect2i(rect.position, Vector2i(rect.size.x, rect.size.y - 1)), "roof")


func _add_markers(root: Node2D) -> void:
	var plots := _group(root, "BuildingPlots")
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
		marker.set_meta("district", entry[5])
		_stamp_project(marker, String(entry[3]))
		plots.add_child(marker)
		marker.owner = root

	var pois := _group(root, "PointsOfInterest")
	for entry in POIS:
		var poi := Marker2D.new()
		poi.name = "Poi_" + String(entry[0])
		poi.position = _centre(entry[1])
		poi.set_meta("poi_id", entry[0])
		poi.set_meta("note", entry[2])
		poi.set_meta("district", entry[3])
		_stamp_project(poi, String(entry[0]))
		pois.add_child(poi)
		poi.owner = root

	_add_npc_markers(root, "ambry")

	# Doorways, and the spot outside each one you come back out to. Emitted as
	# metadata rather than as Area2Ds: the map is data, and `Level` turns these
	# into `world/doorway.tscn` instances when the scene runs.
	var doors := _group(root, "Doorways")
	for entry in BUILDINGS:
		var target: String = entry[6]
		if target == "":
			continue
		var cell := _door_cell(entry)
		var door := Marker2D.new()
		door.name = "Doorway_" + String(entry[3])
		door.position = _centre(cell)
		door.set_meta("target_scene", target)
		door.set_meta("target_spawn", "PlayerSpawn")
		door.set_meta("prompt", "Enter")
		doors.add_child(door)
		door.owner = root

		# Where the interior sends you back to: one tile out, so you are not
		# standing in the doorway you just used.
		var outside := Marker2D.new()
		outside.name = "Door_" + String(entry[3])
		outside.position = _centre(cell + Vector2i(0, 1))
		root.add_child(outside)
		outside.owner = root

	# The way out to the valley. An edge, not a door — walked into rather than
	# pressed (`world/gateway.gd`).
	var gateways := _group(root, "Gateways")
	var out := Marker2D.new()
	out.name = "Gateway_south"
	out.position = Vector2((ROAD_X[0] + ROAD_X.size() * 0.5) * TILE, (MAP_H - 0.5) * TILE)
	out.set_meta("target_scene", "res://levels/orchardfall/valley_road_level.tscn")
	out.set_meta("target_spawn", "Edge_north")
	out.set_meta("facing", "south")
	out.set_meta("span", ROAD_X.size())
	gateways.add_child(out)
	out.owner = root

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	# Just inside the south gate: the player always enters Ambry the same way.
	spawn.position = _centre(Vector2i(ROAD_X[0], MAP_H - 3))
	root.add_child(spawn)
	spawn.owner = root

	# ...and where the valley sends them back to. The same place, named for the
	# edge it is on, so the zone's convention holds all the way to the gate:
	# an exit heading north lands on the neighbour's `Edge_south`.
	var arrive := Marker2D.new()
	arrive.name = "Edge_south"
	arrive.position = _centre(Vector2i(ROAD_X[0], MAP_H - 3))
	root.add_child(arrive)
	arrive.owner = root


func _stamp_project(marker: Marker2D, id: String) -> void:
	if not _project.has(id):
		return
	marker.set_meta("project", true)
	marker.set_meta("cost", _project[id]["cost"])
	marker.set_meta("requires", _project[id]["requires"])


func _add_npc_markers(root: Node2D, where: String) -> void:
	var npcs := _group(root, "NpcMarkers")
	for entry in _npcs_in(where):
		var marker := Marker2D.new()
		marker.name = "Npc_" + String(entry[0])
		marker.position = _centre(entry[2])
		marker.set_meta("npc_id", entry[0])
		npcs.add_child(marker)
		marker.owner = root


func _npcs_in(where: String) -> Array:
	return NPCS.filter(func(entry): return String(entry[1]) == where)


# ----------------------------------------------------------------- interiors

## One room, walls, a door in the south face, and whatever the room is for.
##
## Each interior is a `Level` in its own right (`levels/level.gd`), so
## `world_bounds()` derives the camera from the tiles and a one-room scene needs
## no special handling.
func _build_interior(tileset: TileSet, entry: Array) -> void:
	var id: String = entry[0]
	var size: Vector2i = entry[1]
	var door_offset: int = entry[2]
	var features: Array = entry[3]
	var pois: Array = entry[4]

	var ground := _new_layer("Ground", tileset, Z_GROUND)
	var objects := _new_layer("Objects", tileset, Z_OBJECTS)
	objects.y_sort_enabled = true

	_fill(ground, Rect2i(0, 0, size.x, size.y), "floorboards")
	for x in range(size.x):
		_put(objects, Vector2i(x, 0), "wall")
		_put(objects, Vector2i(x, size.y - 1), "wall")
	for y in range(size.y):
		_put(objects, Vector2i(0, y), "wall")
		_put(objects, Vector2i(size.x - 1, y), "wall")
	for x in [2, size.x - 3]:
		_put(objects, Vector2i(x, 0), "window")

	var door := Vector2i(door_offset, size.y - 1)
	_put(objects, door, "door")

	for feature in features:
		_put(objects, feature[1], String(feature[0]))

	var root := Node2D.new()
	root.name = id.to_pascal_case()
	root.y_sort_enabled = true
	for layer in [ground, objects]:
		root.add_child(layer)
		layer.owner = root

	var pois_node := _group(root, "PointsOfInterest")
	for poi_entry in pois:
		var poi := Marker2D.new()
		poi.name = "Poi_" + String(poi_entry[0])
		poi.position = _centre(poi_entry[1])
		poi.set_meta("poi_id", poi_entry[0])
		poi.set_meta("note", poi_entry[2])
		poi.set_meta("district", "interior")
		pois_node.add_child(poi)
		poi.owner = root

	_add_npc_markers(root, id)

	var doors := _group(root, "Doorways")
	var out := Marker2D.new()
	out.name = "Doorway_out"
	out.position = _centre(door)
	out.set_meta("target_scene", VILLAGE_PATH.replace("ambry.tscn", "ambry_level.tscn"))
	out.set_meta("target_spawn", "Door_" + _plot_for_interior(id))
	# Not "Enter". The same node on the other side of the same door wants the
	# opposite verb, and a prompt that reads "Enter" while you are stood in
	# somebody's kitchen is the kind of small wrongness that adds up.
	out.set_meta("prompt", "Leave")
	doors.add_child(out)
	out.owner = root

	# Two tiles in from the door, so arriving never overlaps the doorway you
	# would immediately walk back through.
	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = _centre(Vector2i(door_offset, size.y - 3))
	root.add_child(spawn)
	spawn.owner = root

	# Same rule inside: the door is solid, so the tile in front of it is what
	# has to be standable. A room you cannot get to the door of is a room you
	# cannot leave.
	var layers: Array[TileMapLayer] = [ground, objects]
	var reached := _flood(layers, Vector2i(door_offset, size.y - 3))
	if not reached.has(door + Vector2i(0, -1)):
		_fail("%s: the doorstep is not reachable from the spawn" % id)

	var packed := PackedScene.new()
	packed.pack(root)
	_save(packed, "%s/%s.tscn" % [INTERIOR_DIR, id])
	root.free()
	print("interior %s: %dx%d tiles, %d POIs, %d npc markers"
		% [id, size.x, size.y, pois.size(), _npcs_in(id).size()])


static func _plot_for_interior(id: String) -> String:
	for entry in BUILDINGS:
		if String(entry[6]).ends_with("/%s_level.tscn" % id):
			return String(entry[3])
	return id


# ------------------------------------------------------------------ helpers

func _group(root: Node2D, group_name: String) -> Node2D:
	var existing := root.get_node_or_null(NodePath(group_name)) as Node2D
	if existing != null:
		return existing
	var node := Node2D.new()
	node.name = group_name
	root.add_child(node)
	node.owner = root
	return node


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


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


func _fail(message: String) -> void:
	_failures += 1
	push_error(message)


func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("failed to save %s (%d)" % [path, error])
		quit(1)
	else:
		print("wrote %s" % path)
