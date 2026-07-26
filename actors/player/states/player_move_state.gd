class_name PlayerMoveState
extends PlayerState
## Walking. 8-directional, 82 px/s, full speed in 0.08s (GDD §5).


func physics_update(delta: float) -> void:
	var direction := player.input.intent.move
	player.face(direction)
	player.apply_motion(delta, player.desired_walk_velocity())

	if try_common_transitions():
		return

	if direction == Vector2.ZERO and player.motion_velocity.length_squared() < 1.0:
		state_machine.transition_to(&"Idle")
