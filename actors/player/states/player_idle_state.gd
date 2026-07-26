class_name PlayerIdleState
extends PlayerState
## Standing still.


func physics_update(delta: float) -> void:
	player.apply_motion(delta, Vector2.ZERO)

	if try_common_transitions():
		return

	if player.input.intent.move != Vector2.ZERO:
		state_machine.transition_to(&"Move")
