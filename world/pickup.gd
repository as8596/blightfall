class_name Pickup
extends Area2D
## A material lying in the world, collected by walking over it.
##
## **Hand-placed. Never dropped by an enemy** (GDD §15 A4). The moment a
## Blighted Villager drops two timber, the optimal play is a kill loop and the
## game becomes about the loop instead of the valley — and it breaks §3's
## asymmetry besides, since mercy that pays out in construction materials is not
## mercy.
##
## Walked over rather than interacted with. Materials are the routine currency
## of an expedition; making the player press a button forty times a run is a
## tax, not a decision. The interact verb is reserved for things worth stopping
## for.

signal collected(id: StringName, amount: int)

@export var material_id: StringName = &"stone"
@export var amount: int = 1

## Set false for a pickup that should wait rather than leap into a full satchel
## — the player can come back for it once they have dropped something off.
@export var allow_partial: bool = true

## Seconds before this can be picked up. Used by dropped hauls so a player who
## dies does not instantly re-absorb their own cache mid-death animation.
@export var arm_delay: float = 0.0

## What each material looks like lying on the ground.
##
## Assigned here rather than left to the scene, because a pickup is spawned from
## a map marker that knows only an id — and the scene shipped with an empty
## Sprite2D, which made every material in Orchardfall invisible. Collectable and
## unseeable is worse than absent: the player concludes the valley is empty and
## stops looking.
const ICONS: Dictionary = {
	&"timber": preload("res://art/sprites/props/material_timber.png"),
	&"stone": preload("res://art/sprites/props/material_stone.png"),
	&"ironwork": preload("res://art/sprites/props/material_ironwork.png"),
}

@onready var visual: Sprite2D = $Visual

var _armed: bool = true


func _ready() -> void:
	monitoring = true
	monitorable = false
	if visual != null and visual.texture == null:
		var icon: Texture2D = ICONS.get(material_id)
		if icon == null:
			push_warning("Pickup: nothing drawn for material '%s'." % material_id)
		visual.texture = icon
	body_entered.connect(_on_body_entered)
	if arm_delay > 0.0:
		_armed = false
		get_tree().create_timer(arm_delay).timeout.connect(arm)


## Collectable now, including by anything already standing on it — a pickup
## that spawns under the player has no entry event to wait for.
func arm() -> void:
	_armed = true
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if not _armed:
		return
	var inventory := _inventory_of(body)
	if inventory == null:
		return

	var taken := inventory.add(material_id, amount)
	if taken <= 0:
		return
	if taken < amount and not allow_partial:
		# Put it back; this pickup is all-or-nothing.
		inventory.remove(material_id, taken)
		return

	amount -= taken
	collected.emit(material_id, taken)
	Events.material_collected.emit(material_id, taken)
	Sfx.play(&"impact_light", -6.0)

	if amount <= 0:
		queue_free()


static func _inventory_of(body: Node) -> InventoryComponent:
	for child in body.get_children():
		var inventory := child as InventoryComponent
		if inventory != null:
			return inventory
	return null
