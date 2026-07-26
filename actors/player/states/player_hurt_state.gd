class_name PlayerHurtState
extends PlayerState
## Brief stagger on taking damage.
##
## Short on purpose. A long hitstun turns one mistake into three, and pillar 1
## says every death should be the player's fault — which requires giving them
## the controls back fast enough to argue with.
##
## The 0.8s of i-frames outlast this state; they live on the Hurtbox, granted
## by Player._on_hit_taken, so exiting the stagger early can't cut them short.

var _t: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	_t = 0.0
	player.motion_velocity = Vector2.ZERO
	player.next_combo_index = 0
	player.combo_window_remaining = 0.0
	player.input.clear_buffers()

	var source := msg.get("source") as Node2D
	if source != null and player.hurt_knockback_distance > 0.0:
		var away := player.global_position - source.global_position
		if away.length_squared() > 0.0001:
			player.knockback.apply_distance(away.normalized(), player.hurt_knockback_distance)


func physics_update(delta: float) -> void:
	_t += delta
	player.apply_motion(delta, Vector2.ZERO)
	if _t >= player.hurt_stun_time:
		return_to_locomotion()
