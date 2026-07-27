extends Node
## Walks the player through a door and back out again, for real.
##
##     godot --headless --path . tests/doorway_test.tscn
##
## Separate from `m1_smoke_test` because it is the one test that changes scenes.
## `change_scene_to_file` frees whatever `current_scene` is, so a test living in
## the current scene would delete itself halfway through the thing it is
## testing; this reparents its runner to the tree root first and outlives every
## scene it opens.
##
## What it is actually guarding is the ordering inside `Doorway.travel`. The
## save payload it carries across the threshold includes the player's position,
## so applying it *after* the level has placed the player would silently teleport
## them back to the building they just walked out of — a bug that looks like a
## doorway not working and is in fact a doorway working perfectly, twice.

const AMBRY := "res://levels/ambry/ambry_level.tscn"
const HOME := "res://levels/ambry/interiors/home_level.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	Engine.max_fps = 250
	_boot.call_deferred()


func _boot() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	await get_tree().process_frame
	await _run()


func _run() -> void:
	print("\n=== Blightfall doorway test ===\n")

	get_tree().change_scene_to_file(AMBRY)
	await get_tree().tree_changed
	await _ticks(6)

	var ambry := get_tree().current_scene as Level
	_check("Ambry loaded", ambry != null)
	if ambry == null:
		return _finish()

	# Something to lose. A satchel that empties itself on the way through a door
	# is the failure this whole ordering dance exists to prevent.
	ambry.player.inventory.add(&"timber", 5)
	var door_out := ambry.find_marker("Door_home")
	_check("Ambry has the spot outside your door", door_out != Vector2.INF)

	# Walk in. Driving the input rather than calling travel() directly is the
	# point: it also proves the Area2D's layers and mask line up with the
	# player's body.
	ambry.player.global_position = door_out + Vector2(0, 32.0)
	await _ticks(20)
	var arrived := await _walk_until_scene_changes(&"move_up", HOME)
	_check("walking into the door opens your home", arrived, get_tree().current_scene.scene_file_path)
	if not arrived:
		return _finish()

	var home := get_tree().current_scene as Level
	await _ticks(6)
	_check("the haul came with you", home.player.inventory.total() == 5,
		"%d units" % home.player.inventory.total())
	var inside := home.find_marker("PlayerSpawn")
	_check("and you are standing inside, not back where you were",
		home.player.global_position.distance_to(inside) < 8.0,
		"%s vs %s" % [home.player.global_position, inside])

	var chest := home.poi("home_chest")
	_check("the chest is in the room", not chest.is_empty())

	# And back out.
	var left := await _walk_until_scene_changes(&"move_down", AMBRY)
	_check("walking into the door leaves again", left, get_tree().current_scene.scene_file_path)
	if not left:
		return _finish()

	var back := get_tree().current_scene as Level
	await _ticks(6)
	_check("you come out of the door you went in",
		back.player.global_position.distance_to(back.find_marker("Door_home")) < 8.0,
		"%s" % back.player.global_position)
	_check("still carrying the haul", back.player.inventory.total() == 5,
		"%d units" % back.player.inventory.total())

	_finish()


func _walk_until_scene_changes(action: StringName, expected: String) -> bool:
	Input.action_press(action)
	for i in 240:
		await get_tree().physics_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected:
			Input.action_release(action)
			await _ticks(4)
			return true
	Input.action_release(action)
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _finish() -> void:
	print("\n%d checks, %d failed\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
