class_name InventoryComponent
extends Node
## What the player is carrying out of a zone, and how much more will fit.
##
## The capacity is the point. A4's loop is expedition → haul → rebuild, and the
## interesting decision in it is *when to turn back* — which only exists if you
## can be full. An unlimited satchel turns every run into "clear the zone", and
## the walk home into administration.
##
## Deliberately not a general item system. It holds counted materials, nothing
## else: no equipment, no stacking rules, no slots. Unique items and key items
## belong somewhere else, because the moment this handles both it grows a type
## system and stops being legible.

signal changed(carried: int, capacity: int)
signal filled
signal rejected(id: StringName)

## Total units carried, across all materials. Materials are all the same size on
## purpose — "three timber or two stone" is a decision about the *rebuild*, and
## putting a second weight axis on the carry turns it into arithmetic.
@export var capacity: int = 12

## Contents, as {StringName: int}.
var contents: Dictionary = {}


func total() -> int:
	var sum := 0
	for count in contents.values():
		sum += int(count)
	return sum


func space_left() -> int:
	return maxi(capacity - total(), 0)


func is_full() -> bool:
	return space_left() <= 0


func count_of(id: StringName) -> int:
	return int(contents.get(id, 0))


## Add up to `amount`. Returns how many were actually taken — a partial pickup
## is correct behaviour, not an error: walking over the last ore with one slot
## free should take one, not refuse the pile.
func add(id: StringName, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, space_left())
	if taken <= 0:
		rejected.emit(id)
		return 0
	contents[id] = count_of(id) + taken
	changed.emit(total(), capacity)
	if is_full():
		filled.emit()
	return taken


## Remove up to `amount`. Returns how many were actually removed.
func remove(id: StringName, amount: int = 1) -> int:
	var held := count_of(id)
	var dropped := mini(amount, held)
	if dropped <= 0:
		return 0
	if held - dropped <= 0:
		contents.erase(id)
	else:
		contents[id] = held - dropped
	changed.emit(total(), capacity)
	return dropped


## Whether every id/amount pair in `cost` is affordable.
func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if count_of(id) < int(cost[id]):
			return false
	return true


## Spend a cost atomically. Returns false and changes nothing if short — a
## half-paid building is worse than a refused one.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		remove(id, int(cost[id]))
	return true


## Hand everything over and come back empty. Used on death and when banking a
## haul at the village.
func take_all() -> Dictionary:
	var haul := contents.duplicate()
	contents.clear()
	changed.emit(0, capacity)
	return haul


## Absorb a dictionary of contents, up to capacity. Returns whatever did not
## fit, so a recovered haul bigger than the satchel stays on the ground rather
## than evaporating.
func add_all(items: Dictionary) -> Dictionary:
	var leftover := {}
	for id in items:
		var wanted := int(items[id])
		var taken := add(StringName(id), wanted)
		if taken < wanted:
			leftover[id] = wanted - taken
	return leftover


func clear() -> void:
	contents.clear()
	changed.emit(0, capacity)


# ------------------------------------------------------------------- saving

func save_data() -> Dictionary:
	var out := {}
	for id in contents:
		out[String(id)] = int(contents[id])
	return {"capacity": capacity, "contents": out}


func load_data(data: Dictionary) -> void:
	capacity = SaveGame.read_int(data, "capacity", capacity)
	contents.clear()
	var stored: Variant = data.get("contents")
	if stored is Dictionary:
		for id in stored:
			var amount: Variant = stored[id]
			if amount is float or amount is int:
				contents[StringName(id)] = int(amount)
	changed.emit(total(), capacity)
