class_name HaulCache
extends Area2D
## Everything the player was carrying when they died, left where they fell.
##
## This is the mechanic that decides whether A4's loop is an adventure or a
## commute. Gathering with nothing at stake makes the walk home dead time; a
## haul you can lose makes the question "one more room, or turn back now?"
## a real one, and extends the tension of the zone across the return journey —
## which is otherwise the least interesting part of an expedition game.
##
## One cache at a time, by design. A second death moves the pile rather than
## scattering the valley with them: the player has one thing to go back for and
## always knows where it is, so the stake is legible instead of a bookkeeping
## exercise. It is a stake, not a punishment — nothing is destroyed, only
## displaced, and it waits indefinitely.

signal recovered(items: Dictionary)

const GROUP: StringName = &"haul_cache"

## Seconds before it can be picked back up, so the player does not re-absorb
## their own cache during the death animation.
@export var arm_delay: float = 1.0

@export var contents: Dictionary = {}

@onready var visual: Sprite2D = $Visual

var _armed: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SaveGame.GROUP)
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	if arm_delay > 0.0:
		get_tree().create_timer(arm_delay).timeout.connect(arm)
	else:
		arm.call_deferred()


## Make the cache collectable.
##
## Sweeps whatever is already standing on it rather than only listening for
## `body_entered`. Dying on the spot and respawning there is the normal case for
## a save point near where you fell, and there is no *entry* event for a body
## that never left — the haul would sit under the player's feet, visible and
## uncollectable, until they stepped off and back on.
func arm() -> void:
	_armed = true
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_on_body_entered(body)


## Drop `items` at `where`, replacing any existing cache.
static func drop(tree: SceneTree, scene: PackedScene, parent: Node, where: Vector2,
		items: Dictionary) -> HaulCache:
	if items.is_empty() or scene == null:
		return null
	for existing in tree.get_nodes_in_group(GROUP):
		existing.queue_free()
	var cache: HaulCache = scene.instantiate()
	cache.contents = items.duplicate()
	parent.add_child(cache)
	cache.global_position = where
	Events.haul_dropped.emit(items, where)
	return cache


func _on_body_entered(body: Node2D) -> void:
	if not _armed or contents.is_empty():
		return
	var inventory := Pickup._inventory_of(body)
	if inventory == null:
		return

	var leftover := inventory.add_all(contents)
	var took_something := leftover.size() < contents.size() or _total(leftover) < _total(contents)
	contents = leftover

	if not took_something:
		return
	Sfx.play(&"impact_heavy", -4.0)
	if contents.is_empty():
		# Recovered in full.
		recovered.emit(contents)
		Events.haul_recovered.emit()
		queue_free()


static func _total(items: Dictionary) -> int:
	var sum := 0
	for value in items.values():
		sum += int(value)
	return sum


func total() -> int:
	return _total(contents)


# ------------------------------------------------------------------- saving
#
# A cache survives quitting. Losing a haul to a crash rather than to a mistake
# would make the stake feel arbitrary, which is the one thing it must not be.

func save_id() -> StringName:
	return &"haul_cache"


func save_data() -> Dictionary:
	var items := {}
	for id in contents:
		items[String(id)] = int(contents[id])
	return {
		"position": SaveGame.write_vector2(global_position),
		"contents": items,
	}


func load_data(data: Dictionary) -> void:
	global_position = SaveGame.read_vector2(data, "position", global_position)
	contents.clear()
	var stored: Variant = data.get("contents")
	if stored is Dictionary:
		for id in stored:
			var amount: Variant = stored[id]
			if amount is float or amount is int:
				contents[StringName(id)] = int(amount)
