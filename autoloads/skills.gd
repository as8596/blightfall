extends Node
## What levelling buys.
##
## **This reverses GDD §15 A8 on purpose — see A10.** A8 said a level grants
## nothing and left `_test_experience` guarding that, while naming the risk in
## the same breath: "a progress bar that pays out nothing is a bar players will
## eventually resent. This is a placeholder for a decision, not the decision."
## This is the decision.
##
## **What survives from A7, and it is the part that mattered:** nothing moves a
## number anonymously. Skills write to `StatsComponent` under a source id of
## their own, exactly as buildings and worn gear do, so every point on the
## character sheet can still name the thing that granted it and a refund removes
## precisely what it added.
##
## **What is deliberately given up:** the village is no longer the *only* thing
## that raises a stat. It is still the only thing that raises most of them —
## six skills against eight buildings — and it remains the only source of the
## capabilities, which is the half of A4 worth keeping. A player who never
## rebuilds anything still cannot open the north gate.
##
## An autoload because skills outlive every scene, exactly like `Village`.

## A point was spent, refunded, or granted. UI redraws on this.
signal changed

## Prefix for the source ids written into `StatsComponent`.
const SOURCE_PREFIX := "skill:"

const DEFS_DIR := "res://resources/skills/defs"
const GROUP: StringName = &"saveable"

## Points per level. One, because the interesting question is which branch, not
## how many things you can have.
const POINTS_PER_LEVEL: int = 1

var _by_id: Dictionary = {}
var _unlocked: Dictionary = {}
var _available: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	_scan()
	Events.player_leveled.connect(_on_leveled)


func all() -> Array:
	var out: Array = []
	for id in _by_id:
		out.append(_by_id[id])
	out.sort_custom(func(a: SkillData, b: SkillData) -> bool:
		if a.branch != b.branch:
			return a.branch < b.branch
		# Prerequisites first inside a branch, so a column reads top to bottom.
		return a.requires == &"" and b.requires != &"")
	return out


func get_skill(id: StringName) -> SkillData:
	return _by_id.get(id)


func points() -> int:
	return _available


func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


func spent() -> int:
	var total := 0
	for id in _unlocked:
		var skill: SkillData = _by_id.get(id)
		total += skill.cost if skill != null else 1
	return total


## Whether this could be taken right now: it exists, is not already taken, its
## prerequisite is met, and there are points for it.
func can_unlock(id: StringName) -> bool:
	var skill: SkillData = _by_id.get(id)
	if skill == null or is_unlocked(id):
		return false
	if skill.requires != &"" and not is_unlocked(skill.requires):
		return false
	return _available >= skill.cost


## Take it. Returns false and changes nothing if it could not be taken — a
## half-spent point is worse than a refused one, same rule as `Village.build`.
func unlock(id: StringName, stats: StatsComponent = null) -> bool:
	if not can_unlock(id):
		return false
	var skill: SkillData = _by_id[id]
	_available -= skill.cost
	_unlocked[id] = true
	_apply_one(skill, stats)
	changed.emit()
	return true


## Grant points directly. For the debug spawner and the tests; levelling goes
## through `_on_leveled`.
func grant(amount: int) -> void:
	_available = maxi(_available + amount, 0)
	changed.emit()


## Push every unlocked skill into a fresh `StatsComponent`.
##
## Called when a player enters a scene, because the component is per-actor and
## this is not — a skill taken in one level has to still be applied two scenes
## later, and the component that knew about it has been freed.
func apply_all(stats: StatsComponent) -> void:
	if stats == null:
		return
	for id in _by_id:
		var skill: SkillData = _by_id[id]
		if is_unlocked(id):
			_apply_one(skill, stats)
		else:
			stats.revoke(_source_of(skill))


func reset() -> void:
	_unlocked.clear()
	_available = 0
	changed.emit()


func _apply_one(skill: SkillData, stats: StatsComponent) -> void:
	if stats == null or skill.modifiers.is_empty():
		return
	@warning_ignore("return_value_discarded")
	stats.apply(_source_of(skill), skill.modifiers)


static func _source_of(skill: SkillData) -> StringName:
	return StringName(SOURCE_PREFIX + String(skill.id))


func _on_leveled(_level: int) -> void:
	grant(POINTS_PER_LEVEL)


## Scanned rather than listed, for the reason `Items` gives: a hand-maintained
## list of every skill is a list that goes stale the first time one is added.
func _scan() -> void:
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		push_warning("Skills: no directory at %s." % DEFS_DIR)
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var skill := load("%s/%s" % [DEFS_DIR, name]) as SkillData
		if skill == null or not skill.is_valid():
			push_warning("Skills: %s is not a usable SkillData." % name)
			continue
		if _by_id.has(skill.id):
			push_error("Skills: duplicate id '%s'." % skill.id)
			continue
		_by_id[skill.id] = skill


func save_id() -> StringName:
	return &"skills"


func save_data() -> Dictionary:
	var taken := _unlocked.keys()
	taken.sort()
	return {
		"points": _available,
		"unlocked": taken.map(func(id: StringName) -> String: return String(id)),
	}


func load_data(data: Dictionary) -> void:
	_unlocked.clear()
	_available = int(data.get("points", 0))
	for id in data.get("unlocked", []):
		var key := StringName(String(id))
		if _by_id.has(key):
			_unlocked[key] = true
	changed.emit()
