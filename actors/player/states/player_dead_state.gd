class_name PlayerDeadState
extends PlayerState
## Dead. Terminal until something calls `Player.respawn()`.
##
## No death screen, no retry flow, no save — M1 has none of that (BUILD-PLAN).
## F5 in the prototype room puts you back on your feet.


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
