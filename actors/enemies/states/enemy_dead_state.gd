class_name EnemyDeadState
extends EnemyState
## Death. Terminal — flash white, coast to a stop, fade, free.
##
## Killing one enemy should feel satisfying enough that you do it again without
## being asked (BUILD-PLAN, week 3 gate). Most of that is the hit that killed
## it, but the body has to acknowledge the kill too.

## Deceleration of the corpse as it comes to rest.
@export var slide_deceleration: float = 800.0

var _t: float = 0.0


func can_be_staggered() -> bool:
	return false


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	enemy.hitbox.deactivate()
	enemy.hurtbox.disabled = true
	# Stop colliding with the world so the corpse can't block a doorway.
	enemy.set_collision_layer_value(5, false)
	enemy.set_collision_mask_value(1, false)
	enemy.remove_from_group(Targeting.ENEMY_GROUP)
	enemy.flash.hold()
	Sfx.play(&"enemy_death")


func physics_update(delta: float) -> void:
	_t += delta
	enemy.apply_motion(delta, Vector2.ZERO, slide_deceleration)
	var u := clampf(_t / maxf(data.death_time, 0.0001), 0.0, 1.0)
	enemy.visual.modulate.a = 1.0 - u
	if _t >= data.death_time:
		enemy.queue_free()
