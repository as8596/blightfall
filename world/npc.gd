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
## Ignored once `animations` is set — a tint over real art is a bug that looks
## like a lighting choice.
@export var tint: Color = Color(0.78, 0.74, 0.66)

## Real sprites, when this villager has been drawn. Everyone else stays a tinted
## rectangle, which is honest: GDD §8's sprite budget puts the player first, one
## enemy second and the zone 1 tileset third, so most of the cast is not due yet.
##
## Given a set, this uses the same `AnimationComponent` the player and the
## enemies use — so an NPC with art turns to face you through the same eight-way
## code, rather than through a second implementation that drifts from it.
@export var animations: ActorAnimationSet

## Only meaningful with `animations`: the drawn height, for the offset that puts
## the feet on the origin. `tools/import_pixellab.py` prints it.
@export var body_height: float = 96.0

const BODY: Texture2D = preload("res://art/sprites/player_greybox/player_greybox_idle_down.png")

## Two frames of breath at this rate. Nothing here is animation; it is enough
## motion that a standing figure does not read as scenery.
const BREATH_FPS: float = 2.0

## How far they drift from where the map put them.
##
## Deliberately under half a tile. These have no collision body — they are
## `Area2D`s, detected rather than detecting — so nothing stops them walking
## into a wall, and the only safe wander is one that cannot leave the tile the
## map already proved was standable. Read as somebody shifting their weight and
## looking around, not as a patrol route.
@export var wander_radius: float = 22.0
@export var wander_speed: float = 26.0
## Seconds of standing still between drifts, picked in this range.
@export var rest_min: float = 1.6
@export var rest_max: float = 5.0

var _sprite: Sprite2D
var _time: float = 0.0
var _home: Vector2
var _target: Vector2
var _rest: float = 0.0
var _frames: int = 2
var _facing: int = AnimationComponent.Facing.DOWN

## True while the player's interactor has us as its target. See `set_highlighted`.
var _focused: bool = false


func _ready() -> void:
	# Before `super()`, which is what builds the prompt label off it.
	prompt = "Talk"
	super()
	_build_body()
	# `call_deferred` because `Level` positions us *after* instancing, so home is
	# not known yet at `_ready`.
	_settle.call_deferred()
	# Talking to somebody is not something to be doing while a conversation is
	# already open, and the interactor has no idea one is.
	set_process(true)


func _settle() -> void:
	_home = global_position
	_target = _home
	# Staggered, or a street full of villagers all steps off in lockstep.
	_rest = Rng.randf_range(0.0, rest_max)


func _build_body() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	if animations != null and animations.idle != null:
		var clip := animations.idle
		_sprite.texture = clip.down
		_sprite.hframes = maxi(clip.frames, 1)
		_sprite.offset = Vector2(0, -body_height * 0.5)
		_frames = maxi(clip.frames, 1)
		return
	_sprite.texture = BODY
	_sprite.hframes = 2
	_frames = 2
	# Same rule as `AnimationComponent`: the feet sit on the node origin, or
	# y-sorting puts a villager behind the ground they are standing on.
	_sprite.offset = Vector2(0, -48)
	_sprite.modulate = tint


func _process(delta: float) -> void:
	_time += delta
	if _sprite != null:
		_sprite.frame = int(_time * BREATH_FPS) % _frames
	_wander(delta)


## Drift, pause, drift. Through `Rng` rather than a local generator, because GDD
## §12 rule 5 puts every bit of randomness in the game through one seeded source
## — including this, which is the least important of them and would be the first
## to be excused.
func _wander(delta: float) -> void:
	# Stand still when somebody is about to talk to you. The interactor already
	# tells us when we are the thing it would act on, so this needs no proximity
	# check of its own — and a villager who wanders off the moment the prompt
	# appears is a villager you chase.
	if wander_radius <= 0.0 or _focused or Dialogue.is_open():
		return
	if _rest > 0.0:
		_rest -= delta
		return

	var to_target := _target - global_position
	if to_target.length() < 2.0:
		global_position = _target
		_rest = Rng.randf_range(rest_min, rest_max)
		_target = _home + Vector2(Rng.randf_range(-1.0, 1.0),
			Rng.randf_range(-0.6, 0.6)).normalized() * Rng.randf_range(6.0, wander_radius)
		return

	global_position += to_target.normalized() * wander_speed * delta
	_face(to_target)


## Point the body along a direction, using the eight-way resolver so a villager
## with real art turns the same way the player does — including refusing to
## mirror an asymmetric one.
func _face(direction: Vector2) -> void:
	if _sprite == null:
		return
	if animations == null or animations.idle == null:
		if absf(direction.x) > 1.0:
			_sprite.flip_h = direction.x < 0.0
		return
	var facing := AnimationComponent.facing_for(direction, _facing)
	if facing == _facing:
		return
	_facing = facing
	var chosen := animations.idle.resolve(_facing)
	if chosen["texture"] != null:
		_sprite.texture = chosen["texture"]
		_sprite.flip_h = chosen["flip"]


## What the dialogue box puts in its frame. The placeholder body, cropped to the
## head, in this villager's colour — which is not a portrait, but it is this
## villager rather than a blank square, and it costs nothing.
func portrait() -> Dictionary:
	if animations != null and animations.idle != null and animations.idle.down != null:
		# Frame 0 of the front-facing strip, cropped to the head. No tint: the
		# art is the character.
		return {"texture": animations.idle.down, "region": Dialogue.BUST}
	return {"texture": BODY, "region": Dialogue.BUST, "tint": tint}


func set_highlighted(on: bool) -> void:
	super(on)
	_focused = on


func can_interact(actor: Node) -> bool:
	if not super(actor):
		return false
	return dialogue_id != &"" and not Dialogue.is_open() and not Dialogue.just_closed()


func interact(actor: Node) -> void:
	super(actor)
	# Face whoever is talking to you. It costs one line and its absence is the
	# kind of thing that makes a village feel like a diorama.
	if actor is Node2D:
		_face((actor as Node2D).global_position - global_position)
	if not Dialogue.start(dialogue_id, portrait()):
		push_warning("Npc %s: nothing to say (dialogue '%s')" % [name, dialogue_id])
