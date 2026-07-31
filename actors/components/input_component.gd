class_name InputComponent
extends Node

## Hotbar keys, 1-9 then 0. Must match `ItemsComponent.slots`.
const HOTBAR_SLOTS: int = 12
## The only place in the player's code that touches `Input` (GDD §12, rule 3).
##
## Produces an InputIntent the state machine consumes. Also owns input
## buffering: pressing attack 0.1s before the recovery window opens should
## still land, and without a buffer a 0.08s-windup combo feels like it is
## dropping inputs even when it isn't.

## Turn off to hand control to a cutscene without touching any other state.
@export var enabled: bool = true

## 8-directional movement (BUILD-PLAN week 1). Off = analog.
@export var snap_to_8_directions: bool = true

@export_range(0.0, 1.0, 0.01) var deadzone: float = 0.2

## How long a press stays queued. 0 = no buffering (feels worse; try it).
@export_range(0.0, 0.5, 0.01) var buffer_time: float = 0.12

var intent := InputIntent.new()

var _attack_buffer: float = 0.0
var _dodge_buffer: float = 0.0
var _tool_buffer: float = 0.0
var _interact_buffer: float = 0.0

## Which hotbar slot was pressed this frame, or -1. Deliberately unbuffered:
## eating is not a combat verb, and a queued meal that fires half a second after
## the danger has passed is a meal thrown away.
var _hotbar_pressed: int = -1

## Accumulated wheel steps since the last read. A mouse wheel presses and
## releases within one frame, so `is_action_just_pressed` in `_process` drops
## flicks; this is filled from `_unhandled_input` instead.
var _hotbar_scroll: int = 0


func _process(delta: float) -> void:
	_attack_buffer = maxf(_attack_buffer - delta, 0.0)
	_dodge_buffer = maxf(_dodge_buffer - delta, 0.0)
	_tool_buffer = maxf(_tool_buffer - delta, 0.0)
	_interact_buffer = maxf(_interact_buffer - delta, 0.0)

	if not enabled:
		intent.move = Vector2.ZERO
		intent.raw_move = Vector2.ZERO
		intent.attack_held = false
		intent.dodge_held = false
		intent.aim_stick = Vector2.ZERO
		_refresh_flags()
		return

	var raw := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", deadzone)
	intent.raw_move = raw
	intent.move = snap_8(raw) if snap_to_8_directions else raw

	# **The click that closed a conversation must not also swing the sword.**
	#
	# Attack is the left mouse button and a dialogue is dismissed by clicking
	# it, so the press that ends the conversation is still down on the frame the
	# world starts running again — and the player takes a swing they never asked
	# for, at whoever they were just talking to.
	#
	# The GUI consuming the click does not help: this polls `Input` directly,
	# which is deliberate (GDD §12 rule 3 keeps `Input` out of the state
	# machine, not out of here) and is not affected by a Control handling the
	# event. `Dialogue.just_closed()` is the same lock that already stops the
	# interact key reopening the conversation it just ended; this is the second
	# thing that press must not do.
	var swallow_attack := Dialogue.just_closed()
	if swallow_attack:
		_attack_buffer = 0.0
	elif Input.is_action_just_pressed(&"attack"):
		_attack_buffer = buffer_time
	if Input.is_action_just_pressed(&"dodge"):
		_dodge_buffer = buffer_time
	if Input.is_action_just_pressed(&"tool"):
		_tool_buffer = buffer_time
	if Input.is_action_just_pressed(&"interact"):
		_interact_buffer = buffer_time
	_hotbar_pressed = -1
	for slot in HOTBAR_SLOTS:
		if Input.is_action_just_pressed(&"hotbar_%d" % (slot + 1)):
			_hotbar_pressed = slot
			break
	intent.attack_held = Input.is_action_pressed(&"attack") and not swallow_attack
	intent.dodge_held = Input.is_action_pressed(&"dodge")
	# The right stick, read raw. A pad has no cursor, so aiming has to come from
	# somewhere — and this is the only place in the player's code allowed to ask
	# the hardware anything (GDD §12 rule 3).
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	intent.aim_stick = stick if stick.length() > deadzone else Vector2.ZERO
	_refresh_flags()


func _refresh_flags() -> void:
	intent.attack_buffered = _attack_buffer > 0.0
	intent.dodge_buffered = _dodge_buffer > 0.0
	intent.tool_buffered = _tool_buffer > 0.0
	intent.interact_buffered = _interact_buffer > 0.0


## Take the buffered attack, if there is one. Returns true once per press.
func consume_attack() -> bool:
	if _attack_buffer <= 0.0:
		return false
	_attack_buffer = 0.0
	intent.attack_buffered = false
	return true


func consume_dodge() -> bool:
	if _dodge_buffer <= 0.0:
		return false
	_dodge_buffer = 0.0
	intent.dodge_buffered = false
	return true


func consume_tool() -> bool:
	if _tool_buffer <= 0.0:
		return false
	_tool_buffer = 0.0
	intent.tool_buffered = false
	return true


func consume_interact() -> bool:
	if _interact_buffer <= 0.0:
		return false
	_interact_buffer = 0.0
	intent.interact_buffered = false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed(&"hotbar_next"):
		_hotbar_scroll += 1
	elif event.is_action_pressed(&"hotbar_prev"):
		_hotbar_scroll -= 1


## Wheel steps since the last call, and clears them. Unlike the buffered verbs
## this is read-and-consume, because two flicks in one frame should move two
## slots rather than one.
func take_hotbar_scroll() -> int:
	var steps := _hotbar_scroll
	_hotbar_scroll = 0
	return steps if enabled else 0


## The hotbar slot pressed this frame, or -1. Reading it does not clear it; it
## is rebuilt every frame from the raw input.
func hotbar_pressed() -> int:
	return _hotbar_pressed if enabled else -1


func clear_buffers() -> void:
	_attack_buffer = 0.0
	_dodge_buffer = 0.0
	_tool_buffer = 0.0
	_interact_buffer = 0.0
	_refresh_flags()


## Longest remaining buffer, for the debug overlay.
func buffer_remaining() -> float:
	return maxf(_attack_buffer, maxf(_dodge_buffer, _tool_buffer))


## Collapse a vector onto the nearest of eight compass directions.
static func snap_8(v: Vector2) -> Vector2:
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return Vector2.RIGHT.rotated(snappedf(v.angle(), PI / 4.0))
