class_name EquipmentComponent
extends Node
## What the player is wearing, as opposed to what they are carrying.
##
## **This is new to the design and GDD §15 A9 is the record of it.** §2 caps the
## content budget and says nothing about equipment; A7 says every stat modifier
## names the building that granted it and that the village is the only thing
## that writes to a number. That second rule is the one that gives here — see
## the amendment. What survives is the part that mattered: nothing raises a stat
## anonymously, and the player can always point at what is doing it.
##
## Three slots and no more. A weapon, a piece of armour, and which of the four
## keys is in your hand (GDD §6). There is no wardrobe here and adding one is a
## §2 conversation, not a code change.

signal changed

## Sources are named for the **slot**, not the item.
##
## Keyed by item, swapping one sword for another would apply the new one and
## leave the old one's bonus in place forever — which does not look like a bug,
## it looks like the second sword being unusually good. Keyed by slot, equipping
## replaces, which is what equipping means.
const SOURCE_PREFIX := "equip:"

## What the player starts wearing. GDD §4 hands them nothing — the intro is an
## escape from an execution — but the intro is M6 work and until it exists an
## unarmed character cannot test the combat the whole milestone is about.
@export var starting_gear: Array[ItemData] = []

## {ItemData.Slot: ItemData}. Absent means empty.
var worn: Dictionary = {}

@onready var _stats: StatsComponent = get_parent().get_node_or_null(^"StatsComponent")


func _ready() -> void:
	for item in starting_gear:
		if item != null:
			@warning_ignore("return_value_discarded")
			equip(item)
	changed.emit.call_deferred()


func item_in(slot: ItemData.Slot) -> ItemData:
	return worn.get(slot)


func is_worn(item: ItemData) -> bool:
	return item != null and worn.get(item.slot) == item


## Put `item` on. Returns whatever came off, so the caller can put it back in the
## pack rather than destroying it — a slot that eats what it replaces is a slot
## nobody experiments with.
func equip(item: ItemData) -> ItemData:
	if item == null or not item.is_equippable():
		return null
	var previous: ItemData = worn.get(item.slot)
	if previous == item:
		return null
	worn[item.slot] = item
	_apply(item.slot)
	changed.emit()
	return previous


func unequip(slot: ItemData.Slot) -> ItemData:
	var previous: ItemData = worn.get(slot)
	if previous == null:
		return null
	worn.erase(slot)
	_apply(slot)
	changed.emit()
	return previous


## Everything currently worn, for the character sheet: [{slot, name, modifiers}].
func summary() -> Array:
	var out: Array = []
	for slot in ItemData.EQUIP_SLOTS:
		var item: ItemData = worn.get(slot)
		out.append({
			"slot": slot,
			"label": ItemData.slot_name(slot),
			"name": item.display_name if item != null else "",
			"id": item.id if item != null else &"",
			"modifiers": item.modifiers.duplicate() if item != null else {},
		})
	return out


## Push one slot's contribution into `StatsComponent`, replacing whatever that
## slot granted before. Revoked outright when the slot empties, so taking armour
## off actually takes the armour off.
func _apply(slot: ItemData.Slot) -> void:
	if _stats == null:
		return
	var source := StringName(SOURCE_PREFIX + str(slot))
	var item: ItemData = worn.get(slot)
	if item == null or item.modifiers.is_empty():
		_stats.revoke(source)
		return
	@warning_ignore("return_value_discarded")
	_stats.apply(source, item.modifiers)


func save_data() -> Dictionary:
	var out := {}
	for slot in worn:
		out[str(slot)] = String((worn[slot] as ItemData).id)
	return out


func load_data(data: Dictionary, library: Dictionary) -> void:
	worn.clear()
	for key in data:
		var item: ItemData = library.get(StringName(String(data[key])))
		if item != null and item.is_equippable():
			worn[item.slot] = item
	for slot in ItemData.EQUIP_SLOTS:
		_apply(slot)
	changed.emit()
