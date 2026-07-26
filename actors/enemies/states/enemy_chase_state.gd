class_name EnemyChaseState
extends EnemyState
## Walk toward the target until close enough to commit to an attack.
##
## GDD §5 lists the Blighted Villager as "slow walker, lunge" — the walk is
## slow so the lunge reads as a decision rather than a continuation.

## Hysteresis on losing interest, so an enemy at exactly aggro range doesn't
## flicker between Idle and Chase.
@export var give_up_range_scale: float = 1.4


func physics_update(delta: float) -> void:
	if enemy.target == null:
		state_machine.transition_to(&"Idle")
		return

	var distance := enemy.distance_to_target()
	if distance > data.aggro_range * give_up_range_scale:
		state_machine.transition_to(&"Idle")
		return

	var direction := enemy.direction_to_target()
	enemy.face(direction)

	var steer := (direction + enemy.separation()).normalized()
	enemy.apply_motion(delta, steer * data.move_speed)

	if distance <= data.attack_range and enemy.can_attack():
		state_machine.transition_to(&"Telegraph")
