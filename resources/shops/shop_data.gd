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


func sells(id_wanted: StringName) -> bool:
	for item in stock:
		if item != null and item.id == id_wanted:
			return true
	return false


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty() and margin < markup
