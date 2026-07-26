class_name BaseEnemy
extends CharacterBody2D
## Shared enemy actor: CharacterBody2D + sprite + components + a state machine
## (GDD §10, pattern 1). Everything that varies between enemies lives in an
## EnemyData `.tres`, so enemy #7 is an afternoon rather than a week.
##
## Behaviour is the Blighted Villager's loop — approach, telegraph, lunge,
## recover — because that is the only enemy M1 contains. Enemies with genuinely
## different logic will swap the state set, not this script.

@export var data: EnemyData

## How far past the edge of the screen still counts as on-screen, in pixels.
## A little slack: an enemy exactly on the boundary shouldn't flicker between
## "allowed to attack" and "not".
@export var offscreen_margin: float = 48.0

@onready var health: HealthComponent = $HealthComponent
@onready var knockback: KnockbackComponent = $KnockbackComponent
@onready var flash: FlashComponent = $FlashComponent
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visual: ColorRect = $Visual
@onready var state_machine: StateMachine = $StateMachine
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

var facing: Vector2 = Vector2.DOWN
var motion_velocity: Vector2 = Vector2.ZERO
var attack_cooldown_remaining: float = 0.0

## Cached each tick from the targeting helper. Enemy code never looks the
## player up itself (GDD §12, rule 2).
var target: Node2D


func _ready() -> void:
	add_to_group(Targeting.ENEMY_GROUP)
	if data == null:
		push_error("%s has no EnemyData." % name)
		return
	_apply_data()
	hitbox.source = self
	hurtbox.owner_actor = self
	hurtbox.hit_taken.connect(_on_hit_taken)
	health.died.connect(_on_died)
	state_machine.start()


func _process(delta: float) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)


func _physics_process(_delta: float) -> void:
	target = Targeting.nearest_target(self)


## Push every tunable number out of the scene and into the resource.
func _apply_data() -> void:
	health.max_health = data.max_health
	health.reset()
	knockback.resistance_scale = data.knockback_resistance

	visual.color = data.base_color
	visual.offset_left = -data.body_size.x * 0.5
	visual.offset_right = data.body_size.x * 0.5
	visual.offset_top = -data.body_size.y
	visual.offset_bottom = 0.0
	# Scale the telegraph "pose" about the feet, not the top-left corner.
	visual.pivot_offset = Vector2(data.body_size.x * 0.5, data.body_size.y)

	# Derived from body_size rather than hard-coded, so changing the sprite
	# resolution moves the collider with it instead of silently leaving a
	# 16px-era footprint under a 64px character.
	var body_rect := body_shape.shape as RectangleShape2D
	if body_rect != null:
		body_rect = body_rect.duplicate()
		body_rect.size = Vector2(data.body_size.x * 0.75, data.body_size.y * 0.5)
		body_shape.shape = body_rect
		body_shape.position = Vector2(0, -data.body_size.y * 0.25)

	hitbox.damage = data.contact_damage
	hitbox.position = Vector2(0, -data.body_size.y * 0.5)
	var hit_rect := hitbox_shape.shape as RectangleShape2D
	if hit_rect != null:
		hit_rect = hit_rect.duplicate()
		hit_rect.size = data.hitbox_size
		hitbox_shape.shape = hit_rect
	hitbox_shape.position = Vector2(data.hitbox_offset, 0)


func apply_motion(delta: float, desired: Vector2, accel: float = 1600.0) -> void:
	motion_velocity = motion_velocity.move_toward(desired, accel * delta)
	velocity = motion_velocity + knockback.velocity
	move_and_slide()


func set_motion(desired: Vector2) -> void:
	motion_velocity = desired
	velocity = motion_velocity + knockback.velocity
	move_and_slide()


func face(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		facing = direction.normalized()


func direction_to_target() -> Vector2:
	if target == null:
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length_squared() < 0.0001:
		return Vector2.ZERO
	return to_target.normalized()


func distance_to_target() -> float:
	if target == null:
		return INF
	return global_position.distance_to(target.global_position)


## Steer away from nearby enemies so a pack of three reads as three bodies
## instead of one stack. Cheap by design — this is not flocking.
func separation() -> Vector2:
	if data.separation_strength <= 0.0:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for other in Targeting.neighbours(self, Targeting.ENEMY_GROUP, data.separation_radius):
		var away := global_position - other.global_position
		if away.length_squared() < 0.0001:
			# Exactly co-located; nudge deterministically via the shared RNG.
			push += Rng.direction()
			continue
		push += away.normalized() * (1.0 - away.length() / data.separation_radius)
	return push * data.separation_strength


## GDD §5, enemy rule 4: no enemy attacks off-screen.
##
## Computed from the canvas transform rather than read off a
## VisibleOnScreenNotifier2D. The notifier depends on the renderer having drawn
## a frame, so it reports false in headless runs and for a frame or two after a
## spawn — and the failure mode of this particular check is an enemy that walks
## up to you and then politely does nothing, which is very hard to spot and
## very easy to misread as broken AI.
func is_on_screen() -> bool:
	if not is_inside_tree():
		return false
	return get_viewport_rect().grow(offscreen_margin).has_point(
		get_global_transform_with_canvas().origin
	)


func can_attack() -> bool:
	return attack_cooldown_remaining <= 0.0 and is_on_screen()


func start_attack_cooldown() -> void:
	attack_cooldown_remaining = data.attack_cooldown


func is_targetable() -> bool:
	return health.is_alive()


func _on_hit_taken(_hitbox: Hitbox) -> void:
	if not health.is_alive():
		return
	flash.flash()
	var current := state_machine.current_state as EnemyState
	if current != null and current.can_be_staggered():
		state_machine.transition_to(&"Hurt")


func _on_died() -> void:
	Events.enemy_died.emit(self)
	state_machine.transition_to(&"Dead")
