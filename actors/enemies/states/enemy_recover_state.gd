class_name EnemyRecoverState
extends EnemyState
## The player's turn.
##
## Every enemy in the GDD is killable in ≤5 hits at matched gear, which only
## works if there is a reliable window to spend those hits in. This is it —
## long, obvious, and vulnerable.

## Deceleration out of the lunge. Slower than normal so the attack has weight.
@export var slide_deceleration: float = 1040.0

var _t: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	enemy.motion_velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	_t += delta
	# Slide to a stop rather than stopping dead, so the lunge has weight.
	enemy.apply_motion(delta, Vector2.ZERO, slide_deceleration)
	if _t >= data.recover_time:
		state_machine.transition_to(&"Chase")
