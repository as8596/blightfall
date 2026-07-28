extends Node
## Capture a frame of the prototype room to a PNG, for eyeballing layout
## without a human at the keyboard.
##
##     xvfb-run -a godot --path . tests/screenshot.tscn -- --shot=user://frame.png
##
## Used during development to check that the debug overlay actually fits inside
## 320×180 and that the grey boxes land where the numbers say they do.

const ROOM: PackedScene = preload("res://levels/prototype/prototype_room.tscn")

## `--scene=res://...` captures something other than the prototype room.
var _scene_override: String = ""

@export var settle_frames: int = 90
@export var output_path: String = "user://frame.png"

## `--near` pulls the enemies into the player's face so a combat frame can be
## captured without anyone walking anywhere.
var _pull_enemies_close: bool = false
## `--attack` swings, then waits `_attack_delay` physics ticks before capturing,
## which is how you check the hitbox lands where the numbers say it does.
var _attack: bool = false
var _attack_delay: int = 6

## `--anim` assigns the placeholder animation set, so the pipeline can be
## checked without changing what the project ships with by default.
var _use_placeholder_animations: bool = false

## `--fit` zooms the camera out to frame the whole level, for judging a layout
## rather than playing it.
var _fit_level: bool = false

## `--at=tx,ty` stands the player on a tile, so a specific corner of a level can
## be looked at without walking there. Draw-order bugs only show up next to the
## thing being drawn over you.
var _stand_at: Vector2 = Vector2.INF

## `--face=n|s|e|w` points the player, for checking the directional sprites
## without walking them around.
var _face: String = ""

## `--xp=N` awards experience, for checking a bar that is otherwise empty in
## every fresh scene.
var _grant_xp: int = 0

## `--pointer=x,y` puts the cursor somewhere, in window pixels. Hover states are
## invisible to a harness that never moves the mouse.
var _pointer: Vector2 = Vector2.INF

var _room: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_override = arg.trim_prefix("--scene=")
	if _scene_override != "":
		_room = (load(_scene_override) as PackedScene).instantiate()
	else:
		_room = ROOM.instantiate()
	add_child(_room)
	_capture.call_deferred()


func _capture() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			output_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--frames="):
			settle_frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--boxes"):
			DebugSettings.show_boxes = true
		elif arg.begins_with("--at="):
			var parts := arg.trim_prefix("--at=").split(",")
			if parts.size() == 2:
				_stand_at = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--fit"):
			_fit_level = true
		elif arg.begins_with("--anim"):
			_use_placeholder_animations = true
		elif arg.begins_with("--near"):
			_pull_enemies_close = true
		elif arg.begins_with("--face="):
			_face = arg.trim_prefix("--face=")
		elif arg.begins_with("--xp="):
			_grant_xp = arg.trim_prefix("--xp=").to_int()
		elif arg.begins_with("--pointer="):
			var at := arg.trim_prefix("--pointer=").split(",")
			if at.size() == 2:
				_pointer = Vector2(float(at[0]), float(at[1]))
		elif arg.begins_with("--attack="):
			_attack = true
			_attack_delay = arg.trim_prefix("--attack=").to_int()
		elif arg.begins_with("--attack"):
			_attack = true

	for i in settle_frames:
		await get_tree().process_frame

	var level := _room as Level
	if _fit_level and level != null:
		var bounds := level.world_bounds()
		var view := get_viewport().get_visible_rect().size
		var camera := level.camera
		if camera != null and bounds.size != Vector2.ZERO:
			# Unbound the camera first — room limits would clamp the framing.
			camera.limit_left = -100000
			camera.limit_top = -100000
			camera.limit_right = 100000
			camera.limit_bottom = 100000
			camera.set_target(null)
			camera.position_smoothing_enabled = false
			camera.zoom = Vector2.ONE * minf(view.x / bounds.size.x, view.y / bounds.size.y)
			camera.global_position = bounds.get_center()
		await _wait_ticks(4)

	# Searched for rather than pathed to. The player lives inside the world
	# SubViewport now (`ui/world_view.gd`), the prototype room and `Level` reach
	# it by different routes, and a hard-coded path finds nothing *silently* —
	# which cost an afternoon hunting a drawing bug in a swing that was never
	# actually swung.
	var player := _find_player(_room)
	if _stand_at != Vector2.INF and player != null:
		# Tile coordinates, landing on the tile's centre.
		player.global_position = (_stand_at + Vector2(0.5, 0.5)) * 64.0
		if level != null and level.camera != null:
			level.camera.set_target(player)
		await _wait_ticks(4)

	if _use_placeholder_animations and player != null:
		player.animation.animations = load("res://resources/animation/player_placeholder.tres")
		await _wait_ticks(2)

	if _pull_enemies_close and player != null:
		for node in get_tree().get_nodes_in_group(Targeting.ENEMY_GROUP):
			var enemy := node as BaseEnemy
			if enemy == null:
				continue
			# Park each enemy just inside its own attack range, so this stays
			# right whatever the sprite resolution is.
			var reach: float = enemy.data.attack_range if enemy.data != null else 100.0
			enemy.global_position = player.global_position + Vector2(reach * 0.9, 0)
		await _wait_ticks(20)

	if player == null and (_attack or _use_placeholder_animations or _stand_at != Vector2.INF):
		push_warning("screenshot: no player in this scene — some flags did nothing.")

	if _face != "" and player != null:
		const HEADINGS := {
			"n": Vector2.UP, "s": Vector2.DOWN, "e": Vector2.RIGHT, "w": Vector2.LEFT,
		}
		player.facing = HEADINGS.get(_face, Vector2.DOWN)
		await _wait_ticks(2)

	if _grant_xp > 0 and player != null:
		player.experience.grant(_grant_xp)
		await _wait_ticks(2)

	if _pointer != Vector2.INF:
		Input.warp_mouse(_pointer)
		# Two full frames: one for the warp to land, one for whatever polls it.
		await get_tree().process_frame
		await get_tree().process_frame

	if _attack and player != null:
		# The swing follows the cursor, and a headless cursor sits at (0, 0) —
		# which would aim this up and to the left. Pin it.
		player.aim_override = Vector2.RIGHT
		player.facing = Vector2.RIGHT
		Input.action_press(&"attack")
		await get_tree().process_frame
		Input.action_release(&"attack")
		await _wait_ticks(_attack_delay)

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("screenshot: save failed (%d)" % error)
	print("screenshot: %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	get_tree().quit(0 if error == OK else 1)


static func _find_player(root: Node) -> Player:
	if root is Player:
		return root as Player
	for child in root.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _wait_ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
