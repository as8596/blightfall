extends Node
## Walks out of Ambry, around Orchardfall, and back again — for real.
##
##     godot --headless --path . tests/gateway_test.tscn
##
## Separate from `m1_smoke_test` for the same reason `doorway_test` is: it
## changes scenes, and `change_scene_to_file` frees whatever `current_scene` is.
## The runner reparents itself to the tree root and outlives every area it
## opens.
##
## What it actually guards is the opposite rule to the doorway test. A door must
## **not** open when you walk into it; an edge must. Both of those are one line
## of code away from being the other, and both failures are silent — a door that
## opens on contact only bites when somebody walks past one, and an edge that
## needs a keypress just looks like the map ending.
##
## The other thing here is the arrival bounce. Every gateway sits on the
## outermost row of its opening and every arrival marker sits two rows inside
## it. If that ever stops being true the player fades into an area, lands on the
## trigger they arrived through, and ricochets between two maps forever with no
## input accepted. `Gateway._armed` is the guard; this is the test that it
## works, and it is checked by *arriving and then standing still*.

const MENU := "res://ui/main_menu.tscn"
const AMBRY := "res://levels/ambry/ambry_level.tscn"
const VALLEY := "res://levels/orchardfall/valley_road_level.tscn"
const ORCHARD := "res://levels/orchardfall/orchard_rows_level.tscn"
const MILLPOND := "res://levels/orchardfall/millpond_level.tscn"

## Every area, and where each of its edges is supposed to lead. Written out
## rather than read from the scenes, so this fails if the generator's graph
## changes without anyone meaning it to.
const GRAPH := {
	"valley_road": {"north": "ambry", "south": "orchard_rows", "east": "millpond"},
	"orchard_rows": {"north": "valley_road", "east": "terraces", "south": "cider_yard"},
	"millpond": {"west": "valley_road", "south": "terraces"},
	"terraces": {"north": "millpond", "west": "orchard_rows", "south": "deep_rows"},
	"cider_yard": {"north": "orchard_rows", "east": "deep_rows"},
	"deep_rows": {"north": "terraces", "west": "cider_yard"},
}

var _failures: int = 0
var _checks: int = 0
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
	print("\n=== Blightfall gateway test ===\n")

	# From the title screen, the way a player gets there. Booting straight into
	# the level would skip the one path everybody takes.
	_check("the game boots to the title screen",
		ProjectSettings.get_setting("application/run/main_scene", "") == MENU,
		String(ProjectSettings.get_setting("application/run/main_scene", "")))

	get_tree().change_scene_to_file(MENU)
	await get_tree().tree_changed
	await _ticks(4)

	var new_game := _find_button(get_tree().current_scene, "New Game")
	_check("the title screen offers a new game", new_game != null)
	if new_game == null:
		return _finish()
	new_game.emit_signal("pressed")
	var started := await _wait_for_scene(AMBRY)
	_check("and it starts one, in Ambry", started, get_tree().current_scene.scene_file_path)
	if not started:
		return _finish()
	await _ticks(6)

	# The title screen is gone now, and anything it connected to an autoload has
	# to have gone with it. A lambda does not: Godot only auto-disconnects a
	# callable bound to the freed object, so `UiScale.changed.connect(func ...)`
	# on the menu left a callback holding a freed Label, and every UI-scale press
	# for the rest of the session ran it. That is a crash you only meet after
	# starting a game and then opening the pause menu, which is late.
	var dangling: Array[String] = []
	for entry in UiScale.changed.get_connections():
		var callable: Callable = entry["callable"]
		if not is_instance_valid(callable.get_object()):
			dangling.append(str(callable))
	_check("nothing dead is still listening for a UI scale change",
		dangling.is_empty(), ", ".join(dangling))
	# ...and pressing it is safe, which is the thing the player actually does.
	var before := UiScale.factor
	UiScale.factor += UiScale.STEP
	UiScale.factor = before
	_check("changing the UI scale after leaving the menu is safe",
		is_equal_approx(UiScale.factor, before), "%.1f" % UiScale.factor)

	var ambry := get_tree().current_scene as Level
	_check("Ambry loaded", ambry != null)
	if ambry == null:
		return _finish()

	# Something to lose on the way out and on the way back.
	ambry.player.inventory.add(&"timber", 4)

	var out := ambry.gateways()
	_check("Ambry has exactly one way out to the valley", out.size() == 1, str(out.size()))
	if out.is_empty():
		return _finish()
	_check("and it leads to the valley road", String(out[0]["target"]) == VALLEY,
		String(out[0]["target"]))

	# Walk south into the gate. No keypress — that is the whole feature.
	ambry.player.global_position = ambry.find_marker("PlayerSpawn")
	await _ticks(6)
	var left := await _walk_until_scene_changes(&"move_down", VALLEY)
	_check("walking into the gate leaves town, with no keypress", left,
		get_tree().current_scene.scene_file_path)
	_check("and the screen faded to black on the way", _darkest >= 0.99,
		"darkest %.2f" % _darkest)
	if not left:
		return _finish()

	var valley := get_tree().current_scene as Level
	await _ticks(6)
	_check("the haul came with you", valley.player.inventory.total() == 4,
		"%d units" % valley.player.inventory.total())

	var arrival := valley.find_marker("Edge_north")
	_check("you arrive at the valley's north edge", arrival != Vector2.INF
		and valley.player.global_position.distance_to(arrival) < 8.0,
		"%s vs %s" % [valley.player.global_position, arrival])
	_check("the screen is clear again once you arrive", not ScreenFade.is_covered(),
		"alpha %.2f" % ScreenFade.alpha())

	# The bounce. Stand still on the arrival tile for a full second: the gateway
	# you came through is two rows away and must not reach you, and even if it
	# did, arriving inside one must not fire it.
	await _ticks(60)
	_check("standing still after arriving does not send you back",
		get_tree().current_scene.scene_file_path == VALLEY,
		get_tree().current_scene.scene_file_path)

	_check("the valley road has three ways out", valley.gateways().size() == 3,
		str(valley.gateways().size()))

	# ...and out the other side, to prove the zone is a zone and not a cul-de-sac.
	var onward := await _walk_until_scene_changes(&"move_down", ORCHARD, 900)
	_check("walking south again reaches the orchard rows", onward,
		get_tree().current_scene.scene_file_path)
	if onward:
		var orchard := get_tree().current_scene as Level
		await _ticks(6)
		_check("still carrying the haul two areas out",
			orchard.player.inventory.total() == 4,
			"%d units" % orchard.player.inventory.total())
		# Straight back the way we came. Two-way is asserted in the generator
		# against the data; this asserts it against the game.
		var home := await _walk_until_scene_changes(&"move_up", VALLEY, 900)
		_check("and walking back north returns to the valley road", home,
			get_tree().current_scene.scene_file_path)

	_check_graph()
	_finish()


## Every area's edges lead where the map says they lead, and every one of them
## has a partner coming back. Loaded rather than walked — walking all fifteen
## would take a minute of real time and prove the same thing.
func _check_graph() -> void:
	print("")
	var wrong: Array[String] = []
	var missing: Array[String] = []
	for id in GRAPH:
		var scene: PackedScene = load("res://levels/orchardfall/%s.tscn" % id)
		if scene == null:
			missing.append("%s has no map" % id)
			continue
		var map: Node = scene.instantiate()
		var edges := map.get_node_or_null(^"Gateways")
		var seen := {}
		for child in (edges.get_children() if edges != null else []):
			var facing := String(child.get_meta("facing", ""))
			var target := String(child.get_meta("target_scene", ""))
			var want: String = String(GRAPH[id].get(facing, ""))
			seen[facing] = true
			if want == "":
				wrong.append("%s has an unexpected %s exit" % [id, facing])
			elif want == "ambry":
				if target != AMBRY:
					wrong.append("%s %s should lead to Ambry, leads to %s" % [id, facing, target])
			elif not target.ends_with("/%s_level.tscn" % want):
				wrong.append("%s %s should lead to %s, leads to %s" % [id, facing, want, target])
			# ...and the arrival marker the other side aims at has to exist.
			if map.get_node_or_null(NodePath("Edge_" + facing)) == null:
				missing.append("%s has no Edge_%s to arrive on" % [id, facing])
		for facing in GRAPH[id]:
			if not seen.has(facing):
				missing.append("%s is missing its %s exit" % [id, facing])
		map.free()

	_check("every exit leads where the zone map says", wrong.is_empty(), ", ".join(wrong))
	_check("every exit has an arrival marker to land on", missing.is_empty(),
		", ".join(missing))

	# The millpond is the one with a bridge, and a bridge is only worth the
	# tiles if it goes somewhere. This is the assertion that caught it going
	# nowhere the first time.
	var pond: Node = (load("res://levels/orchardfall/millpond.tscn") as PackedScene).instantiate()
	var ruin: Node = pond.get_node_or_null(^"PointsOfInterest/Poi_mill_ruin")
	_check("the millpond's bridge lands on the mill", ruin != null)
	pond.free()


# ------------------------------------------------------------------ harness

static func _find_button(root: Node, text: String) -> Button:
	var button := root as Button
	if button != null and button.text == text:
		return button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _wait_for_scene(expected: String, ticks: int = 300) -> bool:
	for i in ticks:
		await get_tree().physics_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected:
			for j in 90:
				await get_tree().process_frame
				if not ScreenFade.is_covered() and ScreenFade.alpha() <= 0.01:
					break
			return true
	return false


func _walk_until_scene_changes(action: StringName, expected: String, ticks: int = 300) -> bool:
	_darkest = 0.0
	Input.action_press(action)
	for i in ticks:
		await get_tree().physics_frame
		_darkest = maxf(_darkest, ScreenFade.alpha())
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected:
			Input.action_release(action)
			# Let the fade finish before anything is measured.
			for j in 90:
				await get_tree().process_frame
				if not ScreenFade.is_covered() and ScreenFade.alpha() <= 0.01:
					break
			await _ticks(4)
			return true
	Input.action_release(action)
	await _ticks(2)
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
