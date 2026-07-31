class_name Shrine
extends Interactable
## A waystone: the save point and the fast-travel anchor, and the same object as
## both because they are the same promise — *you do not have to walk that again*.
##
## **Two pictures, one node.** Dormant and lit. The dormant one is what the
## player finds; the lit one is what they made. That state is the only thing this
## saves, and it is the smallest possible version of GDD §7's "save point every
## 5–6 rooms" that is still a thing the player *did* rather than a thing that
## happened to them.
##
## **What this does not do yet:** it does not travel. Choosing a destination
## needs a registry of which shrines the player has lit across every scene and a
## panel to pick from, neither of which exists. What it does today is light,
## stay lit across a save, and announce itself on the bus — which is exactly the
## part a destination picker will need, and none of the part it would have to
## replace.

## Emitted the first time a given shrine is lit. The `id` is what a travel
## network will key on, so it is a stable string rather than a node path.
signal lit(id: StringName)

## Stable across scene edits — this is a save key. Set it per instance.
@export var id: StringName = &""

## What is drawn before and after. Two textures rather than two frames of one
## strip, because they are two exported files and packing them into a strip
## would be work whose only purpose is to make this line shorter.
@export var dormant: Texture2D:
	set(value):
		dormant = value
		_refresh()
@export var kindled: Texture2D:
	set(value):
		kindled = value
		_refresh()

## Nudge the art relative to the base, for a picture whose plinth is not at the
## bottom of its canvas.
@export var art_offset: Vector2 = Vector2.ZERO:
	set(value):
		art_offset = value
		_refresh()

var is_lit: bool = false

var _sprite: Sprite2D


func _ready() -> void:
	prompt = "Rest"
	super()
	add_to_group(SaveGame.GROUP)
	_sprite = Sprite2D.new()
	_sprite.centered = true
	# Base on the origin, same rule as Prop and AnimationComponent — a shrine
	# sorted by its own centre lets the player stand in front of it and be drawn
	# behind it.
	add_child(_sprite)
	_refresh()


func _refresh() -> void:
	if _sprite == null:
		return
	var texture: Texture2D = kindled if is_lit and kindled != null else dormant
	_sprite.texture = texture
	if texture != null:
		_sprite.offset = Vector2(0, -texture.get_height() * 0.5) + art_offset


func can_interact(actor: Node) -> bool:
	return super(actor)


## Resting writes the save. Resting at one that is already lit writes it again —
## that is most of what a save point is for after the first visit.
##
## **This did not actually save until long after the docstring said it did.** It
## lit, it persisted its own lit-ness, it announced itself, and eleven assertions
## passed — all of them about the lighting. Nothing called `SaveGame`. The lesson
## is in `tests/m1_smoke_test.gd`: the check that would have caught it asserts
## the file on disk changed, not that the node's flag flipped.
func interact(actor: Node) -> void:
	if not can_interact(actor):
		return
	super(actor)
	if not is_lit:
		is_lit = true
		_refresh()
		lit.emit(id)
		Events.shrine_lit.emit(id)
	var ok := SaveGame.save_slot(SaveGame.current_slot)
	Sfx.play(&"ui_select" if ok else &"ui_deny", -4.0)
	Events.game_saved.emit(ok, SaveGame.last_error())


func save_id() -> StringName:
	return StringName("shrine:" + String(id))


func save_data() -> Dictionary:
	return {"lit": is_lit}


func load_data(data: Dictionary) -> void:
	is_lit = bool(data.get("lit", false))
	_refresh()
