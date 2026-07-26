class_name KnockbackComponent
extends Node
## Decaying impulse velocity, kept separate from the actor's own motion.
##
## The actor adds `velocity` on top of its movement each tick. Keeping the two
## apart means a 1000 px/s² movement acceleration can't instantly cancel a
## knockback the way it would if both shared `CharacterBody2D.velocity`.

## How fast the impulse bleeds off, px/s². Higher = punchier and shorter.
@export var friction: float = 900.0

## Multiplier on incoming knockback. Heavies set this below 1.0.
@export_range(0.0, 2.0, 0.05) var resistance_scale: float = 1.0

var velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


## Knock back by a distance in pixels (GDD §5: 12–20px on the final combo hit).
## Solving `d = v² / 2f` for v keeps the tuning value the thing you can see.
func apply_distance(direction: Vector2, distance_px: float) -> void:
	if distance_px <= 0.0 or direction == Vector2.ZERO:
		return
	var scaled := distance_px * resistance_scale
	if scaled <= 0.0:
		return
	var speed := sqrt(2.0 * friction * scaled)
	velocity = direction.normalized() * speed


## Direct impulse, for cases where the speed matters more than the distance.
func apply_impulse(impulse: Vector2) -> void:
	velocity = impulse * resistance_scale


func clear() -> void:
	velocity = Vector2.ZERO


func is_active() -> bool:
	return velocity.length_squared() > 1.0


## How far the current impulse will still travel, in pixels.
func remaining_distance() -> float:
	return velocity.length_squared() / (2.0 * maxf(friction, 0.0001))
