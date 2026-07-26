class_name Hurtbox
extends Area2D
## The receiving half of a hit (GDD §10, pattern 1).
##
## Owns invulnerability, because two unrelated systems grant it — dodge i-frames
## and post-damage i-frames — and they overlap constantly. Tracking them as one
## boolean produces the classic bug where a dodge ending mid-invulnerability
## strips the i-frames the player just earned, so they are tracked separately.

signal hit_taken(hitbox: Hitbox)
signal blocked(hitbox: Hitbox)

## The actor that owns this hurtbox. Set in `_ready()` from the scene root
## unless overridden.
@export var owner_actor: Node

@export var health_path: NodePath = ^"../HealthComponent"
@export var knockback_path: NodePath = ^"../KnockbackComponent"

## Dodge i-frames (GDD §5: 0.04 → 0.24 of a 0.36s roll).
var dodge_invulnerable: bool = false

## Post-damage i-frames (GDD §5: 0.8s).
var damage_invulnerable: bool = false

## Cutscene / death switch.
var disabled: bool = false

var health: HealthComponent
var knockback: KnockbackComponent

var _damage_iframes_remaining: float = 0.0


func _ready() -> void:
	monitoring = false
	monitorable = true
	set_process(false)
	if owner_actor == null:
		owner_actor = owner
	health = get_node_or_null(health_path) as HealthComponent
	knockback = get_node_or_null(knockback_path) as KnockbackComponent
	DebugSettings.changed.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	_damage_iframes_remaining = maxf(_damage_iframes_remaining - delta, 0.0)
	if _damage_iframes_remaining > 0.0:
		return
	damage_invulnerable = false
	set_process(false)
	queue_redraw()


func is_invulnerable() -> bool:
	return disabled or dodge_invulnerable or damage_invulnerable


## Called by a Hitbox. Returns true if the hit connected — the hitbox uses the
## result to decide whether to spend its hitstop and shake, so a whiffed hit on
## an i-framing target correctly produces no impact at all.
func take_hit(hitbox: Hitbox) -> bool:
	if is_invulnerable():
		blocked.emit(hitbox)
		return false
	if health != null and not health.is_alive():
		return false

	if knockback != null and hitbox.knockback_distance > 0.0:
		var direction := _knockback_direction(hitbox)
		knockback.apply_distance(direction, hitbox.knockback_distance)

	if health != null:
		health.take_damage(hitbox.damage, hitbox.source)

	hit_taken.emit(hitbox)
	return true


## Away from the attacker. Falls back to the hitbox's own facing when the two
## are exactly co-located, which happens more often than you'd think.
func _knockback_direction(hitbox: Hitbox) -> Vector2:
	var from: Node2D = hitbox.source as Node2D
	if from == null:
		from = hitbox
	var self_position := (owner_actor as Node2D).global_position if owner_actor is Node2D else global_position
	var direction := self_position - from.global_position
	if direction.length_squared() < 0.0001:
		return Vector2.RIGHT.rotated(hitbox.global_rotation)
	return direction.normalized()


## Grant post-damage i-frames (GDD §5: 0.8s on the player).
func start_damage_iframes(duration: float) -> void:
	if duration <= 0.0:
		return
	_damage_iframes_remaining = maxf(_damage_iframes_remaining, duration)
	damage_invulnerable = true
	set_process(true)
	queue_redraw()


func clear_iframes() -> void:
	_damage_iframes_remaining = 0.0
	damage_invulnerable = false
	dodge_invulnerable = false
	set_process(false)
	queue_redraw()


func iframes_remaining() -> float:
	return _damage_iframes_remaining


func _draw() -> void:
	if not DebugSettings.show_boxes:
		return
	var color := Color(0.4, 0.6, 1.0, 0.7)
	if is_invulnerable():
		color = Color(1.0, 0.9, 0.3, 0.9)
	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var rect := shape_node.shape as RectangleShape2D
		if rect != null:
			draw_rect(Rect2(shape_node.position - rect.size * 0.5, rect.size), color, false, 1.0)
			continue
		var circle := shape_node.shape as CircleShape2D
		if circle != null:
			draw_arc(shape_node.position, circle.radius, 0.0, TAU, 24, color, 1.0)
