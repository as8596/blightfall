extends Node
## Walks up to a villager and has a conversation with them.
##
##     godot --headless --path . tests/dialogue_test.tscn
##
## Separate from `m1_smoke_test` because it loads Ambry, which is a scene change,
## and because a conversation is a state machine with its own failure modes.
##
## The ones worth naming, because each was either a real bug here or is one line
## of code away from being one:
##
## - **The opening press advancing the first line.** The same keypress that
##   starts a conversation is still held on the frame it opens, so without a
##   frame of deadband every conversation skips its own first line.
## - **A held key ripping through it.** Same problem, once per frame.
## - **Replies offered mid-speech**, which would have the player answering a
##   sentence the character has not finished.
## - **The tree never unpausing.** A conversation pauses the game; one that ends
##   without putting that back leaves a player who can see everything and move
##   nothing.

const AMBRY := "res://levels/ambry/ambry_level.tscn"

var _failures: int = 0
var _checks: int = 0
var _chose: Array = []


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
	print("\n=== Blightfall dialogue test ===\n")

	# Every conversation file has to parse and be shaped like a conversation.
	# Content that fails quietly ships.
	_check_library()

	get_tree().change_scene_to_file(AMBRY)
	await get_tree().tree_changed
	await _ticks(6)

	var ambry := get_tree().current_scene as Level
	_check("Ambry loaded", ambry != null)
	if ambry == null:
		return _finish()

	var cast := ambry.npcs()
	_check("the village has people standing in it", cast.size() >= 6, "%d" % cast.size())

	var carpenter: Npc = null
	for child in ambry.world.get_children():
		var person := child as Npc
		if person != null and person.dialogue_id == &"carpenter":
			carpenter = person
	_check("the carpenter is one of them", carpenter != null)
	if carpenter == null:
		return _finish()

	# Stand in front of them and press talk, driving real input rather than
	# calling start() — which also proves the interactor finds an Npc on the
	# Interactable layer, exactly as it finds a door.
	ambry.player.global_position = carpenter.global_position + Vector2(0, 72)
	await _ticks(20)
	var offered := ambry.player.interactor.target()
	_check("standing by them offers a prompt", offered != null and offered is Npc, "%s" % offered)
	_check("and the verb is Talk", offered != null and offered.prompt == "Talk",
		offered.prompt if offered != null else "-")

	Dialogue.chose.connect(func(id: StringName, node: String, index: int) -> void:
		_chose.append([id, node, index]))

	await _tap(&"interact")
	await _ticks(4)
	_check("pressing talk opens a conversation", Dialogue.is_open())
	if not Dialogue.is_open():
		return _finish()
	_check("the game is paused while you talk", get_tree().paused)
	_check("and the HUD is out of the way", not Hud.enabled)

	# The first line must still be typing. If the press that opened the box also
	# advanced it, this is already on line two and nobody would ever notice.
	_check("the first line starts typing rather than being skipped",
		Dialogue.line_index() == 0 and Dialogue.is_typing(),
		"line %d, typing %s" % [Dialogue.line_index(), Dialogue.is_typing()])
	_check("the speaker is named", Dialogue.speaker() == "The Carpenter", Dialogue.speaker())
	_check("no replies while a line is still arriving", not Dialogue.showing_replies())

	# Pressing mid-type completes the line instead of skipping it.
	var first := Dialogue.line_text()
	await _tap(&"interact")
	_check("pressing mid-line reveals the rest of it rather than skipping",
		Dialogue.line_text() == first and not Dialogue.is_typing() and Dialogue.line_index() == 0,
		"line %d, typing %s" % [Dialogue.line_index(), Dialogue.is_typing()])

	# ...and the next press moves on. Two lines in this node; the replies appear
	# on their own as soon as the second finishes arriving, rather than needing
	# another press — a box that made you confirm the end of a sentence before
	# it would show you the answers is a box with a redundant button in it.
	await _press(&"interact")
	_check("the next press moves to the second line", Dialogue.line_index() == 1,
		"line %d" % Dialogue.line_index())
	_check("the last line of a node offers replies once it has arrived",
		Dialogue.showing_replies())
	_check("and there are three of them", Dialogue.choice_count() == 3,
		"%d" % Dialogue.choice_count())
	_check("the first is selected", Dialogue.choice_index() == 0)

	# Moving the cursor, including the wrap.
	await _tap(&"move_down")
	_check("down moves the cursor", Dialogue.choice_index() == 1, "%d" % Dialogue.choice_index())
	await _tap(&"move_up")
	await _tap(&"move_up")
	_check("up wraps around the bottom", Dialogue.choice_index() == 2,
		"%d" % Dialogue.choice_index())
	await _tap(&"move_down")
	_check("and back to the top", Dialogue.choice_index() == 0, "%d" % Dialogue.choice_index())

	# Take the branch. "Timber for what?" leads to the deed.
	await _press(&"interact")
	_check("choosing a reply follows it", Dialogue.is_open() and Dialogue.node_name() == "deed",
		Dialogue.node_name())
	_check("and the choice is announced", _chose.size() == 1
		and String(_chose[0][1]) == "greeting" and int(_chose[0][2]) == 0, str(_chose))
	_check("the new node starts at its first line", Dialogue.line_index() == 0)

	# Run the branch out. The deed node is three lines and then two replies;
	# take the second, which reaches a node with no replies at all.
	await _press(&"interact")
	await _press(&"interact")
	_check("the branch ends in replies too", Dialogue.showing_replies()
		and Dialogue.choice_count() == 2, "%d replies" % Dialogue.choice_count())
	await _tap(&"move_down")
	await _press(&"interact")
	_check("the second reply leads somewhere else", Dialogue.node_name() == "materials",
		Dialogue.node_name())

	await _press(&"interact")
	await _press(&"interact")
	_check("a node with no replies ends after its last line", not Dialogue.is_open(),
		"still open at node '%s' line %d" % [Dialogue.node_name(), Dialogue.line_index()])
	_check("the game is running again afterwards", not get_tree().paused)
	_check("and the HUD is back", Hud.enabled)

	# Nobody should be able to open a conversation with somebody who has nothing
	# written for them.
	_check("an npc with no file does not open an empty box",
		not Dialogue.start(&"nobody_at_all"))
	_check("and that did not leave the game paused", not get_tree().paused)

	await _test_clicking()
	_finish()


## The mouse does what the key does.
##
## In its own conversation rather than woven into the run above, because a test
## that advances the dialogue as a side effect of checking something else leaves
## every assertion after it standing on a different node — which is exactly how
## this failed the first time.
func _test_clicking() -> void:
	_check("a fresh conversation opens for the click test", Dialogue.start(&"carpenter"))
	await _ticks(4)

	var typing_line := Dialogue.line_text()
	_check("it is mid-line to begin with", Dialogue.is_typing())
	_click()
	await _ticks(2)
	_check("clicking the box reveals the rest of a typing line",
		Dialogue.line_text() == typing_line and not Dialogue.is_typing(),
		"typing %s" % Dialogue.is_typing())

	var before := Dialogue.line_index()
	_click()
	await _ticks(2)
	_check("and clicking again turns the page",
		Dialogue.line_index() > before, "line %d" % Dialogue.line_index())

	# Run it to the replies with the mouse alone, then confirm a click on the
	# box *behind* them is not an answer — choosing the highlighted reply for
	# the player is a conversation they did not have.
	for _i in range(8):
		if Dialogue.showing_replies():
			break
		_click()
		await _ticks(2)
	_check("clicking alone reaches the replies", Dialogue.showing_replies())
	var node_before := Dialogue.node_name()
	_click()
	await _ticks(2)
	_check("clicking the box behind the replies chooses nothing",
		Dialogue.node_name() == node_before and Dialogue.showing_replies(),
		"%s -> %s" % [node_before, Dialogue.node_name()])

	Dialogue.close()
	await _ticks(2)
	_check("the click test left the game unpaused", not get_tree().paused)


## Every file in `resources/dialogue/` parses, and every reply points at a node
## that exists. A `goto` typo is a conversation that ends abruptly for one
## player on one branch, which is not a thing anyone finds by playing.
func _check_library() -> void:
	var dir := DirAccess.open(Dialogue.DIR)
	_check("the dialogue folder exists", dir != null)
	if dir == null:
		return
	var broken: Array[String] = []
	var count := 0
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		count += 1
		var id := StringName(file.trim_suffix(".json"))
		var data := Dialogue.load_dialogue(id)
		if data.is_empty():
			broken.append("%s did not parse" % id)
			continue
		var nodes: Dictionary = data.get("nodes", {})
		if not nodes.has(String(data.get("start", "greeting"))):
			broken.append("%s starts at a node that does not exist" % id)
		for name in nodes:
			var node: Dictionary = nodes[name]
			if node.get("lines", []).is_empty():
				broken.append("%s/%s has no lines" % [id, name])
			for choice in node.get("choices", []):
				var goto := String(choice.get("goto", ""))
				if goto != "" and not nodes.has(goto):
					broken.append("%s/%s -> '%s' goes nowhere" % [id, name, goto])
	_check("every conversation parses and every reply goes somewhere", broken.is_empty(),
		", ".join(broken))
	_check("the whole cast has something to say", count >= 10, "%d files" % count)


# ------------------------------------------------------------------ harness

## Hold, release, settle. Nothing waits for the typewriter — checks that care
## about being mid-line need the press to land mid-line.
## A left click on the dialogue box. Delivered straight to the handler rather
## than through the viewport: `Input.parse_input_event` would have to land on
## the panel's real screen rect, which depends on the window size and on the UI
## scale, and a test that silently stops clicking the thing it means to click is
## worse than no test.
func _click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Dialogue._on_box_input(event)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _ticks(3)
	Input.action_release(action)
	await _ticks(3)


## The same, then waits out the reveal — for checks about *which line* rather
## than about the reveal itself.
func _press(action: StringName) -> void:
	await _tap(action)
	for i in 600:
		if not Dialogue.is_open() or not Dialogue.is_typing():
			break
		await get_tree().process_frame
	await _ticks(2)


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
