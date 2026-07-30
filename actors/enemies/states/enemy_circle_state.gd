class_name EnemyCircleState
extends EnemyState
## Keep your distance and move around them, waiting for an opening.
##
## **This is what makes a pack a pack.** Before it, three wolves ran the same
## straight line at the player and arrived in single file — the second and third
## did nothing but queue, because separation pushed them apart and chase pulled
## them straight back in. A fight against three was a fight against one, three
## times.
##
## Circling gives the other two somewhere to be that is not behind the first
## one. It also delivers the roster line: GDD §7 describes the Rot Hound as
## "fast, circles before lunging, packs of 3", and the forest wolf shares its
## shape.
##
## **Entered after an attack, not before one.** An enemy that circles on first
## sight reads as cowardly and wastes the approach; one that lunges, misses, and
## then backs off to come around again reads as an animal that has learned
## something. So `Recover` sends its enemies here rather than back to `Chase`.
##
## The player's window is preserved: circling holds the enemy at a distance
## greater than its attack range, so the seconds after a miss are still seconds
## in which nothing can reach you.

## Which way round, and how long before committing again. Seconds, picked per
## entry so two wolves in the same pack do not orbit in lockstep.
var _clockwise: bool = true
var _remaining: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	# Through `Rng`, like every other decision in the game (GDD §12 rule 5).
	_clockwise = Rng.randf() < 0.5
	_remaining = Rng.randf_range(data.circle_time_min, data.circle_time_max)


func physics_update(delta: float) -> void:
	if enemy.target == null:
		state_machine.transition_to(&"Idle")
		return

	var distance := enemy.distance_to_target()
	if distance > data.aggro_range * 1.4:
		state_machine.transition_to(&"Idle")
		return

	_remaining -= delta
	if _remaining <= 0.0 and enemy.can_attack():
		state_machine.transition_to(&"Chase")
		return

	# Two pulls, summed: sideways around the target, and in or out until the
	# radius is right. Doing it as a sum rather than as a strict orbit means an
	# enemy shoved by knockback drifts back to the ring instead of snapping.
	var inward := enemy.direction_to_target()
	var around := Vector2(-inward.y, inward.x) * (1.0 if _clockwise else -1.0)
	var wanted := data.attack_range * data.circle_radius_scale
	var correction := signf(distance - wanted)
	var steer := (around + inward * correction * 0.8 + enemy.separation()).normalized()

	enemy.face(inward)
	enemy.apply_motion(delta, steer * data.move_speed * data.circle_speed_scale)
