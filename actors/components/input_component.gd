class_name InputComponent
extends Node
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


func _process(delta: float) -> void:
	_attack_buffer = maxf(_attack_buffer - delta, 0.0)
	_dodge_buffer = maxf(_dodge_buffer - delta, 0.0)
	_tool_buffer = maxf(_tool_buffer - delta, 0.0)

	if not enabled:
		intent.move = Vector2.ZERO
		intent.raw_move = Vector2.ZERO
		intent.attack_held = false
		_refresh_flags()
		return

	var raw := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", deadzone)
	intent.raw_move = raw
	intent.move = snap_8(raw) if snap_to_8_directions else raw

	if Input.is_action_just_pressed(&"attack"):
		_attack_buffer = buffer_time
	if Input.is_action_just_pressed(&"dodge"):
		_dodge_buffer = buffer_time
	if Input.is_action_just_pressed(&"tool"):
		_tool_buffer = buffer_time
	intent.attack_held = Input.is_action_pressed(&"attack")
	_refresh_flags()


func _refresh_flags() -> void:
	intent.attack_buffered = _attack_buffer > 0.0
	intent.dodge_buffered = _dodge_buffer > 0.0
	intent.tool_buffered = _tool_buffer > 0.0


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


func clear_buffers() -> void:
	_attack_buffer = 0.0
	_dodge_buffer = 0.0
	_tool_buffer = 0.0
	_refresh_flags()


## Longest remaining buffer, for the debug overlay.
func buffer_remaining() -> float:
	return maxf(_attack_buffer, maxf(_dodge_buffer, _tool_buffer))


## Collapse a vector onto the nearest of eight compass directions.
static func snap_8(v: Vector2) -> Vector2:
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return Vector2.RIGHT.rotated(snappedf(v.angle(), PI / 4.0))
