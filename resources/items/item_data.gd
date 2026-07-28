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
}

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var kind: Kind = Kind.CONSUMABLE

## How many fit in one slot. Tools and keys are 1.
@export_range(1, 99) var stack_size: int = 1

@export_group("Consumable")
## Hearts restored. GDD §5 gives the player 6 to start and 12 at most, so this
## is in whole hearts rather than a percentage — "two hearts" is a thing you can
## decide about mid-fight and "18%" is not.
@export_range(0, 12) var heals: int = 0


func is_stackable() -> bool:
	return stack_size > 1


## Whether this belongs in the hotbar at all. A key in a quick slot is a slot
## the player has lost.
func is_quick_usable() -> bool:
	return kind == Kind.CONSUMABLE or kind == Kind.TOOL


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty()
