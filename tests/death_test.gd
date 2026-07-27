extends Node
## Kill the player and check they come back.
##
##     godot --headless --path . tests/death_test.tscn
##
## In `tests/` alongside `doorway_test` and for the same reason: it changes
## scenes, and `change_scene_to_file` frees whatever `current_scene` is — so a
## test living inside the current scene would delete itself halfway through the
## thing it is testing.
##
## Two cases, and the second is the one that matters. Dying with no save has to
## put you back on your feet rather than leave you lying in an empty street,
## because until a bed exists in the world that is *every* death. And dying with
## a save must not rewind the world: GDD §15 A4 says a lost haul is displaced,
## not destroyed, so it has to survive the reload and still be lying where you
## fell. A retry that quietly deleted the cache would delete the whole stake.

const AMBRY := "res://levels/ambry/ambry_level.tscn"

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
	print("\n=== Blightfall death test ===\n")
	# Nothing here needs a second of lying about before the fade.
	Transition.death_pause = 0.05
	SaveGame.delete_save(SaveGame.current_slot)

	# ---- no save at all: the scene restarts.
	await _load(AMBRY)
	var level := get_tree().current_scene as Level
	_check("Ambry loaded", level != null)
	if level == null:
		return _finish()

	level.player.inventory.add(&"timber", 4)
	var died_at := level.player.global_position
	level.player.health.take_damage(999)
	_check("dying enters the Dead state", level.player.state_machine.is_in(&"Dead"))

	var back := await _wait_for_reload(AMBRY)
	_check("dying with no save restarts the level", back != null)
	if back == null:
		return _finish()
	_check("and you are alive again",
		back.player.health.current == back.player.health.max_health,
		"%d/%d hp" % [back.player.health.current, back.player.health.max_health])
	_check("and not still in the Dead state", not back.player.state_machine.is_in(&"Dead"))
	_check("the screen is clear", not ScreenFade.is_covered(),
		"alpha %.2f" % ScreenFade.alpha())

	# The haul was dropped where you fell and has to still be there.
	var caches := get_tree().get_nodes_in_group(HaulCache.GROUP)
	_check("the haul you dropped survived the reload", caches.size() == 1,
		"%d caches" % caches.size())
	if caches.size() == 1:
		var cache: HaulCache = caches[0]
		_check("with everything still in it", cache.total() == 4, "%d units" % cache.total())
		_check("and lying where you fell",
			cache.global_position.distance_to(died_at) < 8.0,
			"%s vs %s" % [cache.global_position, died_at])
		_check("your own satchel is empty", back.player.inventory.total() == 0,
			"%d units" % back.player.inventory.total())
		cache.queue_free()
		await _ticks(2)

	# ---- with a save: the run resumes from it.
	back.player.global_position = back.find_marker("Door_home")
	back.player.health.set_max_health(8, true)
	await _ticks(4)
	var rest_point := back.player.global_position
	_check("saved", SaveGame.save_slot(SaveGame.current_slot))

	# Walk somewhere else, then die there.
	back.player.global_position = rest_point + Vector2(0, 192.0)
	back.player.health.take_damage(999)
	var resumed := await _wait_for_reload(AMBRY)
	_check("dying with a save reloads it", resumed != null)
	if resumed == null:
		return _finish()
	_check("you resume at the save, not where you died",
		resumed.player.global_position.distance_to(rest_point) < 8.0,
		"%s vs %s" % [resumed.player.global_position, rest_point])
	# Restoring max_health before current is the ordering trap the save system
	# has a test for; this checks it survives the retry path too.
	_check("with the heart containers you had earned",
		resumed.player.health.max_health == 8, "%d" % resumed.player.health.max_health)

	SaveGame.delete_save(SaveGame.current_slot)
	_finish()


## The retry is deliberately not instant — a pause, then a fade each way. Give
## it real time rather than assuming a frame count.
func _wait_for_reload(expected: String) -> Level:
	for i in 400:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != expected:
			continue
		if Transition.is_busy() or ScreenFade.alpha() > 0.01:
			continue
		var level := scene as Level
		if level != null and level.player != null and is_instance_valid(level.player):
			await _ticks(2)
			return level
	return null


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await get_tree().tree_changed
	await _ticks(6)


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
