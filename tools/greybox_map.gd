class_name GreyboxMap
extends RefCounted
## The parts of map generation that are not about any particular map.
##
## Extracted when Orchardfall arrived and `tools/build_greybox.gd` was about to
## grow a second copy of the tile index, the layer constructor and the flood
## fill. The flood fill in particular is the thing that catches "this village
## looks completely correct and cannot be walked", and a second, drifting copy
## of it is worse than no second zone.
##
## Layout and assertions stay in the per-map tools. This is scaffolding.

const TILE := 64
const ATLAS_COLS := 4

## Draw order.
##
## **Objects must share the player's z_index, which is 0.** `z_index` is checked
## before y-sorting, so a props layer at z_index 1 draws over the player from
## every position — walk up to a wall and you vanish behind it. The layer is
## y-sorted instead, and the actors are ordinary participants in that sort.
const Z_GROUND := -1
const Z_OBJECTS := 0
const Z_OVERHEAD := 1

const TILESET_PATH := "res://resources/tilesets/greybox.tres"
const TEXTURE_PATH := "res://art/tilesets/greybox_64.png"

## Must match `tools/gen_greybox_tileset.py`, in order. Name, solid.
const TILES: Array = [
	["dirt_path", false], ["grass_yard", false], ["cobble", false], ["floorboards", false],
	["wall", true], ["wall_inner", true], ["roof", false], ["fence", true],
	["door", true], ["window", true], ["hearth", false], ["well", true],
	["plot_empty", false], ["plot_ruined", false], ["stockpile", true], ["bed_save", false],
	["gate", true], ["npc_marker", false], ["blight_creep", true], ["void", true],
	["bell", true], ["garden", false], ["tent", true], ["rubble_wall", true],
	["chest", true], ["shrine", true],
	# Orchardfall.
	["orchard_tree", true], ["dead_tree", true], ["tall_grass", false], ["crop_row", false],
	["water", true], ["shallows", false], ["bridge", false], ["rock", true],
	["ruin_wall", true], ["signpost", true],
]

## The `Level` wrapper each generated map needs to be playable. Boilerplate, and
## generated rather than copied for the usual reason: six near-identical scenes
## maintained by hand drift, and the drift is silent until somebody walks into
## the one that was missed.
const LEVEL_TEMPLATE := """[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://levels/level.gd" id="1_level"]
[ext_resource type="PackedScene" path="{map}" id="2_map"]
[ext_resource type="PackedScene" path="res://actors/player/player.tscn" id="3_player"]
[ext_resource type="PackedScene" path="res://camera/camera_rig.tscn" id="4_camera"]
[ext_resource type="PackedScene" path="res://ui/debug_overlay.tscn" id="5_overlay"]
[ext_resource type="Script" path="res://ui/world_view.gd" id="9_worldview"]

[node name="{root}" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_level")
map_path = NodePath("Map")
player_path = NodePath("Player")
camera_path = NodePath("CameraRig")
spawn_marker = "{spawn}"
is_safe = {safe}

[node name="WorldView" type="SubViewportContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("9_worldview")

[node name="SubViewport" type="SubViewport" parent="WorldView"]
handle_input_locally = false
size = Vector2i(1280, 720)
render_target_update_mode = 4

[node name="World" type="Node2D" parent="WorldView/SubViewport"]
y_sort_enabled = true

[node name="Map" parent="WorldView/SubViewport/World" instance=ExtResource("2_map")]

[node name="Player" parent="WorldView/SubViewport/World" instance=ExtResource("3_player")]

[node name="CameraRig" parent="WorldView/SubViewport/World" instance=ExtResource("4_camera")]

[node name="DebugOverlay" parent="." instance=ExtResource("5_overlay")]
player_path = NodePath("../WorldView/SubViewport/World/Player")
"""

var index := {}
var failures := 0


func _init() -> void:
	for i in TILES.size():
		index[TILES[i][0]] = Vector2i(i % ATLAS_COLS, i / ATLAS_COLS)


# ------------------------------------------------------------------ tileset

func build_tileset() -> TileSet:
	var texture: Texture2D = load(TEXTURE_PATH)
	if texture == null:
		fail("missing %s — run tools/gen_greybox_tileset.py first" % TEXTURE_PATH)
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
		fail("%s is %s, expected %s for %d tiles — rerun tools/gen_greybox_tileset.py, then `godot --headless --path . --import`"
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
		# centre. Moving it to the tile's base would sort a row-N tile at exactly
		# the feet of a player standing on row N+1, which is the one position
		# players actually occupy when walking along a wall.
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
		fail("collision missing: %d of %d solid tiles have polygons" % [solid, expected_solid])
	else:
		print("collision: %d/%d solid tiles have polygons" % [solid, expected_solid])
	print("tileset: %d tiles, %d solid" % [TILES.size(), expected_solid])
	return tileset


# ------------------------------------------------------------------- tiles

func new_layer(layer_name: String, tileset: TileSet, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z
	return layer


func put(layer: TileMapLayer, cell: Vector2i, tile_name: String) -> void:
	if not index.has(tile_name):
		push_error("unknown tile '%s'" % tile_name)
		return
	layer.set_cell(cell, 0, index[tile_name])


func fill(layer: TileMapLayer, rect: Rect2i, tile_name: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			put(layer, Vector2i(x, y), tile_name)


func tile_at(layers: Array[TileMapLayer], cell: Vector2i) -> String:
	for i in range(layers.size() - 1, -1, -1):
		var atlas := layers[i].get_cell_atlas_coords(cell)
		if atlas == Vector2i(-1, -1):
			continue
		return String(TILES[atlas.y * ATLAS_COLS + atlas.x][0])
	return ""


func solid_at(layers: Array[TileMapLayer], cell: Vector2i, opened: Dictionary = {}) -> bool:
	if opened.has(cell):
		return false
	for layer in layers:
		var atlas := layer.get_cell_atlas_coords(cell)
		if atlas == Vector2i(-1, -1):
			continue
		var i: int = atlas.y * ATLAS_COLS + atlas.x
		if i < TILES.size() and TILES[i][1]:
			return true
	return false


## Four-way flood fill over everything not blocked by a solid tile on any layer.
## Cells in `opened` are treated as clear, which is how a rebuild is simulated
## without editing the map and putting it back.
func flood(layers: Array[TileMapLayer], from: Vector2i, size: Vector2i,
		opened: Dictionary = {}) -> Dictionary:
	var seen := {}
	if solid_at(layers, from, opened):
		return seen
	var queue: Array[Vector2i] = [from]
	seen[from] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			if seen.has(next) or solid_at(layers, next, opened):
				continue
			seen[next] = true
			queue.append(next)
	return seen


# ------------------------------------------------------------------- nodes

static func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


func group(root: Node2D, group_name: String) -> Node2D:
	var existing := root.get_node_or_null(NodePath(group_name)) as Node2D
	if existing != null:
		return existing
	var node := Node2D.new()
	node.name = group_name
	root.add_child(node)
	node.owner = root
	return node


func marker(root: Node2D, parent: Node2D, marker_name: String, cell: Vector2i,
		meta: Dictionary = {}) -> Marker2D:
	return marker_at(root, parent, marker_name, centre(cell), meta)


## The same, in pixels. Edge openings are an even number of tiles wide, so their
## centre falls on a tile boundary rather than in a tile.
func marker_at(root: Node2D, parent: Node2D, marker_name: String, pos: Vector2,
		meta: Dictionary = {}) -> Marker2D:
	var node := Marker2D.new()
	node.name = marker_name
	node.position = pos
	for key in meta:
		node.set_meta(StringName(key), meta[key])
	parent.add_child(node)
	node.owner = root
	return node


# ------------------------------------------------------------------ output

func save(resource: Resource, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		fail("failed to save %s (%d)" % [path, error])
		return false
	print("wrote %s" % path)
	return true


func save_scene(root: Node2D, path: String) -> bool:
	var packed := PackedScene.new()
	@warning_ignore("return_value_discarded")
	packed.pack(root)
	var ok := save(packed, path)
	# The tools build these nodes outside any tree, so nothing else will free
	# them and the engine reports leaked RIDs on exit.
	root.free()
	return ok


## Write the `Level` wrapper that makes a generated map playable.
func save_level(map_path: String, level_path: String, root_name: String,
		spawn: String = "PlayerSpawn", safe: bool = true) -> bool:
	var text: String = LEVEL_TEMPLATE.format({
		"map": map_path, "root": root_name, "spawn": spawn,
		"safe": "true" if safe else "false",
	})
	DirAccess.make_dir_recursive_absolute(level_path.get_base_dir())
	var file := FileAccess.open(level_path, FileAccess.WRITE)
	if file == null:
		fail("failed to write %s" % level_path)
		return false
	file.store_string(text)
	file.close()
	print("wrote %s" % level_path)
	return true


func fail(message: String) -> void:
	failures += 1
	push_error(message)
