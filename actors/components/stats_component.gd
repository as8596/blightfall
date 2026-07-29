class_name StatsComponent
extends Node
## The player's numbers, and the only thing allowed to move them.
##
## GDD §15 A7 amends A4: the player has real stats now, and the village is what
## writes to them. The rule that keeps A4's intent alive is enforced here rather
## than remembered — **every modifier carries the id of the building that
## granted it**, and `apply()` refuses one without a source. There is no XP, no
## level, and no way to raise a number that is not "go and rebuild the thing".
##
## Bases are read from the components that already own them rather than copied,
## so this cannot drift out of step with the game. A stat sheet that can
## disagree with the thing it describes is worse than no sheet.

signal changed

## Named so a typo is a missing key rather than a silently wrong number.
const MAX_HEALTH := &"max_health"
const CARRY := &"carry"
const DAMAGE := &"damage"
const REACH := &"reach"
const MOVE_SPEED := &"move_speed"
## Extra points in the pool.
const STAMINA := &"stamina"
## Percent faster recovery — applied to both the pause before regen starts and
## the time it takes to fill. A rested character is a different character, and
## it is the kind of improvement a town can plausibly give you.
const STAMINA_REGEN := &"stamina_regen"

## {source_id: {stat: delta}}. Keyed by source so a building being un-built —
## or a save being loaded — removes exactly what it added.
var _modifiers: Dictionary = {}

var _base: Dictionary = {}

## Shipped recovery numbers, kept so a percentage can be applied to them
## repeatedly without compounding.
var base_max_stamina: float = 4.0
var base_regen_delay: float = 0.7
var base_regen_time: float = 6.0


## How much faster recovery is than it shipped, as a multiplier.
func regen_speed() -> float:
	return 1.0 + float(bonus(STAMINA_REGEN)) / 100.0


func _ready() -> void:
	var actor := get_parent()
	if actor == null:
		return
	# Snapshot the shipped values once. Everything after this is a delta, which
	# means "what has the village given me" is answerable at any moment.
	_base = {
		MAX_HEALTH: _int_on(actor, "health", "max_health", 6),
		CARRY: _int_on(actor, "inventory", "capacity", 12),
		MOVE_SPEED: int(actor.get("move_speed") if actor.get("move_speed") != null else 328),
		DAMAGE: 0,
		REACH: 0,
		STAMINA: 0,
		STAMINA_REGEN: 0,
	}
	# Recovery timings are floats and are restored by ratio rather than by sum,
	# so they are kept apart from the integer stats above.
	var pool := actor.get_node_or_null(^"StaminaComponent") as StaminaComponent
	if pool != null:
		base_max_stamina = pool.max_stamina
		base_regen_delay = pool.regen_delay
		base_regen_time = pool.full_regen_time


## Grant `deltas` in the name of `source`. Re-granting the same source replaces
## rather than stacks, so applying a project twice cannot double it.
func apply(source: StringName, deltas: Dictionary) -> bool:
	if source == &"":
		# A4 abandoned rather than amended. See GDD §15 A7.
		push_error("StatsComponent: a modifier with no source is not allowed.")
		return false
	_modifiers[source] = deltas.duplicate()
	changed.emit()
	return true


## Take back everything `source` granted.
func revoke(source: StringName) -> void:
	if _modifiers.erase(source):
		changed.emit()


func has_source(source: StringName) -> bool:
	return _modifiers.has(source)


## Every building currently contributing, so the character sheet can say *why*
## a number is what it is rather than only what it is.
func sources() -> Array:
	return _modifiers.keys()


func base(stat: StringName) -> int:
	return int(_base.get(stat, 0))


func bonus(stat: StringName) -> int:
	var total := 0
	for source in _modifiers:
		total += int((_modifiers[source] as Dictionary).get(stat, 0))
	return total


func value(stat: StringName) -> int:
	return base(stat) + bonus(stat)


static func _int_on(actor: Node, child_name: String, property: String, fallback: int) -> int:
	var child := actor.get_node_or_null(NodePath(child_name))
	if child == null:
		return fallback
	var found: Variant = child.get(property)
	return int(found) if found != null else fallback
