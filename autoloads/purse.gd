extends Node
## The player's money.
##
## An autoload for the same reason `Village` and `Skills` are: it outlives every
## scene, and a component would be rebuilt each time a doorway swapped the level
## out. It saves itself, so no level and no player has to remember it exists.
##
## ## Gold does not drop
##
## GDD §15 A4 drops the *haul* where you fall, and `InventoryComponent`'s
## docstring is clear about why: the haul is the thing the expedition loop is
## about, and losing it is the risk that makes turning back a decision. Money is
## not that. Dropping it too would mean every death costs you the run *and* the
## errand you were saving for, which is the kind of double punishment that makes
## players stop taking the interesting route.
##
## So: a haul drops where you fall, a key does not, and neither does your purse.
##
## ## It is not a second progression track
##
## GDD §688 is blunt — "Not a hub with shops. The *rebuild state of Ambry is*
## the player's progression" — and §15's amendment log spends a page making sure
## the rebuild loop can never degrade into a shop that sells stat points. This
## exists to buy **supplies**: food, salves, the things an expedition consumes.
## What enforces that is `ShopData.stock`, not this file, but it is the reason
## this file is small and will stay small. There is no bank, no interest, no
## second currency.

## Amount changed. UI listens here; nothing polls.
signal changed(amount: int)

const GROUP: StringName = &"saveable"

## What you are carrying out of the intro. Not nothing, because a shop you
## cannot afford to enter teaches the player it is scenery, and not much,
## because the first purchase should still be a choice between two things.
const STARTING: int = 30

var _gold: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	_gold = STARTING
	# Deferred: `Hud` and the rest of the UI autoloads may not have run `_ready`
	# yet, and a purse that announces itself into an empty room leaves the coin
	# counter blank until the first coin is spent.
	_announce.call_deferred()


func amount() -> int:
	return _gold


func can_afford(cost: int) -> bool:
	return cost >= 0 and _gold >= cost


## Add (or, with a negative, take). Returns the new total. Clamped at zero
## because a debt is a mechanic, and this is not one.
func add(delta: int) -> int:
	if delta == 0:
		return _gold
	_gold = maxi(_gold + delta, 0)
	_announce()
	return _gold


## Take `cost`, or take nothing and say so. Same rule as `Village.build` and
## `Skills.unlock`: a half-paid transaction is worse than a refused one.
func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	_gold -= cost
	_announce()
	return true


## Set outright. For the debug spawner and the tests; play never calls this.
func set_amount(value: int) -> void:
	_gold = maxi(value, 0)
	_announce()


func reset() -> void:
	set_amount(STARTING)


func _announce() -> void:
	changed.emit(_gold)
	Events.player_gold_changed.emit(_gold)


# ------------------------------------------------------------------- saving

func save_id() -> StringName:
	return &"purse"


func save_data() -> Dictionary:
	return {"gold": _gold}


func load_data(data: Dictionary) -> void:
	_gold = maxi(SaveGame.read_int(data, "gold", STARTING), 0)
	_announce()
