extends Node
## Being asked to do something, doing it, and being paid for it.
##
##     godot --headless --path . tests/quest_test.tscn
##
## The failure modes worth naming, because a quest system's bugs are all of the
## same shape — state that drifts from the world it claims to describe:
##
## - **A quest that stays ready after you sell the goods.** Progress is derived
##   from what you are holding, so it has to fall back as well as forward, or
##   the turn-in takes nothing and pays out anyway.
## - **A turn-in that eats the goods and drops the reward** because the pack was
##   full. Checked before anything is consumed.
## - **Counters that survive a rename.** Enemies and quests are keyed by id, and
##   a save naming a quest this build has never heard of is dropped rather than
##   carried.
## - **A reply offered in the wrong state** — "I've got your timber" while you
##   have not been asked for any.

const AMBRY := "res://levels/ambry/ambry_level.tscn"

var _failures: int = 0
var _checks: int = 0


## A stand-in for something that died. `Events.enemy_died` carries a Node and
## the listener reads `.data` off it; building a real enemy would drag in the
## whole combat scene for a signal that carries one resource.
class FakeEnemy extends Node:
	var data: EnemyData


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
	print("\n=== Blightfall quest test ===\n")
	_check_library()
	await _check_the_loop()
	_check_synthetic()
	_check_saving()
	await _check_the_seam()
	_finish()


# ----------------------------------------------------------------- library

func _check_library() -> void:
	print("Definitions")
	var all := Quests.all()
	_check("there is a quest to do", all.size() >= 1, "%d" % all.size())

	var broken: Array[String] = []
	for entry in all:
		var quest: QuestData = entry
		if not quest.is_valid():
			broken.append("%s is not usable" % quest.id)
		if quest.giver != &"" and Dialogue.load_dialogue(quest.giver).is_empty():
			broken.append("%s is given by '%s', who has no conversation"
				% [quest.id, quest.giver])
		for step in quest.steps:
			match step.kind:
				QuestStep.Kind.GATHER:
					if not Materials.known(step.target) and not Items.has(step.target):
						broken.append("%s wants '%s', which is nothing" % [quest.id, step.target])
				QuestStep.Kind.TALK:
					if step.node == "":
						broken.append("%s has a TALK step naming no node" % quest.id)
	_check("every quest is coherent", broken.is_empty(), ", ".join(broken))

	# The generated journal line has to say something for every kind, or a step
	# renders as a blank bullet and the player cannot tell what is being asked.
	var wordless: Array[String] = []
	for entry in all:
		for step in (entry as QuestData).steps:
			if Quests.step_text(step).strip_edges() == "":
				wordless.append(String((entry as QuestData).id))
	_check("every step says what it wants", wordless.is_empty(), ", ".join(wordless))


# -------------------------------------------------------------- the loop

func _check_the_loop() -> void:
	print("\nTaking one on, and finishing it")
	get_tree().change_scene_to_file(AMBRY)
	await get_tree().tree_changed
	await _ticks(6)

	var level := get_tree().current_scene as Level
	_check("Ambry loaded", level != null)
	if level == null:
		return
	var sack: InventoryComponent = level.player.inventory
	var pack: ItemsComponent = level.player.items
	Quests.reset()
	sack.clear()
	Purse.set_amount(0)

	var quest := Quests.get_quest(&"supply_run")
	_check("the supply run exists", quest != null)
	if quest == null:
		return

	_check("it starts unknown", Quests.state_of(&"supply_run") == Quests.State.UNKNOWN)
	_check("and is on offer", Quests.can_offer(&"supply_run"))
	_check("it is not in the journal yet", Quests.journal().is_empty())

	_check("taking it works", Quests.offer(&"supply_run"))
	_check("it is now active", Quests.state_of(&"supply_run") == Quests.State.ACTIVE)
	_check("it cannot be taken twice", not Quests.offer(&"supply_run"))
	_check("and it is in the journal", Quests.journal().size() == 1)

	# Nothing carried, so nothing done.
	var at := Quests.step_progress(quest, 0, level.player)
	_check("no progress on an empty satchel", int(at[0]) == 0, "%d/%d" % [at[0], at[1]])
	_check("turning in early is refused",
		Quests.turn_in(&"supply_run", level.player) != "")

	# Part of the way.
	@warning_ignore("return_value_discarded")
	sack.add(&"timber", 8)
	await _ticks(2)
	_check("timber counts", Quests.step_done(quest, 0, level.player))
	_check("but the stone is still owed", not Quests.step_done(quest, 1, level.player))
	_check("so it is not ready", Quests.state_of(&"supply_run") == Quests.State.ACTIVE)

	@warning_ignore("return_value_discarded")
	sack.add(&"stone", 4)
	await _ticks(2)
	_check("with both, it is ready", Quests.state_of(&"supply_run") == Quests.State.READY)

	# **Both directions.** Selling the goods has to un-ready it, or the turn-in
	# takes nothing and pays out anyway.
	@warning_ignore("return_value_discarded")
	sack.remove(&"stone", 2)
	await _ticks(2)
	_check("selling the goods takes it back to active",
		Quests.state_of(&"supply_run") == Quests.State.ACTIVE)
	@warning_ignore("return_value_discarded")
	sack.add(&"stone", 2)
	await _ticks(2)
	_check("and replacing them makes it ready again",
		Quests.state_of(&"supply_run") == Quests.State.READY)

	# The full-pack refusal, before anything is taken.
	var filler := Items.get_item(&"worn_sword")
	for slot in pack.items.size():
		if pack.item_at(slot) == null:
			@warning_ignore("return_value_discarded")
			pack.add(filler, 1)
	var timber_before := sack.count_of(&"timber")
	var refusal := Quests.turn_in(&"supply_run", level.player)
	_check("a full pack refuses the turn-in", refusal != "", refusal)
	_check("and the goods are untouched", sack.count_of(&"timber") == timber_before,
		"%d" % sack.count_of(&"timber"))
	_check("and it is still ready", Quests.state_of(&"supply_run") == Quests.State.READY)

	# Room made, and paid.
	for slot in pack.items.size():
		if pack.item_at(slot) != null:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, pack.count_at(slot))
	var xp_before: int = level.player.experience.total()
	_check("turning in succeeds", Quests.turn_in(&"supply_run", level.player) == "")
	_check("it is done", Quests.state_of(&"supply_run") == Quests.State.DONE)
	_check("the goods are taken", sack.count_of(&"timber") == 0 and sack.count_of(&"stone") == 0,
		"%d timber, %d stone" % [sack.count_of(&"timber"), sack.count_of(&"stone")])
	_check("the gold is paid", Purse.amount() == quest.gold, "%d" % Purse.amount())
	_check("the experience is paid", level.player.experience.total() > xp_before)
	_check("and the salve arrives", _held(pack, &"salve") == 1, "%d" % _held(pack, &"salve"))
	_check("it counted as one completion", Quests.completions(&"supply_run") == 1)

	# Repeatable, so it comes back round.
	_check("a repeatable quest is on offer again", Quests.can_offer(&"supply_run"))
	_check("and can be taken again", Quests.offer(&"supply_run"))
	_check("which makes it active", Quests.state_of(&"supply_run") == Quests.State.ACTIVE)
	_check("and it is not ready, since the goods were handed over",
		Quests.state_of(&"supply_run") != Quests.State.READY)


# ------------------------------------------------- kinds without a def yet

## SLAY, TALK and BUILD, driven through a quest built here rather than shipped.
## The three exist because the loop will want them; asserting them now is what
## stops the first real one that uses them from being the thing that finds the
## bug.
func _check_synthetic() -> void:
	print("\nThe other three kinds")
	var quest := QuestData.new()
	quest.id = &"_test_synthetic"
	quest.title = "Synthetic"
	var slay := QuestStep.new()
	slay.kind = QuestStep.Kind.SLAY
	slay.target = &"forest_wolf"
	slay.count = 2
	var talk := QuestStep.new()
	talk.kind = QuestStep.Kind.TALK
	talk.target = &"smith"
	talk.node = "greeting"
	var build := QuestStep.new()
	build.kind = QuestStep.Kind.BUILD
	build.target = &"home"
	quest.steps = [slay, talk, build]
	Quests._by_id[quest.id] = quest

	_check("it registers", Quests.has(&"_test_synthetic"))
	_check("and can be taken", Quests.offer(&"_test_synthetic"))

	_check("no kills yet", not Quests.step_done(quest, 0))
	for i in 3:
		var corpse := FakeEnemy.new()
		corpse.data = load("res://resources/enemy_data/forest_wolf.tres")
		Events.enemy_died.emit(corpse)
		corpse.free()
	_check("kills are counted", Quests.step_done(quest, 0))
	var at := Quests.step_progress(quest, 0)
	_check("and clamped to what was asked", int(at[0]) == 2, "%d/%d" % [at[0], at[1]])

	# A wolf is not a villager. Counting every death against every SLAY step is
	# the obvious bug here and it would look like the quest working.
	var other := QuestData.new()
	other.id = &"_test_other"
	other.title = "Other"
	var wrong := QuestStep.new()
	wrong.kind = QuestStep.Kind.SLAY
	wrong.target = &"blighted_villager"
	wrong.count = 1
	other.steps = [wrong]
	Quests._by_id[other.id] = other
	@warning_ignore("return_value_discarded")
	Quests.offer(&"_test_other")
	_check("a kill only counts for the enemy it was", not Quests.step_done(other, 0))

	_check("nobody has been spoken to", not Quests.step_done(quest, 1))
	_check("the house is not built", not Quests.step_done(quest, 2))
	_check("so the whole thing is not ready",
		Quests.state_of(&"_test_synthetic") == Quests.State.ACTIVE)

	# TALK and BUILD read the systems that already know, rather than a copy.
	@warning_ignore("return_value_discarded")
	Dialogue.start(&"smith")
	Dialogue.close()
	_check("speaking to them satisfies the step", Quests.step_done(quest, 1))

	Quests._by_id.erase(&"_test_synthetic")
	Quests._by_id.erase(&"_test_other")


# ------------------------------------------------------------------ saving

func _check_saving() -> void:
	print("\nSaving")
	Quests.reset()
	@warning_ignore("return_value_discarded")
	Quests.offer(&"supply_run")
	var saved := Quests.save_data()
	Quests.reset()
	_check("a reset forgets it", Quests.state_of(&"supply_run") == Quests.State.UNKNOWN)
	Quests.load_data(saved)
	_check("a load remembers it", Quests.is_active(&"supply_run"))
	_check("quests are registered as saveable", Quests.is_in_group(SaveGame.GROUP))

	# A save naming a quest this build has never heard of is dropped, not kept:
	# the same rule `Skills.load_data` follows for a deleted skill.
	Quests.load_data({"states": {"a_quest_that_was_cut": 1}, "progress": {}, "completions": {}})
	_check("an unknown quest in a save is ignored", Quests.journal().is_empty())


# ---------------------------------------------------------------- the seam

## The conditions and the actions, which is where the dialogue meets the state
## machine. Both halves work in isolation and would keep working with the wire
## between them cut.
func _check_the_seam() -> void:
	print("\nTalking about it")
	Quests.reset()
	Dialogue.forget_conversations()

	_check("an unknown quest reads as unknown", Quests.matches("supply_run:unknown"))
	_check("and as offerable", Quests.matches("supply_run:offerable"))
	_check("but not as active", not Quests.matches("supply_run:active"))
	_check("several states can be listed",
		Quests.matches("supply_run:active|unknown"))
	_check("a missing quest matches nothing", not Quests.matches("no_such_quest:active"))
	_check("an empty condition always passes", Quests.matches(""))

	# Every `if_quest` in every conversation names a quest that exists and a
	# state that exists — a typo here is a reply that can never appear, and
	# nothing about that looks like a fault from inside the game.
	var dir := DirAccess.open(Dialogue.DIR)
	var broken: Array[String] = []
	var gated := 0
	if dir != null:
		for file in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var id := StringName(file.trim_suffix(".json"))
			var data := Dialogue.load_dialogue(id)
			for node_name in data.get("nodes", {}):
				for choice in (data["nodes"][node_name] as Dictionary).get("choices", []):
					for key in ["if_quest", "unless_quest"]:
						var spec := String((choice as Dictionary).get(key, ""))
						if spec == "":
							continue
						gated += 1
						var parts := spec.split(":")
						if not Quests.has(StringName(parts[0])):
							broken.append("%s/%s -> '%s'" % [id, node_name, spec])
							continue
						for want in (parts[1] if parts.size() > 1 else "active").split("|", false):
							if want != "offerable" and not Quests.STATE_NAMES.has(want):
								broken.append("%s/%s '%s' is not a state" % [id, node_name, want])
					# Same for the actions.
					var action := String((choice as Dictionary).get("action", ""))
					if action in ["quest", "turn_in"]:
						var named := StringName(String((choice as Dictionary).get("quest", "")))
						if not Quests.has(named):
							broken.append("%s/%s %s -> '%s'" % [id, node_name, action, named])
	_check("every quest reply names something real", broken.is_empty(), ", ".join(broken))
	_check("and the conversations actually use them", gated >= 3, "%d gated replies" % gated)

	# Driving it: her reply that takes the quest on.
	@warning_ignore("return_value_discarded")
	Dialogue.start(&"shopkeeper")
	var taken: bool = await _pick_action(&"quest")
	_check("a reply can take a quest on", taken, "found and chose it")
	await get_tree().process_frame
	_check("and it is active afterwards", Quests.is_active(&"supply_run"))
	Dialogue.close()


## Walk her conversation until a reply carrying `action` is offered, then take
## it. Bounded, so a rewrite cannot hang the suite.
##
## The walk cannot just take reply 0 every time. Doing that reaches "Show me the
## shelf" — which opens the shop and ends the conversation — several nodes
## before it reaches the one that offers the quest. So at every fork it takes
## the first reply that **goes somewhere and does nothing**: no action, and a
## `goto` that is not the exit. That is a plain depth-first walk toward the
## deepest part of the conversation, which is where a quest offer lives in every
## conversation anybody would write.
func _pick_action(action: StringName) -> bool:
	# Generous: a click finishes the typewriter and a second one advances, so a
	# node costs up to two iterations per line. The quest offer sits nine nodes
	# deep, and a bound of 40 stopped one node short of it.
	for step in 200:
		if not Dialogue.is_open():
			return false
		if Dialogue.showing_replies():
			var fallback := -1
			for i in Dialogue._choices.size():
				var choice: Dictionary = Dialogue._choices[i]
				var carries := StringName(String(choice.get("action", "")))
				if carries == action:
					Dialogue._choice = i
					Dialogue._pick()
					return true
				if fallback < 0 and carries == &"" and String(choice.get("goto", "")) != "":
					fallback = i
			if fallback < 0:
				return false
			Dialogue._choice = fallback
			Dialogue._pick()
			await get_tree().process_frame
			continue
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		Dialogue._on_box_input(event)
		await get_tree().process_frame
	return false


# ----------------------------------------------------------------- helpers

static func _held(pack: ItemsComponent, id: StringName) -> int:
	var total := 0
	for slot in pack.items.size():
		var item := pack.item_at(slot)
		if item != null and item.id == id:
			total += pack.count_at(slot)
	return total


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
