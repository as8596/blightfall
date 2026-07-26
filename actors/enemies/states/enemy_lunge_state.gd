class_name EnemyLungeState
extends EnemyState
## The committed attack. Direction is locked at entry — this is the window the
## player is meant to dodge, and it can only be a real dodge if the enemy
## can't re-aim mid-lunge.

var _t: float = 0.0
var _direction: Vector2 = Vector2.RIGHT


## The one state a hit does not interrupt (see EnemyState).
func can_be_staggered() -> bool:
	return false


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	_direction = enemy.facing
	enemy.start_attack_cooldown()
	enemy.hitbox.rotation = _direction.angle()
	enemy.hitbox.activate()


func exit() -> void:
	enemy.hitbox.deactivate()


func physics_update(delta: float) -> void:
	_t += delta
	# Linear dash: the villager throws its weight forward and does not steer.
	enemy.set_motion(_direction * data.lunge_speed())
	if _t >= data.lunge_time:
		state_machine.transition_to(&"Recover")
