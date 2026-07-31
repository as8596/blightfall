extends Node
## What you have been asked to do, and how far along it is.
##
## The registry half is the same pattern as `Items`, `Skills` and `Shops`. The
## rest is a four-state machine per quest and a set of listeners that keep the
## counts honest.
##
## ## The four states
##
##     UNKNOWN -> ACTIVE -> READY -> DONE
##
## `READY` is the one worth explaining: it means every step is satisfied but you
## have not been back to whoever asked. Collapsing it into `DONE` would remove
## the return trip, and the return trip is where the reward actually lives — the
## person, not the gold.
##
## `DONE` is not final for a repeatable quest; taking it again puts it back to
## `ACTIVE` and clears its counters.
##
## ## Two kinds of progress, and only one of them is stored
##
## **Cumulative steps are counted** — kills happen once and cannot be undone, so
## `_progress` remembers them.
##
## **Everything else is derived on the spot.** Whether you are holding eight
## timber, whether the wall is rebuilt, whether you have spoken to the smith:
## all of that is already true or false somewhere else, and storing a second
## copy is how a save ends up disagreeing with the game. `step_progress` asks
## the satchel, `Village` and `Dialogue` directly.

signal changed
## A quest moved between states. UI listens here; nothing polls.
signal state_changed(id: StringName, state: int)

enum State { UNKNOWN, ACTIVE, READY, DONE }

const DEFS_DIR := "res://resources/quests/defs"
const GROUP: StringName = &"saveable"

var _by_id: Dictionary = {}
var _state: Dictionary = {}
## {quest_id: {step_index: count}} for cumulative steps only.
var _progress: Dictionary = {}
## How many times each has been finished. Repeatable quests use it; everything
## else gets it for free and the journal can say "third run".
var _completions: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	_scan()
	Events.enemy_died.connect(_on_enemy_died)
	Dialogue.action_chosen.connect(_on_dialogue_action)
	# Anything that could satisfy a derived step re-checks readiness. Cheap:
	# there are single-digit active quests and single-digit steps each.
	Events.player_materials_changed.connect(func(_c: Dictionary) -> void: _reassess())
	Events.player_items_changed.connect(func(_i: Array, _c: Array) -> void: _reassess())
	Events.village_built.connect(func(_id: StringName) -> void: _reassess())
	Dialogue.finished.connect(func(_id: StringName) -> void: _reassess())


func all() -> Array:
	return _by_id.values()


func get_quest(id: StringName) -> QuestData:
	return _by_id.get(id)


func has(id: StringName) -> bool:
	return _by_id.has(id)


## Returns `int`, not `State`. An enum declared in an autoload is a *different
## type* when reached through the singleton than it is inside this file, so a
## `State`-typed return refuses to compare against `Quests.State.READY` at every
## call site outside here. Plain ints, and the enum stays the vocabulary.
func state_of(id: StringName) -> int:
	return _state.get(id, State.UNKNOWN)


func is_active(id: StringName) -> bool:
	var at := state_of(id)
	return at == State.ACTIVE or at == State.READY


func completions(id: StringName) -> int:
	return int(_completions.get(id, 0))


const STATE_NAMES := {
	"unknown": State.UNKNOWN, "active": State.ACTIVE,
	"ready": State.READY, "done": State.DONE,
}


## Whether a dialogue condition like `"supply_run:ready"` holds.
##
## The states are `unknown`, `active`, `ready` and `done`, plus **`offerable`**
## for "could be taken right now" — which is what a giver's opening line
## actually wants, because it covers never-taken *and* finished-but-repeatable
## without the author having to remember which applies.
##
## Several may be listed: `"supply_run:ready|done"`. Omitting the state means
## `active`, which is the common case.
##
## Lives here rather than in `ui/dialogue_box.gd` so the box stays ignorant of
## what a quest is — it knows a reply carries a string and knows who to ask.
func matches(spec: String) -> bool:
	if spec == "":
		return true
	var parts := spec.split(":")
	var id := StringName(parts[0])
	if not has(id):
		push_warning("Quests: no quest '%s' (from '%s')." % [id, spec])
		return false
	for want in (parts[1] if parts.size() > 1 else "active").split("|", false):
		if want == "offerable":
			if can_offer(id):
				return true
		elif STATE_NAMES.has(want):
			if state_of(id) == STATE_NAMES[want]:
				return true
		else:
			push_warning("Quests: '%s' is not a state (from '%s')." % [want, spec])
	return false


## Every quest not in `UNKNOWN`, for the journal. Active first, then ready, then
## finished — which is the order you want to read them in.
func journal() -> Array:
	var out: Array = []
	for order in [State.READY, State.ACTIVE, State.DONE]:
		for id in _by_id:
			if state_of(id) == order:
				out.append(_by_id[id])
	return out


## Whether this could be taken right now.
func can_offer(id: StringName) -> bool:
	var quest: QuestData = _by_id.get(id)
	if quest == null:
		return false
	var at := state_of(id)
	return at == State.UNKNOWN or (at == State.DONE and quest.repeatable)


## Take it on. Returns false and changes nothing if it was not on offer — same
## rule as `Village.build` and `Skills.unlock`.
func offer(id: StringName) -> bool:
	if not can_offer(id):
		return false
	_state[id] = State.ACTIVE
	_progress[id] = {}
	_reassess()
	changed.emit()
	state_changed.emit(id, state_of(id))
	Events.quest_taken.emit(id)
	return true


## Hand it in. Consumes what the `GATHER` steps asked for and pays out.
##
## Refuses if the pack cannot hold the reward, **before taking anything**: a
## turn-in that eats your timber and then silently drops the salve because you
## had no room is the worst bug this system could have.
func turn_in(id: StringName, actor: Node = null) -> String:
	if state_of(id) != State.READY:
		return "That isn't finished."
	var quest: QuestData = _by_id[id]
	var pack: ItemsComponent = actor.get("items") if actor != null else null
	var sack: InventoryComponent = actor.get("inventory") if actor != null else null

	if pack != null and not quest.items.is_empty():
		var free := 0
		for slot in pack.items.size():
			if pack.item_at(slot) == null:
				free += 1
		if free < quest.items.size():
			return "You have no room for what she's offering."

	for step in quest.steps:
		if step.kind == QuestStep.Kind.GATHER:
			_consume(step, pack, sack)

	if quest.gold > 0:
		@warning_ignore("return_value_discarded")
		Purse.add(quest.gold)
	if quest.experience > 0 and actor != null:
		var xp: ExperienceComponent = actor.get("experience")
		if xp != null:
			xp.grant(quest.experience)
	for item in quest.items:
		if item != null and pack != null:
			@warning_ignore("return_value_discarded")
			pack.add(item, 1)

	_state[id] = State.DONE
	_completions[id] = completions(id) + 1
	_progress.erase(id)
	changed.emit()
	state_changed.emit(id, State.DONE)
	Events.quest_completed.emit(id)
	return ""


## `{"action": "quest", "quest": "supply_run"}` takes it on;
## `{"action": "turn_in", "quest": "supply_run"}` hands it back.
##
## The same seam the shop uses. A refusal is pushed onto `Events.quest_refused`
## rather than swallowed, because the one case that will happen in play — a full
## pack at turn-in — has to reach the player somehow, and the conversation has
## already moved on by the time we know.
func _on_dialogue_action(action: StringName, params: Dictionary) -> void:
	var id := StringName(String(params.get("quest", "")))
	if action == &"quest":
		if id != &"" and not offer(id):
			push_warning("Quests: '%s' was not on offer." % id)
	elif action == &"turn_in":
		var refusal := turn_in(id, _player())
		if refusal != "":
			Events.quest_refused.emit(id, refusal)


# ---------------------------------------------------------------- progress

## How far along one step is, as [done, needed].
func step_progress(quest: QuestData, index: int, actor: Node = null) -> Array:
	var step: QuestStep = quest.steps[index]
	match step.kind:
		QuestStep.Kind.SLAY:
			var counted: Dictionary = _progress.get(quest.id, {})
			return [mini(int(counted.get(index, 0)), step.count), step.count]
		QuestStep.Kind.BUILD:
			return [step.count if Village.is_built(step.target) else 0, step.count]
		QuestStep.Kind.TALK:
			var spoken := Dialogue.has_seen(step.target, step.node)
			return [step.count if spoken else 0, step.count]
		_:
			return [mini(_held(step.target, actor), step.count), step.count]


func step_done(quest: QuestData, index: int, actor: Node = null) -> bool:
	var at := step_progress(quest, index, actor)
	return int(at[0]) >= int(at[1])


## The journal line for a step, generated unless the author overrode it.
static func step_text(step: QuestStep) -> String:
	if step.text != "":
		return step.text
	match step.kind:
		QuestStep.Kind.SLAY:
			return "Kill %d %s" % [step.count, _name_of_enemy(step.target)]
		QuestStep.Kind.BUILD:
			return "Rebuild the %s" % String(step.target).replace("_", " ")
		QuestStep.Kind.TALK:
			return "Speak to the %s" % String(step.target).replace("_", " ")
		_:
			return "Bring %d %s" % [step.count, _name_of_thing(step.target).to_lower()]


static func _name_of_thing(id: StringName) -> String:
	if Materials.known(id):
		return Materials.name_of(id)
	var item := Items.get_item(id)
	return item.display_name if item != null else String(id).capitalize()


static func _name_of_enemy(id: StringName) -> String:
	return String(id).replace("_", " ")


## What the player is holding of `target`, across both collections. A quest does
## not care which bag the game keeps a thing in.
func _held(target: StringName, actor: Node) -> int:
	if actor == null:
		actor = _player()
	if actor == null:
		return 0
	var sack: InventoryComponent = actor.get("inventory")
	if sack != null and sack.count_of(target) > 0:
		return sack.count_of(target)
	var pack: ItemsComponent = actor.get("items")
	if pack == null:
		return 0
	var total := 0
	for slot in pack.items.size():
		var item := pack.item_at(slot)
		if item != null and item.id == target:
			total += pack.count_at(slot)
	return total


func _consume(step: QuestStep, pack: ItemsComponent, sack: InventoryComponent) -> void:
	var owed := step.count
	if sack != null and sack.count_of(step.target) > 0:
		owed -= sack.remove(step.target, owed)
	if owed <= 0 or pack == null:
		return
	for slot in pack.items.size():
		if owed <= 0:
			break
		var item := pack.item_at(slot)
		if item != null and item.id == step.target:
			owed -= pack.remove(slot, owed)


func _on_enemy_died(enemy: Node) -> void:
	var data: EnemyData = enemy.get("data") if enemy != null else null
	if data == null or data.id == &"":
		return
	var moved := false
	for id in _by_id:
		if state_of(id) != State.ACTIVE:
			continue
		var quest: QuestData = _by_id[id]
		for i in quest.steps.size():
			var step: QuestStep = quest.steps[i]
			if step.kind != QuestStep.Kind.SLAY or step.target != data.id:
				continue
			var counted: Dictionary = _progress.get(id, {})
			counted[i] = int(counted.get(i, 0)) + 1
			_progress[id] = counted
			moved = true
	if moved:
		_reassess()
		changed.emit()


## Promote anything whose steps are all met, and demote anything whose are not.
##
## **Both directions.** Selling the timber you were asked to bring puts the
## quest back to `ACTIVE`, because the alternative is a quest that stays ready
## while you no longer have the goods, and a turn-in that then takes nothing and
## pays out anyway.
func _reassess() -> void:
	var actor := _player()
	for id in _by_id:
		var at := state_of(id)
		if at != State.ACTIVE and at != State.READY:
			continue
		var quest: QuestData = _by_id[id]
		var met := true
		for i in quest.steps.size():
			if not step_done(quest, i, actor):
				met = false
				break
		var wanted := State.READY if met else State.ACTIVE
		if wanted != at:
			_state[id] = wanted
			state_changed.emit(id, wanted)
			changed.emit()


func _player() -> Node:
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	return scene.get("player") if scene != null else null


func reset() -> void:
	_state.clear()
	_progress.clear()
	_completions.clear()
	changed.emit()


func _scan() -> void:
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		push_warning("Quests: no directory at %s." % DEFS_DIR)
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var quest := load("%s/%s" % [DEFS_DIR, name]) as QuestData
		if quest == null or not quest.is_valid():
			push_warning("Quests: %s is not a usable QuestData." % name)
			continue
		if _by_id.has(quest.id):
			push_error("Quests: duplicate id '%s'." % quest.id)
			continue
		_by_id[quest.id] = quest


# ------------------------------------------------------------------ saving

func save_id() -> StringName:
	return &"quests"


func save_data() -> Dictionary:
	var states := {}
	for id in _state:
		states[String(id)] = int(_state[id])
	var counted := {}
	for id in _progress:
		var steps := {}
		for index in _progress[id]:
			steps[str(index)] = int(_progress[id][index])
		counted[String(id)] = steps
	var done := {}
	for id in _completions:
		done[String(id)] = int(_completions[id])
	return {"states": states, "progress": counted, "completions": done}


func load_data(data: Dictionary) -> void:
	_state.clear()
	_progress.clear()
	_completions.clear()
	# Ids no longer in the registry are dropped rather than kept, the same way
	# `Skills.load_data` drops a skill that has been removed: a save naming a
	# quest this build has never heard of is not something to carry forward.
	for id in data.get("states", {}):
		var key := StringName(String(id))
		if _by_id.has(key):
			_state[key] = int((data["states"] as Dictionary)[id])
	for id in data.get("progress", {}):
		var key := StringName(String(id))
		if not _by_id.has(key):
			continue
		var steps := {}
		for index in (data["progress"] as Dictionary)[id]:
			steps[int(String(index))] = int(((data["progress"] as Dictionary)[id] as Dictionary)[index])
		_progress[key] = steps
	for id in data.get("completions", {}):
		var key := StringName(String(id))
		if _by_id.has(key):
			_completions[key] = int((data["completions"] as Dictionary)[id])
	_reassess()
	changed.emit()
