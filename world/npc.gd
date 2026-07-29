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
	if _sprite != null and absf(to_target.x) > 1.0:
		_sprite.flip_h = to_target.x < 0.0


## What the dialogue box puts in its frame. The placeholder body, cropped to the
## head, in this villager's colour — which is not a portrait, but it is this
## villager rather than a blank square, and it costs nothing.
func portrait() -> Dictionary:
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
		var away: Vector2 = (actor as Node2D).global_position - global_position
		_sprite.flip_h = away.x < 0.0
	if not Dialogue.start(dialogue_id, portrait()):
		push_warning("Npc %s: nothing to say (dialogue '%s')" % [name, dialogue_id])
