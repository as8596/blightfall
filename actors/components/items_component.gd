class_name ItemsComponent
extends Node
## What the actor is carrying that isn't material: meals, tools, keys.
##
## The counterpart to `InventoryComponent`, and separate from it for the reason
## that component's own docstring gives — materials are a counted currency with
## one axis, and mixing unique things into them grows a type system that makes
## both illegible. They also behave differently in the ways that matter: a haul
## drops where you fall (GDD §15 A4), a key does not.
##
## **Slots, not a bag.** A fixed row the player can see the whole of, because the
## hotbar is the interface and a hotbar that can't show everything is a menu.

signal changed
## A slot was used and something happened. `slot` is -1 when the use came from
## somewhere other than the hotbar.
signal used(item: ItemData, slot: int)
## Nothing there, or nothing it could do. The HUD flashes the slot.
signal refused(slot: int)

## Ten, bound to 1-9 and 0. The row the hand finds without looking is five;
## the row the player is willing to scan is ten.
@export_range(1, 10) var slots: int = 10

## Filled from the inspector for a starting kit.
@export var starting_items: Array[ItemData] = []

## Parallel arrays rather than an array of dictionaries: a slot is an item and a
## count, and every read site wants one or the other.
var items: Array[ItemData] = []
var counts: Array[int] = []


func _ready() -> void:
	items.resize(slots)
	counts.resize(slots)
	for item in starting_items:
		if item != null:
			add(item)


func item_at(slot: int) -> ItemData:
	return items[slot] if slot >= 0 and slot < items.size() else null


func count_at(slot: int) -> int:
	return counts[slot] if slot >= 0 and slot < counts.size() else 0


func is_empty() -> bool:
	for item in items:
		if item != null:
			return false
	return true


## Add `amount`, stacking onto a matching slot first. Returns how many were
## taken — a partial pickup is correct, not an error, exactly as it is for
## materials.
func add(item: ItemData, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var taken := 0

	if item.is_stackable():
		for i in items.size():
			if items[i] != null and items[i].id == item.id and counts[i] < item.stack_size:
				var room: int = mini(item.stack_size - counts[i], amount - taken)
				counts[i] += room
				taken += room
				if taken >= amount:
					break

	while taken < amount:
		var slot := _first_free()
		if slot < 0:
			break
		items[slot] = item
		counts[slot] = mini(item.stack_size, amount - taken)
		taken += counts[slot]

	if taken > 0:
		changed.emit()
	return taken


func remove(slot: int, amount: int = 1) -> int:
	if slot < 0 or slot >= items.size() or items[slot] == null:
		return 0
	var gone: int = mini(amount, counts[slot])
	counts[slot] -= gone
	if counts[slot] <= 0:
		items[slot] = null
		counts[slot] = 0
	if gone > 0:
		changed.emit()
	return gone


## Use what is in `slot` on `actor`. Returns whether anything happened.
##
## The component owns the effect rather than the caller, so "what does eating do"
## lives in one place and the hotbar, a menu and a script all get the same
## answer.
func use(slot: int, actor: Node) -> bool:
	var item := item_at(slot)
	if item == null or not item.is_quick_usable() or not _apply(item, actor):
		refused.emit(slot)
		return false
	if item.kind == ItemData.Kind.CONSUMABLE:
		remove(slot, 1)
	used.emit(item, slot)
	return true


func _apply(item: ItemData, actor: Node) -> bool:
	if item.kind != ItemData.Kind.CONSUMABLE or item.heals <= 0:
		# Tools do their work through the tool verb, which does not exist yet
		# (GDD §5, M3). Refusing is honest; pretending it worked is not.
		return false
	var health := _health_of(actor)
	if health == null or health.current >= health.max_health:
		# Eating at full health is a wasted meal, and the player did not mean it.
		return false
	health.heal(item.heals)
	return true


static func _health_of(actor: Node) -> HealthComponent:
	if actor == null:
		return null
	for child in actor.get_children():
		var health := child as HealthComponent
		if health != null:
			return health
	return null


func _first_free() -> int:
	for i in items.size():
		if items[i] == null:
			return i
	return -1


# ------------------------------------------------------------------- saving

func save_data() -> Dictionary:
	var stored: Array = []
	for i in items.size():
		stored.append({
			"id": String(items[i].id) if items[i] != null else "",
			"count": counts[i],
		})
	return {"slots": stored}


## Ids are resolved against the item library rather than stored as resource
## paths — a save must never name a script or a resource to load (see
## `systems/save/save_game.gd`), and a renamed file must not empty someone's bag.
func load_data(data: Dictionary, library: Dictionary) -> void:
	var stored: Variant = data.get("slots")
	if not (stored is Array):
		return
	items.resize(slots)
	counts.resize(slots)
	for i in items.size():
		items[i] = null
		counts[i] = 0
	var list: Array = stored
	for i in mini(list.size(), items.size()):
		if not (list[i] is Dictionary):
			continue
		var entry: Dictionary = list[i]
		var id := StringName(SaveGame.read_string(entry, "id", ""))
		if id == &"" or not library.has(id):
			continue
		items[i] = library[id]
		counts[i] = maxi(SaveGame.read_int(entry, "count", 1), 1)
	changed.emit()
