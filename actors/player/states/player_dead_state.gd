class_name PlayerDeadState
extends PlayerState
## Dead. Terminal *within this scene*, which is the whole of it: `Transition`
## hears `Events.player_died` and reloads the last save, so the body that entered
## this state is freed rather than resurrected.
##
## `Player.respawn()` still exists for F5 in the prototype room, and for tests,
## which turn `Transition.auto_retry` off precisely so they can kill the player
## without the scene reloading underneath them.


func enter(_msg: Dictionary = {}) -> void:
	player.motion_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.knockback.clear()
	player.input.enabled = false
	player.input.clear_buffers()
	player.hitbox.deactivate()
	player.hurtbox.disabled = true
	player.flash.hold(Color(0.55, 0.12, 0.16))


func exit() -> void:
	player.input.enabled = true
	player.hurtbox.disabled = false
	player.flash.clear()


func physics_update(delta: float) -> void:
	player.apply_motion(delta, Vector2.ZERO)
