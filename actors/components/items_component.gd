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
## Which slot the tool verb will act on.
signal selection_changed(slot: int)

## Forty-two: twelve on the hotbar — ten numbered plus two reserved for potions
## — and thirty behind Tab. The
## hotbar is the first ten by definition rather than by a flag, so "what is on
## my bar" needs no second list to stay in step with.
@export_range(1, 60) var slots: int = 42

## How many of those slots the hotbar shows: ten numbered, then two reserved.
const HOTBAR_SLOTS: int = 12

## The last two are for potions and nothing else. Kept apart on the bar and
## bound to `-` and `=`, so the thing you reach for in a fight is never one slot
## away from the thing you reach for out of one.
const POTION_SLOTS: int = 2

## Index of the first reserved slot.
const FIRST_POTION_SLOT: int = HOTBAR_SLOTS - POTION_SLOTS


## Whether `slot` is one of the reserved potion slots.
static func is_potion_slot(slot: int) -> bool:
	return slot >= FIRST_POTION_SLOT and slot < HOTBAR_SLOTS

## Filled from the inspector for a starting kit.
@export var starting_items: Array[ItemData] = []

## How many of each of those. Short or empty means one apiece, which is what
## every entry meant before this existed.
##
## A parallel array rather than a list of pairs, matching `items`/`counts` below
## — and it exists because arrows arrived: listing a stackable fifteen times to
## start with fifteen of them is not a kit, it is a mistake waiting to be made.
@export var starting_counts: Array[int] = []

## Parallel arrays rather than an array of dictionaries: a slot is an item and a
## count, and every read site wants one or the other.
var items: Array[ItemData] = []
var counts: Array[int] = []

## The slot the tool button uses. Selection is separate from use so the hotbar
## can be skimmed with the wheel without eating anything on the way past.
var selected: int = 0


func _ready() -> void:
	items.resize(slots)
	counts.resize(slots)
	for i in starting_items.size():
		var item := starting_items[i]
		if item == null:
			continue
		var amount: int = starting_counts[i] if i < starting_counts.size() else 1
		@warning_ignore("return_value_discarded")
		add(item, maxi(amount, 1))


## Point at `slot`, wrapping. Wrapping rather than clamping because the wheel
## has no ends and stopping dead at slot 10 feels like a fault.
func select(slot: int) -> void:
	if items.is_empty():
		return
	# Wraps within the hotbar. The wheel is a bar control; it should not walk off
	# the end of the visible row into the pack.
	var target: int = posmod(slot, mini(HOTBAR_SLOTS, items.size()))
	if target == selected:
		return
	selected = target
	selection_changed.emit(selected)


func cycle(steps: int) -> void:
	if steps != 0:
		select(selected + steps)


## Use whatever is selected. This is what the tool verb does — GDD §5 calls it
## "context-dependent", and the hotbar is the context.
func use_selected(actor: Node) -> bool:
	return use(selected, actor)


## Exchange two slots. The one operation drag-and-drop needs and the only one
## that can reorder the bar, so it lives here rather than in the menu doing it
## with two removes and two adds — which would stack, renumber, and occasionally
## drop something on the floor.
func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= items.size() or b >= items.size():
		return
	var item := items[a]
	var count := counts[a]
	items[a] = items[b]
	counts[a] = counts[b]
	items[b] = item
	counts[b] = count
	changed.emit()


func item_at(slot: int) -> ItemData:
	return items[slot] if slot >= 0 and slot < items.size() else null


func count_at(slot: int) -> int:
	return counts[slot] if slot >= 0 and slot < counts.size() else 0


func is_empty() -> bool:
	for item in items:
		if item != null:
			return false
	return true


## How many of `id` are carried, across every slot holding it.
##
## By id rather than by slot, because ammo is spent by a weapon and the weapon
## has no idea which slot the arrows ended up in — nor should it, since a partial
## stack and a full one are two slots holding the same thing.
func count_of(id: StringName) -> int:
	var total := 0
	for i in items.size():
		if items[i] != null and items[i].id == id:
			total += counts[i]
	return total


## Spend `amount` of `id`, drawing from the smallest stacks first. Returns false
## and takes nothing if there are not that many.
##
## **All or nothing.** A shot that consumed the last two of the three arrows it
## needed and then failed would be a shot that cost the player ammunition and
## gave them nothing, which is the sort of thing that gets noticed a week later
## as "arrows disappear sometimes".
##
## Smallest first because the alternative leaves a trail of one-arrow stacks
## across the pack, each one occupying a slot.
func take(id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count_of(id) < amount:
		return false
	var order: Array[int] = []
	for i in items.size():
		if items[i] != null and items[i].id == id:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return counts[a] < counts[b])
	var left := amount
	for slot in order:
		if left <= 0:
			break
		left -= remove(slot, mini(counts[slot], left))
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
