class_name EnemyHurtState
extends EnemyState
## Stagger. Short — the knockback carries the impact, not the stun length.
##
## Hitstop and the white flash have already fired by the time this runs; they
## are what makes the hit feel like it landed. The stagger only has to stop the
## enemy walking through its own hit reaction.

var _t: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	enemy.motion_velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	_t += delta
	enemy.apply_motion(delta, Vector2.ZERO)
	if _t >= data.stagger_time:
		state_machine.transition_to(&"Chase")
