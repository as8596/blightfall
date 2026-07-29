extends Node
## What Ambry has had put back up.
##
## GDD §15 A4 makes the town the progression system: the player rebuilds it, and
## its state is a live readout of whether they are winning. The map already
## carries the eight plots and what each one costs — see `Level.rebuild_projects`
## — but the map is regenerated wholesale by a build script, so it cannot be
## where "the forge is standing" lives. That is this.
##
## **An autoload rather than a node in Ambry.** Village state has to survive
## walking out of the village, which is the entire point of it: the reason to go
## into the valley is to come back with something. A node in the level scene
## would forget every time the player left through the south gate.
##
## It holds ids and nothing else. No positions, no scenes, no references to
## anything that could be freed — the level asks *this* what is built, never the
## other way round (GDD §12 rule 1).

## A project was completed. The village listens; so does anything that wants to
## notice the town changing.
signal built(id: StringName)

## Anything at all changed — built, or reset by a load. UI redraws on this.
signal changed

const GROUP: StringName = &"saveable"

var _built: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)


func is_built(id: StringName) -> bool:
	return _built.has(id)


func count() -> int:
	return _built.size()


## Every completed project, as a sorted list — sorted so a save file diffs
## cleanly and two runs that built the same things look the same.
func completed() -> Array:
	var ids := _built.keys()
	ids.sort()
	return ids


## Whether `project` could be started right now.
##
## `project` is an entry from `Level.rebuild_projects()`; the requirement chain
## lives in the map because that is where the buildings are, and the check lives
## here because that is where the record is.
func can_build(project: Dictionary, satchel: InventoryComponent = null) -> bool:
	var id := StringName(project.get("id", ""))
	if id == &"" or is_built(id):
		return false
	var needs := String(project.get("requires", ""))
	if needs != "" and not is_built(StringName(needs)):
		return false
	if satchel != null and not satchel.can_afford(cost_of(project)):
		return false
	return true


## What each cost tier is worth, in materials.
##
## The map authors a *tier* per project — "trivial", "low", "medium", "high" —
## rather than a shopping list, and that is the right way round: the readable
## decision is "the forge is one of the expensive ones", and the numbers behind
## it should be tunable in one place instead of eight.
##
## Three materials, per docs/AMBRY.md: timber, stone, ironwork. Ironwork only
## appears in the top two tiers, so the early village is rebuilt out of what is
## lying in the valley and the late one needs the forge's own output.
##
## The satchel holds 12 units to start (GDD §5), so a `high` project is
## deliberately several trips. That is the loop, not friction.
const TIERS: Dictionary = {
	"trivial": {&"timber": 4},
	"low": {&"timber": 8, &"stone": 2},
	"medium": {&"timber": 12, &"stone": 8, &"ironwork": 2},
	"high": {&"timber": 16, &"stone": 14, &"ironwork": 6},
}


## What a project costs, as {material: amount}.
##
## Accepts either the tier the map writes or a literal dictionary, so a one-off
## price can be set on a marker later without this needing to change.
static func cost_of(project: Dictionary) -> Dictionary:
	var cost: Variant = project.get("cost", {})
	if cost is Dictionary:
		return (cost as Dictionary).duplicate()
	var tier := String(cost)
	if not TIERS.has(tier):
		if tier != "":
			push_warning("Village: unknown cost tier '%s' on project '%s'."
				% [tier, project.get("id", "?")])
		return {}
	return (TIERS[tier] as Dictionary).duplicate()


## Complete a project, spending the materials for it.
##
## **Spends first and only marks it built if the spend succeeded.** The other
## order is the bug where a failed transaction still finishes the building — and
## a rebuild economy that can be cheated by a full satchel is not an economy.
func build(project: Dictionary, satchel: InventoryComponent = null) -> bool:
	if not can_build(project, satchel):
		return false
	var cost := cost_of(project)
	if satchel != null and not cost.is_empty() and not satchel.spend(cost):
		return false
	var id := StringName(project.get("id", ""))
	_built[id] = true
	built.emit(id)
	Events.village_built.emit(id)
	changed.emit()
	return true


## Forget everything. A new game starts with a ruined town, not with whatever
## the last save had standing.
func reset() -> void:
	_built.clear()
	changed.emit()


func save_id() -> StringName:
	return &"village"


func save_data() -> Dictionary:
	return {"built": completed().map(func(id: StringName) -> String: return String(id))}


func load_data(data: Dictionary) -> void:
	_built.clear()
	for id in data.get("built", []):
		_built[StringName(String(id))] = true
	changed.emit()
