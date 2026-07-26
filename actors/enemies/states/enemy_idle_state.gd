class_name EnemyIdleState
extends EnemyState
## Standing around until something worth chasing comes into range.


func enter(_msg: Dictionary = {}) -> void:
	enemy.motion_velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	enemy.apply_motion(delta, Vector2.ZERO)
	if enemy.target != null and enemy.distance_to_target() <= data.aggro_range:
		state_machine.transition_to(&"Chase")
