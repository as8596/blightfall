class_name Player
extends CharacterBody2D
## The player actor. Movement values from GDD §5.
##
## Deliberately not a singleton and not reachable through one (GDD §12, rule 1):
## nothing looks the player up globally, and everything that needs one is handed
## a reference or finds it through Targeting. That is the difference between
## "add a second player" being a week and being a rewrite.

@export_group("Movement")
## GDD §5: 82 px/s at 320×180.
@export var move_speed: float = 82.0
## GDD §5: full speed in 0.08s.
@export var time_to_max_speed: float = 0.08
## Not specified; slightly snappier than acceleration so stops read as crisp.
@export var time_to_stop: float = 0.06

@export_group("Combat")
## GDD §5: 0.8s i-frames on damage.
@export var damage_invuln_time: float = 0.8
## Control loss on being hit. Short — this game blames the player, not the game.
@export var hurt_stun_time: float = 0.18
@export var hurt_knockback_distance: float = 22.0
@export var combo: PlayerComboData

@export_group("References")
@export var combo_hitbox_shape_path: NodePath = ^"Hitbox/CollisionShape2D"

@onready var input: InputComponent = $InputComponent
@onready var health: HealthComponent = $HealthComponent
@onready var stamina: StaminaComponent = $StaminaComponent
@onready var knockback: KnockbackComponent = $KnockbackComponent
@onready var flash: FlashComponent = $FlashComponent
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var state_machine: StateMachine = $StateMachine
@onready var visual: ColorRect = $Visual

## Last committed facing. Drives hitbox placement and the default dodge
## direction. Starts down because that is where a character faces at rest.
var facing: Vector2 = Vector2.DOWN

## The actor's own motion, kept apart from knockback (see KnockbackComponent).
var motion_velocity: Vector2 = Vector2.ZERO

## Dodge lockout (GDD §5: 0.12s cooldown after recovery).
var dodge_cooldown_remaining: float = 0.0

## Combo continuation, tracked here rather than in the Attack state because the
## window outlives the state it belongs to (see PlayerComboData).
var next_combo_index: int = 0
var combo_window_remaining: float = 0.0

var _hitbox_shape: CollisionShape2D
var _spawn_position: Vector2


func _ready() -> void:
	add_to_group(Targeting.TARGET_GROUP)
	_spawn_position = global_position

	_hitbox_shape = get_node_or_null(combo_hitbox_shape_path) as CollisionShape2D
	if _hitbox_shape != null and _hitbox_shape.shape != null:
		# Unique per instance, so resizing the swing on one player can't resize
		# it on another.
		_hitbox_shape.shape = _hitbox_shape.shape.duplicate()

	hitbox.source = self
	hurtbox.owner_actor = self

	health.died.connect(_on_died)
	health.changed.connect(func(current: int, maximum: int) -> void:
		Events.player_health_changed.emit(current, maximum))
	stamina.changed.connect(func(current: float, maximum: float) -> void:
		Events.player_stamina_changed.emit(current, maximum))
	hurtbox.hit_taken.connect(_on_hit_taken)

	state_machine.start()


func _process(delta: float) -> void:
	dodge_cooldown_remaining = maxf(dodge_cooldown_remaining - delta, 0.0)
	if combo_window_remaining > 0.0:
		combo_window_remaining = maxf(combo_window_remaining - delta, 0.0)
		if combo_window_remaining == 0.0:
			next_combo_index = 0


## Accelerate toward `desired` and move. Knockback rides on top rather than
## being blended in, so a hit still moves you during a full-speed run.
func apply_motion(delta: float, desired: Vector2) -> void:
	var rate := move_speed / maxf(time_to_max_speed, 0.0001)
	if desired == Vector2.ZERO:
		rate = move_speed / maxf(time_to_stop, 0.0001)
	motion_velocity = motion_velocity.move_toward(desired, rate * delta)
	_move()


## Bypass acceleration. The dodge drives its own speed curve.
func set_motion(desired: Vector2) -> void:
	motion_velocity = desired
	_move()


func _move() -> void:
	velocity = motion_velocity + knockback.velocity
	move_and_slide()


## Walk velocity for the current input, scaled (attacks move at 25% / 0%).
func desired_walk_velocity(speed_scale: float = 1.0) -> Vector2:
	return input.intent.move * move_speed * speed_scale


func face(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		facing = direction.normalized()


## Point the combo hitbox along `facing` and load one hit's numbers into it.
func configure_hitbox(step: ComboStepData) -> void:
	hitbox.rotation = facing.angle()
	hitbox.damage = step.damage
	hitbox.knockback_distance = step.knockback_distance
	hitbox.hitstop = step.hitstop
	hitbox.screen_shake = step.screen_shake
	hitbox.impact_sfx = step.impact_sfx
	if _hitbox_shape != null:
		var rect := _hitbox_shape.shape as RectangleShape2D
		if rect != null:
			rect.size = step.hitbox_size
		_hitbox_shape.position = Vector2(step.hitbox_offset, 0.0)


func can_dodge() -> bool:
	return dodge_cooldown_remaining <= 0.0 and stamina.can_spend(1.0)


func is_alive() -> bool:
	return health.is_alive()


## Consulted by Targeting — a dying player stops being a valid target so
## enemies don't keep lunging at a corpse.
func is_targetable() -> bool:
	return health.is_alive()


func _on_hit_taken(hitbox_hit: Hitbox) -> void:
	if not health.is_alive():
		return
	hurtbox.start_damage_iframes(damage_invuln_time)
	flash.flash()
	Sfx.play(&"player_hurt")
	Events.screen_shake_requested.emit(2.0, 0.2)
	HitStop.freeze(0.08)
	if state_machine.has_state(&"Hurt"):
		state_machine.transition_to(&"Hurt", {"source": hitbox_hit.source})


func _on_died() -> void:
	Events.player_died.emit(self)
	state_machine.transition_to(&"Dead")


## Debug respawn (F5 in the prototype room). No save system in M1.
func respawn() -> void:
	global_position = _spawn_position
	motion_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	knockback.clear()
	health.reset()
	stamina.refill()
	hurtbox.clear_iframes()
	hurtbox.disabled = false
	flash.clear()
	input.enabled = true
	input.clear_buffers()
	next_combo_index = 0
	combo_window_remaining = 0.0
	dodge_cooldown_remaining = 0.0
	state_machine.transition_to(&"Idle")
