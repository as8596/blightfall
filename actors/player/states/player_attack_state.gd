class_name PlayerAttackState
extends PlayerState
## The three-hit light combo (GDD §5).
##
## Timeline per hit, `t` measured from the hit's own start:
##
##   0 ─────── windup ─────── active ─────── recovery ─────── end
##             hitbox on ─────┘      hitbox off
##             ▲ cancel_into_next_at        ▲ dodge-cancel opens here
##
## Attacks chain from `cancel_into_next_at`; they dodge-cancel during recovery
## only, which is the main skill expression in the game (GDD §5). The combo
## window itself outlives this state — see Player.combo_window_remaining.

## Let the player re-aim while winding up. Commitment starts at the active
## frames; before that, turning is responsiveness, not a get-out.
@export var allow_turn_during_windup: bool = true

var _index: int = 0
var _step: ComboStepData
var _t: float = 0.0
var _hitbox_on: bool = false
var _chain_queued: bool = false


func enter(msg: Dictionary = {}) -> void:
	_index = msg.get("combo_index", 0)
	_start_step()


func exit() -> void:
	_stop_hitbox()
	if player.weapon_arc != null:
		player.weapon_arc.stop()


func physics_update(delta: float) -> void:
	if _step == null:
		return_to_locomotion()
		return

	_t += delta

	var active_start := _step.windup
	var active_end := _step.recovery_start()
	var step_end := _step.duration()

	# Re-aims at the cursor during windup only. Turning during the wind-up is
	# responsiveness; turning after it is a get-out from a commitment the game
	# just asked you to make.
	if allow_turn_during_windup and _t < active_start:
		player.face_aim()
		player.hitbox.rotation = player.facing.angle()

	if _t >= active_start and _t < active_end and not _hitbox_on:
		_start_hitbox()
	elif _t >= active_end and _hitbox_on:
		_stop_hitbox()

	# The sprite is driven off the same boundaries as the hitbox, never off a
	# frame rate. If the swing had its own clock it would finish before its own
	# active frames did, and the picture would start disagreeing with the hitbox
	# about when the player is about to be hit.
	var phase := 0
	if _t >= active_end:
		phase = 2
	elif _t >= active_start:
		phase = 1
	player.animation.set_manual_frame(phase)

	player.apply_motion(delta, player.desired_walk_velocity(_step.move_speed_scale))

	# Dodge-cancel: recovery only.
	if _t >= active_end and player.can_dodge() and player.input.consume_dodge():
		state_machine.transition_to(&"Dodge")
		return

	# Chain: from cancel_into_next_at onward, on a buffered press.
	if _can_chain_now() and (_chain_queued or player.input.consume_attack()):
		_index += 1
		_start_step()
		return
	if _has_next() and player.input.consume_attack():
		# Pressed too early to chain — hold it rather than dropping it.
		_chain_queued = true

	if _t >= step_end:
		_finish()


func _can_chain_now() -> bool:
	if not _has_next() or not _step.can_chain():
		return false
	return _t >= _step.cancel_into_next_at


func _has_next() -> bool:
	return player.combo != null and _index + 1 < player.combo.length()


func _start_step() -> void:
	_step = player.combo.step(_index) if player.combo != null else null
	if _step == null:
		return_to_locomotion()
		return
	_t = 0.0
	_chain_queued = false
	_stop_hitbox()
	# The swing goes where you pointed, not where you were walking.
	player.face_aim()
	player.configure_hitbox(_step)
	player.animation.play_attack(_index)

	# Alternate the sweep per hit, so a three-hit string reads as three motions
	# rather than the same one three times. The blade covers windup and active
	# together: by the time the hitbox is live the eye needs the streak already
	# moving, or a 0.10s window has nothing to read.
	if player.weapon_arc != null:
		player.weapon_arc.swing(
			player.facing.angle(),
			_step.windup + _step.active,
			_index % 2 == 0,
			1.0 + float(player.stats.bonus(StatsComponent.REACH)) / 100.0
		)
	if _step.swing_sfx != &"":
		Sfx.play(_step.swing_sfx)


func _start_hitbox() -> void:
	_hitbox_on = true
	player.hitbox.rotation = player.facing.angle()
	player.hitbox.activate()


func _stop_hitbox() -> void:
	if not _hitbox_on:
		return
	_hitbox_on = false
	player.hitbox.deactivate()


## Hand the combo's remaining window to the player, then step out. If the
## window is still open when the player presses attack again — even from Idle
## or Move — the chain continues where it left off.
func _finish() -> void:
	var window_left: float = 0.0
	if _has_next():
		window_left = player.combo.combo_window_after_recovery - _step.recovery
	if window_left > 0.0:
		player.next_combo_index = _index + 1
		player.combo_window_remaining = window_left
	else:
		# Recovery outlasted the window, or there is no next hit. Either way
		# the chain is over — reset so the next press starts at hit 1.
		player.next_combo_index = 0
		player.combo_window_remaining = 0.0
	return_to_locomotion()


## For the debug overlay.
func combo_index() -> int:
	return _index


func step_time() -> float:
	return _t
