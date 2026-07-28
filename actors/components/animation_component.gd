class_name AnimationComponent
extends Node
## Drives an actor's Sprite2D from its state machine.
##
## Two kinds of animation live here and they are driven completely differently:
##
## **Free-running** — idle, walk, death. These have their own clock (`fps`) and
## nothing hangs off their timing.
##
## **Frame-data driven** — attacks. These have *no* clock. `PlayerAttackState`
## already tracks elapsed time against the windup / active / recovery boundaries
## in `ComboStepData`, and calls `set_manual_frame()` with the phase it is in.
## This is not a stylistic preference: a 3-frame attack at 12fps runs 0.25s while
## hit 1 runs 0.34s, so a free-running swing finishes before its own hitbox does
## and the picture starts disagreeing with the hitbox about when the player is
## about to be hit.
##
## Works with no art at all. Given no animation set, it generates a flat
## placeholder texture at `placeholder_size`, which is what keeps the grey-box
## prototype running while sprites are drawn one at a time.

enum Facing { DOWN, UP, SIDE }

@export var sprite_path: NodePath = ^"../Visual"

## Leave null to run on generated placeholder boxes.
##
## Assigning this at runtime has to undo the placeholder, not just sit on top of
## it — the placeholder carries its colour in `modulate`, and leaving that in
## place would tint every real sprite the actor ever draws.
@export var animations: ActorAnimationSet:
	set(value):
		animations = value
		if sprite == null:
			return                      # pre-_ready; _ready will pick it up
		if value == null:
			_install_placeholder()
			return
		sprite.modulate = Color.WHITE
		if value.idle != null:
			play(value.idle)

## Body height in pixels. Sets the sprite offset so the actor's feet land on the
## node origin — which is what makes y-sorting correct.
##
## The same offset works for a body-sized placeholder and for a larger frame
## canvas with the body anchored inside it, because in both cases the feet sit
## exactly `body_height / 2` below the texture's centre.
@export var body_height: float = 96.0

## Placeholder box size and colour, used when `animations` is null.
@export var placeholder_size: Vector2 = Vector2(64, 96)
@export var placeholder_color: Color = Color(0.78, 0.82, 0.88)

var sprite: Sprite2D

var _set_state_automatically: bool = true
var _current: SpriteAnimation
var _facing := Facing.DOWN
var _flip: bool = false
var _time: float = 0.0
var _frame: int = 0
var _manual: bool = false
var _actor: Node2D
var _machine: StateMachine


func _ready() -> void:
	sprite = get_node_or_null(sprite_path) as Sprite2D
	if sprite == null:
		push_warning("AnimationComponent on %s: no Sprite2D at '%s'." % [get_parent(), sprite_path])
		set_process(false)
		return
	_actor = owner as Node2D
	sprite.centered = true
	_apply_offset()
	if animations == null:
		_install_placeholder()
	else:
		# The setter above bails out when it runs before `_ready` — which is
		# always, for a set assigned in the scene file rather than at runtime —
		# and promises that `_ready` will pick it up. This is that promise.
		sprite.modulate = Color.WHITE
		if animations.idle != null:
			play(animations.idle)


## Called by the actor once its state machine exists.
func bind(machine: StateMachine) -> void:
	_machine = machine
	if machine != null:
		machine.state_changed.connect(_on_state_changed)
		_on_state_changed(&"", machine.current_state_name())


func _process(delta: float) -> void:
	_update_facing()
	if _manual or _current == null or _current.frames <= 1:
		return
	_time += delta
	var frame_time := 1.0 / maxf(_current.fps, 0.001)
	while _time >= frame_time:
		_time -= frame_time
		if _frame + 1 >= _current.frames:
			if not _current.loop:
				_frame = _current.frames - 1
				return
			_frame = 0
		else:
			_frame += 1
	sprite.frame = _frame


func _on_state_changed(_from: StringName, to: StringName) -> void:
	if not _set_state_automatically or animations == null:
		return
	var clip := animations.for_state(to)
	if clip != null:
		play(clip)


## Start a clip. Free-running unless `manual` — see the class comment.
func play(clip: SpriteAnimation, manual: bool = false) -> void:
	if clip == null or not clip.is_valid() or sprite == null:
		return
	_current = clip
	_manual = manual
	_time = 0.0
	_frame = 0
	_apply_texture()


## Play combo hit `index`, advanced by the attack state rather than by fps.
func play_attack(index: int) -> void:
	if animations == null:
		return
	var clip := animations.attack(index)
	if clip != null:
		play(clip, true)


## Set the frame directly. Used by frame-data-driven animations, where `phase`
## is 0 = windup, 1 = active, 2 = recovery.
func set_manual_frame(phase: int) -> void:
	if _current == null or sprite == null:
		return
	_frame = clampi(phase, 0, _current.frames - 1)
	sprite.frame = _frame


## Stop reacting to state changes — for cutscenes, or a state that wants full
## control of what is on screen.
func set_automatic(enabled: bool) -> void:
	_set_state_automatically = enabled


func _update_facing() -> void:
	if _actor == null or not ("facing" in _actor):
		return
	var f: Vector2 = _actor.facing
	var wanted := _facing
	var flip := _flip
	if absf(f.x) > absf(f.y):
		wanted = Facing.SIDE
		flip = f.x < 0.0
	elif f.y < 0.0:
		wanted = Facing.UP
		flip = false
	else:
		wanted = Facing.DOWN
		flip = false
	if wanted == _facing and flip == _flip:
		return
	_facing = wanted
	_flip = flip
	sprite.flip_h = flip
	_apply_texture()


func _apply_texture() -> void:
	if _current == null or sprite == null:
		return
	var texture := _current.texture_for(_facing)
	if texture == null:
		return
	sprite.texture = texture
	sprite.hframes = maxi(_current.frames, 1)
	sprite.vframes = 1
	sprite.frame = mini(_frame, _current.frames - 1)
	_apply_offset()


func _apply_offset() -> void:
	# Feet on the node origin. See body_height.
	sprite.offset = Vector2(0, -body_height * 0.5)


## A flat rectangle standing in for art that doesn't exist yet.
##
## Filled white, with the colour carried in `modulate`. That keeps one rule for
## both worlds: a tint (an enemy telegraph, say) *replaces* the base colour
## rather than multiplying into mud, and the moment real art arrives the base
## modulate becomes white and the same tint still reads as a tint.
func _install_placeholder() -> void:
	var image := Image.create(
		int(placeholder_size.x), int(placeholder_size.y), false, Image.FORMAT_RGBA8
	)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.hframes = 1
	sprite.vframes = 1
	body_height = placeholder_size.y
	sprite.modulate = placeholder_color
	_apply_offset()


## Resize the placeholder after the actor has loaded its data.
func set_placeholder(size: Vector2, colour: Color) -> void:
	placeholder_size = size
	placeholder_color = colour
	if animations == null:
		_install_placeholder()
	else:
		body_height = size.y
		_apply_offset()


## The modulate an actor sits at when nothing is tinting it: the placeholder
## colour while there is no art, white once there is. States that tint (the
## enemy telegraph) restore to this rather than assuming white.
func base_modulate() -> Color:
	return Color.WHITE if animations != null else placeholder_color


func current_frame() -> int:
	return _frame


func has_art() -> bool:
	return animations != null
