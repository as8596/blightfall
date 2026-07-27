class_name Player
extends CharacterBody2D
## The player actor. Movement values from GDD §5.
##
## Deliberately not a singleton and not reachable through one (GDD §12, rule 1):
## nothing looks the player up globally, and everything that needs one is handed
## a reference or finds it through Targeting. That is the difference between
## "add a second player" being a week and being a rewrite.

@export_group("Movement")
## 328 px/s at 1280×720 — the GDD's 82 px/s at 320×180, scaled with the
## resolution so the character still crosses the screen in the same time.
@export var move_speed: float = 328.0
## GDD §5: full speed in 0.08s.
@export var time_to_max_speed: float = 0.08
## Not specified; slightly snappier than acceleration so stops read as crisp.
@export var time_to_stop: float = 0.06

@export_group("Combat")
## GDD §5: 0.8s i-frames on damage.
@export var damage_invuln_time: float = 0.8
## Control loss on being hit. Short — this game blames the player, not the game.
@export var hurt_stun_time: float = 0.18
@export var hurt_knockback_distance: float = 88.0
@export var combo: PlayerComboData

@export_group("Haul")
## Dropped where the player falls, carrying whatever they were holding.
@export var haul_cache_scene: PackedScene

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
@onready var visual: Sprite2D = $Visual
@onready var animation: AnimationComponent = $AnimationComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var interactor: InteractorComponent = $Interactor

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
	add_to_group(SaveGame.GROUP)
	_spawn_position = global_position

	_hitbox_shape = get_node_or_null(combo_hitbox_shape_path) as CollisionShape2D
	if _hitbox_shape != null and _hitbox_shape.shape != null:
		# Unique per instance, so resizing the swing on one player can't resize
		# it on another.
		_hitbox_shape.shape = _hitbox_shape.shape.duplicate()

	hitbox.source = self
	hurtbox.owner_actor = self

	animation.bind(state_machine)
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

	_try_interact()


## Interacting is handled here rather than in a state, because it is not a state
## the player enters — nothing about the character changes, the world just
## responds. Gated to standing and walking: mid-swing and mid-roll you have
## already committed to something else, and a door that opens out of a dodge
## would make dodging near a building unusable.
func _try_interact() -> void:
	if not (state_machine.is_in(&"Idle") or state_machine.is_in(&"Move")):
		return
	if not input.consume_interact():
		return
	if not interactor.try_interact():
		# Nothing in range. The press is spent either way — holding a stale
		# interact that fires the moment you walk up to a door is worse than
		# dropping it.
		pass


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
	Events.screen_shake_requested.emit(8.0, 0.2)
	HitStop.freeze(0.08)
	if state_machine.has_state(&"Hurt"):
		state_machine.transition_to(&"Hurt", {"source": hitbox_hit.source})


func _on_died() -> void:
	_drop_haul()
	Events.player_died.emit(self)
	state_machine.transition_to(&"Dead")


## Leave the haul where the player fell (GDD §15 A4). Nothing is destroyed —
## it waits, and it is the reason turning back early is ever the right call.
func _drop_haul() -> void:
	if inventory.total() <= 0 or haul_cache_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	HaulCache.drop(get_tree(), haul_cache_scene, parent, global_position, inventory.take_all())


# ------------------------------------------------------------------ saving
#
# Three methods and a group membership — see systems/save/save_game.gd. Adding
# tools, heart shards or whetstones later means extending `save_data` and
# `load_data`, and touching nothing else.

func save_id() -> StringName:
	return &"player"


func save_data() -> Dictionary:
	return {
		"position": SaveGame.write_vector2(global_position),
		"facing": SaveGame.write_vector2(facing),
		"health": health.current,
		"max_health": health.max_health,
		"max_stamina": stamina.max_stamina,
		"inventory": inventory.save_data(),
	}


func load_data(data: Dictionary) -> void:
	global_position = SaveGame.read_vector2(data, "position", global_position)
	facing = SaveGame.read_vector2(data, "facing", facing)

	# Order matters: raise the ceiling before restoring current, or a save with
	# more heart containers than the default clamps down to the default.
	health.set_max_health(SaveGame.read_int(data, "max_health", health.max_health), false)
	health.current = clampi(SaveGame.read_int(data, "health", health.current), 0, health.max_health)
	health.changed.emit(health.current, health.max_health)

	stamina.max_stamina = SaveGame.read_float(data, "max_stamina", stamina.max_stamina)
	stamina.refill()

	var carried: Variant = data.get("inventory")
	if carried is Dictionary:
		inventory.load_data(carried)

	# Whatever the player was doing when they saved, they are standing still now.
	motion_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	knockback.clear()
	hurtbox.clear_iframes()
	input.clear_buffers()
	next_combo_index = 0
	combo_window_remaining = 0.0
	dodge_cooldown_remaining = 0.0
	if health.is_alive():
		hurtbox.disabled = false
		input.enabled = true
		flash.clear()
		state_machine.transition_to(&"Idle")
	else:
		state_machine.transition_to(&"Dead")


## Debug respawn (F5 in the prototype room).
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
