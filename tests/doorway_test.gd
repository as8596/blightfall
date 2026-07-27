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

## Darkest the screen got during the last transition. The fade is the feature;
## asserting only that it *ends* clear would pass just as happily if it never
## started.
var _darkest: float = 0.0


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

	# Stand at the door and press. Driving real input rather than calling
	# travel() directly is the point: it also proves the interactor's mask lines
	# up with the Interactable layer, and that standing next to a door is enough
	# to be offered it.
	ambry.player.global_position = door_out
	await _ticks(20)
	var offered := ambry.player.interactor.target()
	_check("standing at the door offers a prompt",
		offered != null and offered is Doorway, "%s" % offered)
	_check("and the prompt is a verb", offered != null and offered.prompt == "Enter",
		offered.prompt if offered != null else "-")

	# Walking past must not open it. This is the whole reason doors are pressed
	# rather than touched now: a transition that fades the screen firing by
	# accident is much worse than one that only moves you.
	var walked := await _walk_until_scene_changes(&"move_up", HOME, 40)
	_check("walking into the door does NOT open it", not walked,
		get_tree().current_scene.scene_file_path)
	ambry.player.global_position = door_out
	await _ticks(10)

	var arrived := await _press_until_scene_changes(HOME)
	_check("pressing interact opens your home", arrived, get_tree().current_scene.scene_file_path)
	_check("and the screen faded to black on the way", _darkest >= 0.99,
		"darkest %.2f" % _darkest)
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

	_check("the screen is clear again once you arrive", not ScreenFade.is_covered(),
		"alpha %.2f" % ScreenFade.alpha())

	# And back out. Walk down onto the door tile first, since the interior spawn
	# is deliberately two tiles clear of it.
	Input.action_press(&"move_down")
	await _ticks(30)
	Input.action_release(&"move_down")
	await _ticks(4)
	var left := await _press_until_scene_changes(AMBRY)
	_check("pressing interact leaves again", left, get_tree().current_scene.scene_file_path)
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


func _walk_until_scene_changes(action: StringName, expected: String, ticks: int = 240) -> bool:
	Input.action_press(action)
	for i in ticks:
		await get_tree().physics_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected:
			Input.action_release(action)
			await _ticks(4)
			return true
	Input.action_release(action)
	await _ticks(2)
	return false


## Tap interact, then wait out the fade. The transition is deliberately not
## instant, so a test that gives up after two frames would report a working door
## as broken.
func _press_until_scene_changes(expected: String) -> bool:
	_darkest = 0.0
	Input.action_press(&"interact")
	await _ticks(2)
	Input.action_release(&"interact")
	for i in 240:
		await get_tree().physics_frame
		_darkest = maxf(_darkest, ScreenFade.alpha())
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected:
			# Let the fade finish before anything is measured.
			for j in 60:
				await get_tree().process_frame
				if not ScreenFade.is_covered() and ScreenFade.alpha() <= 0.01:
					break
			return true
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
