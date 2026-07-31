class_name ShopCart
extends RefCounted
## What you have picked up in a shop but not yet paid for.
##
## **Buying one thing at a time was the wrong model.** It made every purchase a
## commitment, so the interesting question — *can I afford the stew if I sell
## the timber?* — could only be answered by doing it and hoping. A cart lets the
## whole trade be assembled and looked at before any of it is real, and it means
## selling a haul and spending the proceeds is one action rather than eleven.
##
## Holds ids and counts, never slots. Slots move as things are removed, so a
## cart that remembered "slot 14" would be wrong the moment the first line was
## settled. `Shops.settle` resolves ids to slots at the last possible moment.

## {item_id: count} she is selling to you.
var buys: Dictionary = {}
## {item_id: count} out of your pack.
var sell_items: Dictionary = {}
## {material_id: count} out of your satchel.
var sell_materials: Dictionary = {}


func is_empty() -> bool:
	return buys.is_empty() and sell_items.is_empty() and sell_materials.is_empty()


func clear() -> void:
	buys.clear()
	sell_items.clear()
	sell_materials.clear()


func count_buying(id: StringName) -> int:
	return int(buys.get(id, 0))


func count_selling(id: StringName) -> int:
	return int(sell_items.get(id, 0)) + int(sell_materials.get(id, 0))


## How many of `id` are still on the player, given they hold `held`.
##
## **This is what stops the same loaf being sold twice**: the shop's "yours"
## column lists this rather than the raw holding, so a stack moved wholly into
## the cart disappears from the shelf it came off.
##
## Takes the holding rather than looking it up, because the caller is UI and UI
## reads `Hud`'s pushed cache rather than reaching for the player — the version
## of this that fetched the player rendered an empty sell column for a player
## holding seven timber, which is exactly the bug that rule exists to prevent.
func left_of(id: StringName, held: int) -> int:
	return maxi(held - count_selling(id), 0)


## Move `delta` into or out of a line, dropping it at zero. One method for both
## directions so "add one" and "take one back" cannot disagree about when a line
## disappears.
static func _shift(into: Dictionary, id: StringName, delta: int) -> void:
	var now := int(into.get(id, 0)) + delta
	if now <= 0:
		into.erase(id)
	else:
		into[id] = now


func add_buy(id: StringName, amount: int = 1) -> void:
	_shift(buys, id, amount)


func add_sell_item(id: StringName, amount: int = 1) -> void:
	_shift(sell_items, id, amount)


func add_sell_material(id: StringName, amount: int = 1) -> void:
	_shift(sell_materials, id, amount)


## What the whole cart costs you, in gold. Negative means she owes you.
func net(shop: ShopData) -> int:
	return cost(shop) - credit(shop)


func cost(shop: ShopData) -> int:
	var total := 0
	for id in buys:
		total += shop.price_of(Items.get_item(id)) * int(buys[id])
	return total


func credit(shop: ShopData) -> int:
	var total := 0
	for id in sell_items:
		total += shop.offer_for(Items.get_item(id)) * int(sell_items[id])
	for id in sell_materials:
		total += shop.offer_for_material(id) * int(sell_materials[id])
	return total
