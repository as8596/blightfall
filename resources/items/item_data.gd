class_name ItemData
extends Resource
## One carryable thing: a meal, a tool, a key.
##
## **Separate from `InventoryComponent` on purpose.** That component holds
## counted materials — timber, stone, ironwork — and its own docstring says it
## is deliberately not a general item system, because the moment one collection
## handles both it grows a type system and stops being legible. Materials are
## the haul; these are things you *use*. They are carried in different places,
## shown in different places, and lost in different ways: a haul drops where you
## fall, a key does not.
##
## A Resource rather than a script per item, so adding a meal is a `.tres` in
## the inspector rather than a class — the same reason `EnemyData` and
## `PlayerComboData` are resources.

enum Kind {
	## Consumed on use. The only kind with an effect today.
	CONSUMABLE,
	## Held, used with the tool verb. GDD §5's Cinderflask and its siblings.
	TOOL,
	## Never used, never dropped, never in the hotbar. Opens something.
	KEY,
	## Worn rather than used: a weapon, a piece of armour. Appended rather than
	## inserted, so the `kind = 0/1/2` already written into every `.tres` still
	## means what it meant.
	GEAR,
}

## Where this goes when it is worn rather than carried. `NONE` is everything
## you can only use or spend, which is most things.
enum Slot {
	NONE,
	## The thing you swing. Changes what the combo does, not how it is timed.
	WEAPON,
	## What you are wearing. New to the design — see GDD §15 A9.
	ARMOUR,
	## Which of the four keys is in your hand (GDD §6).
	TOOL_SLOT,
	## Boots. Appended rather than slotted in next to ARMOUR, so every `slot = n`
	## already written into a `.tres` still means what it meant.
	BOOTS,
}

## The worn slots, in the order they are shown. One list, because there were
## three copies of it and a fourth slot would have been three edits and a bug in
## whichever one got missed.
const EQUIP_SLOTS: Array = [Slot.WEAPON, Slot.ARMOUR, Slot.BOOTS, Slot.TOOL_SLOT]

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var kind: Kind = Kind.CONSUMABLE

## How many fit in one slot. Tools and keys are 1.
@export_range(1, 99) var stack_size: int = 1

## What one of these is worth, in gold, before anybody's margin.
##
## **One number, not a buy price and a sell price.** The spread belongs to the
## merchant (`ShopData.margin`), because it is a fact about *her*, not about the
## bread — and keeping it there means a second merchant who deals fairer is a
## field on her, rather than a second column on all thirty-four of these.
##
## Zero means unsellable, which is the honest default for anything the player
## should not be able to liquidate: quest keys, and anything whose loss would
## strand them. `is_tradeable()` is the one place that decides.
@export_range(0, 9999) var value: int = 0

@export_group("Equipment")
@export var slot: Slot = Slot.NONE

## What wearing this does, as {stat: delta} against `StatsComponent`'s named
## stats. A dictionary rather than a field per stat, so a new stat does not mean
## editing every item in the project.
##
## **These are applied under a source named for the slot, not for the item.**
## Keyed by item, swapping one sword for another would leave the first one's
## bonus applied forever — a bug that looks like the second sword being very
## good. See `EquipmentComponent`.
@export var modifiers: Dictionary = {}

@export_group("Consumable")
## Hearts restored. GDD §5 gives the player 6 to start and 12 at most, so this
## is in whole hearts rather than a percentage — "two hearts" is a thing you can
## decide about mid-fight and "18%" is not.
@export_range(0, 12) var heals: int = 0


func is_equippable() -> bool:
	return slot != Slot.NONE


## Whether this can be bought or sold at all.
##
## Keys never can. A player who sells the rusted key is a player who has locked
## themselves out of the thing it opens, and no amount of "are you sure" makes
## that a decision worth offering — the fix is that the option is never there.
func is_tradeable() -> bool:
	return value > 0 and kind != Kind.KEY


## What the slot is called on screen.
static func slot_name(which: Slot) -> String:
	match which:
		Slot.WEAPON: return "Weapon"
		Slot.ARMOUR: return "Armour"
		Slot.TOOL_SLOT: return "Tool"
		Slot.BOOTS: return "Boots"
		_: return ""


func is_stackable() -> bool:
	return stack_size > 1


## Whether this belongs in the hotbar at all. A key in a quick slot is a slot
## the player has lost.
func is_quick_usable() -> bool:
	return kind == Kind.CONSUMABLE or kind == Kind.TOOL


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty()
