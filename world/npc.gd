class_name Npc
extends Interactable
## Somebody standing in the village who will talk to you.
##
## An `Interactable`, so talking is the same button and the same base class as
## opening a door — which was the whole point of building the verb before
## building any of its users.
##
## **The body is a placeholder and looks like one.** It is the player's own idle
## strip under a `modulate` tint, which is honest rather than lazy: the sprite
## budget (GDD §8) puts the player first, one enemy second and everything else
## after the zone 1 tileset, so a real villager sheet is not due yet. What is
## being proven here is that a marker in a generated map becomes a person you
## can walk up to and talk to, and that works with a tinted rectangle.

## Which conversation this is. Names a file in `resources/dialogue/`.
@export var dialogue_id: StringName = &""

## Tints the placeholder body, so a street of them is not six identical people.
@export var tint: Color = Color(0.78, 0.74, 0.66)

const BODY: Texture2D = preload("res://art/sprites/player/player_idle_down.png")

## Two frames of breath at this rate. Nothing here is animation; it is enough
## motion that a standing figure does not read as scenery.
const BREATH_FPS: float = 2.0

var _sprite: Sprite2D
var _time: float = 0.0


func _ready() -> void:
	# Before `super()`, which is what builds the prompt label off it.
	prompt = "Talk"
	super()
	_build_body()
	# Talking to somebody is not something to be doing while a conversation is
	# already open, and the interactor has no idea one is.
	set_process(true)


func _build_body() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = BODY
	_sprite.hframes = 2
	_sprite.centered = true
	# Same rule as `AnimationComponent`: the feet sit on the node origin, or
	# y-sorting puts a villager behind the ground they are standing on.
	_sprite.offset = Vector2(0, -48)
	_sprite.modulate = tint
	add_child(_sprite)


func _process(delta: float) -> void:
	_time += delta
	if _sprite != null:
		_sprite.frame = int(_time * BREATH_FPS) % 2


func can_interact(actor: Node) -> bool:
	if not super(actor):
		return false
	return dialogue_id != &"" and not Dialogue.is_open() and not Dialogue.just_closed()


func interact(actor: Node) -> void:
	super(actor)
	# Face whoever is talking to you. It costs one line and its absence is the
	# kind of thing that makes a village feel like a diorama.
	if actor is Node2D:
		var away: Vector2 = (actor as Node2D).global_position - global_position
		_sprite.flip_h = away.x < 0.0
	if not Dialogue.start(dialogue_id):
		push_warning("Npc %s: nothing to say (dialogue '%s')" % [name, dialogue_id])
