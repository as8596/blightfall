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
		elif arg.begins_with("--near"):
			_pull_enemies_close = true
		elif arg.begins_with("--attack="):
			_attack = true
			_attack_delay = arg.trim_prefix("--attack=").to_int()
		elif arg.begins_with("--attack"):
			_attack = true

	for i in settle_frames:
		await get_tree().process_frame

	var player := _room.get_node_or_null("Player") as Player
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

	if _attack and player != null:
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


func _wait_ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
