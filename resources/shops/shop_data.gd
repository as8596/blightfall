class_name ShopData
extends Resource
## What one merchant will trade with you.
##
## A Resource for the same reason `ItemData` and `SkillData` are: a second
## merchant should be a `.tres` in the inspector, not a class.
##
## ## The rates are characterisation
##
## `margin` is not a balance knob that happens to live here — it is the number
## that says what kind of dealer this is. Somebody who pays 60% of a thing's
## worth and somebody who pays 25% are different people, and the player will
## work out which is which without being told, because they will have sold a
## fish to both. Writing the difference into the resource rather than into a
## global constant is what makes that possible.
##
## ## What a shop stocks is data
##
## Everything about *what* is on the shelf lives in the `.tres`. Maren currently
## sells food, a salve and two pairs of boots, and that is a decision about her
## rather than a property of shops — a second merchant with a rack of swords
## needs no change to this file and no change to any test.

## Stable id. Named by a dialogue choice's `"shop"` field.
@export var id: StringName = &""

## The name over the door, not the keeper's name. Shown as the window's title.
@export var display_name: String = ""

## One line under the title. Her patter, not a description of the UI.
@export_multiline var greeting: String = ""

## What she has. Unlimited: buying the last loaf does not empty the shelf.
##
## **Scarcity is deliberately not built yet.** A quantity per line is easy; what
## is not easy is restocking, and a shop that empties permanently is worse than
## one that never does — it turns "come back tomorrow" into "this NPC is now
## furniture". When there is a reason for the roads to start running again, that
## is the change that earns finite stock, and this is where it goes.
@export var stock: Array[ItemData] = []

## What she charges, as a multiple of `ItemData.value`. 1.0 is the list price.
@export_range(0.5, 3.0, 0.05) var markup: float = 1.0

## What she pays, as a multiple of `ItemData.value`. Always below `markup`, or
## the shop is a money printer — `is_valid()` refuses that outright rather than
## leaving it to be discovered by a player with a lot of bread.
@export_range(0.05, 1.0, 0.05) var margin: float = 0.55

## Whether she will take timber, stone and ironwork off you.
##
## **This is what connects the money to the expedition loop.** Everything else
## on this resource trades in `ItemData`, and almost nothing in the world drops
## one — the valley drops materials, and materials go in the satchel. Without
## this the sell column shows the loaf you started with and nothing else, ever.
##
## One-directional on purpose: she buys them, she does not stock them. Not a
## rule, just where it starts — a player who can buy timber can rebuild the town
## without going outside, and the walk is the game. If that turns out to be
## worth having, it is a stock array and about ten lines.
@export var buys_materials: bool = true

## What the player pays for one.
func price_of(item: ItemData) -> int:
	if item == null or not item.is_tradeable():
		return 0
	# Ceil, not round: a markup that rounds down to the list price reads as a
	# bug the one time it happens on a cheap item.
	return maxi(int(ceilf(item.value * markup)), 1)


## What the player is paid for one. Never more than it costs to buy the same
## thing back, whatever the rates are set to.
func offer_for(item: ItemData) -> int:
	if item == null or not item.is_tradeable():
		return 0
	return clampi(int(floorf(item.value * margin)), 1, price_of(item))


## What she pays for one unit of a haul material. Zero if she does not deal in
## them, or if it is not a material she recognises.
func offer_for_material(id: StringName) -> int:
	if not buys_materials or not Materials.known(id):
		return 0
	return maxi(int(floorf(Materials.value_of(id) * margin)), 1)


func sells(id_wanted: StringName) -> bool:
	for item in stock:
		if item != null and item.id == id_wanted:
			return true
	return false


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty() and margin < markup
