class_name PlayerDodgeState
extends PlayerState
## Directional roll with i-frames (GDD §5).
##
## Duration 0.36s · i-frames 0.04 → 0.24 · distance 46px · 0.12s cooldown after
## recovery · costs 1 of 4 stamina. Attacks stay free; only this costs
## (GDD §6, decided).

@export_group("Frame data")
@export var duration: float = 0.36
@export var iframe_start: float = 0.04
@export var iframe_end: float = 0.24
@export var distance: float = 46.0
## GDD §5: 0.12s cooldown after recovery.
@export var cooldown: float = 0.12
@export var stamina_cost: float = 1.0

## Shape of the speed curve: v(u) ∝ (1 − u)^exponent. 0 would be a flat
## constant-speed slide; 2 pops out of the roll and settles, which reads as a
## roll instead of a shove.
@export var speed_exponent: float = 2.0

var _t: float = 0.0
var _direction: Vector2 = Vector2.DOWN
var _travelled: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_t = 0.0
	# Roll where you're steering, or where you're facing if you're standing.
	_direction = player.input.intent.move
	if _direction == Vector2.ZERO:
		_direction = player.facing
	_direction = _direction.normalized()
	player.face(_direction)

	player.stamina.spend(stamina_cost)
	# Rolling out of an attack ends the chain; the next press starts at hit 1.
	player.next_combo_index = 0
	player.combo_window_remaining = 0.0
	_travelled = 0.0

	Sfx.play(&"dodge")


func exit() -> void:
	player.hurtbox.dodge_invulnerable = false
	player.dodge_cooldown_remaining = cooldown


func physics_update(delta: float) -> void:
	_t += delta

	player.hurtbox.dodge_invulnerable = _t >= iframe_start and _t < iframe_end

	# Drive position, not speed. Sampling a decaying speed curve at 60Hz
	# under-integrates it — the roll came out 7% short of its exported distance,
	# and would come out short by a different amount at a different tick rate.
	# Stepping along the antiderivative makes `distance` mean what it says.
	var u := clampf(_t / maxf(duration, 0.0001), 0.0, 1.0)
	var target_travelled := _distance_at(u)
	var step := target_travelled - _travelled
	_travelled = target_travelled
	player.set_motion(_direction * (step / maxf(delta, 0.0001)))

	if _t < duration:
		return

	# Rolling straight into an attack should feel like one motion.
	if player.input.consume_attack():
		state_machine.transition_to(&"Attack", {"combo_index": 0})
		return
	return_to_locomotion()


## Distance covered by normalised time `u`. ∫₀^u (1−x)^n dx, normalised so that
## `_distance_at(1.0) == distance` exactly.
func _distance_at(u: float) -> float:
	return distance * (1.0 - pow(1.0 - u, speed_exponent + 1.0))


## For the debug overlay.
func iframes_active() -> bool:
	return player.hurtbox.dodge_invulnerable
