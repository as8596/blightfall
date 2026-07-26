class_name EnemyTelegraphState
extends EnemyState
## The wind-up. GDD §5, enemy rule 1: minimum 0.4s, distinct colour and pose.
##
## The colour and the scale-up are both here because either alone is easy to
## miss — colour is invisible to some players, silhouette change is invisible
## against a busy background, and M1 has neither art nor a busy background to
## check against. Both, always.

## Fraction of the wind-up during which the enemy can still turn to track. The
## last stretch is committed, so sidestepping late beats sidestepping early.
@export_range(0.0, 1.0, 0.05) var tracking_fraction: float = 0.5

## How hard it tracks while it still can, in radians per second.
@export var turn_rate: float = 3.0

var _t: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	enemy.motion_velocity = Vector2.ZERO
	enemy.visual.color = data.telegraph_color
	enemy.visual.scale = Vector2.ONE * data.telegraph_scale
	if data.telegraph_sfx != &"":
		Sfx.play(data.telegraph_sfx)


func exit() -> void:
	enemy.visual.color = data.base_color
	enemy.visual.scale = Vector2.ONE


func physics_update(delta: float) -> void:
	_t += delta

	if _t <= data.telegraph_time * tracking_fraction:
		var wanted := enemy.direction_to_target()
		if wanted != Vector2.ZERO:
			var angle := enemy.facing.angle()
			enemy.face(Vector2.RIGHT.rotated(
				rotate_toward(angle, wanted.angle(), turn_rate * delta)
			))

	enemy.apply_motion(delta, Vector2.ZERO)

	if _t >= data.telegraph_time:
		state_machine.transition_to(&"Lunge")


## Progress 0→1, for the debug overlay.
func progress() -> float:
	return clampf(_t / maxf(data.telegraph_time, 0.0001), 0.0, 1.0)
