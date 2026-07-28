class_name PlayerMoveState
extends PlayerState
## Walking, and sprinting. 8-directional, 328 px/s, full speed in 0.08s (GDD §5).
##
## Sprinting is not a state. Nothing about the character changes — no i-frames,
## no commitment, no animation the player has to wait out — so a state would buy
## transitions nobody needs. It is a speed multiplier the move state applies
## while the dash key is held and the pool has fuel.


func physics_update(delta: float) -> void:
	var direction := player.input.intent.move
	player.face(direction)
	var scale: float = player.sprint_speed_scale if player.update_sprint(delta) else 1.0
	player.apply_motion(delta, player.desired_walk_velocity(scale))

	if try_common_transitions():
		return

	if direction == Vector2.ZERO and player.motion_velocity.length_squared() < 1.0:
		state_machine.transition_to(&"Idle")
