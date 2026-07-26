class_name Hitbox
extends Area2D
## The dealing half of a hit (GDD §10, pattern 1).
##
## Off by default; a state turns it on for exactly the active frames and off
## again. It carries the whole feel payload for the hit it represents —
## damage, knockback distance, hitstop and shake — so tuning one swing means
## editing one place.

signal hit_landed(hurtbox: Hurtbox)

@export_group("Damage")
@export var damage: int = 1
## Pixels of knockback. GDD §5: 12–20px on the final combo hit.
@export var knockback_distance: float = 0.0

@export_group("Feel")
## GDD §5: 0.05s on hits 1–2, 0.10s on hit 3.
@export var hitstop: float = 0.0
@export_range(0.0, 1.0, 0.01) var hitstop_time_scale: float = 0.0
## GDD §5: 2px, heavy hits only.
@export var screen_shake: float = 0.0
@export var screen_shake_time: float = 0.16

@export_group("Rules")
## One hit per target per activation, so a 0.10s active window can't tick twice.
@export var one_hit_per_target: bool = true
## Impact SFX layer. The swing layer is played by the attacking state.
@export var impact_sfx: StringName = &"impact_light"

## The actor this hitbox belongs to. Set by the owning actor in `_ready()`;
## passed along to whatever gets hit so damage has an attributable source.
var source: Node

var _active: bool = false
var _hit_targets: Array[int] = []
var _sweep_pending: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = false
	set_physics_process(false)
	area_entered.connect(_on_area_entered)
	DebugSettings.changed.connect(queue_redraw)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# One sweep on the tick after activation, catching hurtboxes that were
	# already overlapping when the box switched on.
	if not _sweep_pending:
		set_physics_process(false)
		return
	_sweep_pending = false
	set_physics_process(false)
	for area in get_overlapping_areas():
		_on_area_entered(area)


## Turn on for the active frames of an attack.
func activate() -> void:
	_hit_targets.clear()
	_active = true
	monitoring = true
	_sweep_pending = true
	set_physics_process(true)
	queue_redraw()


func deactivate() -> void:
	_active = false
	monitoring = false
	_sweep_pending = false
	set_physics_process(false)
	queue_redraw()


func is_active() -> bool:
	return _active


func _on_area_entered(area: Area2D) -> void:
	if not _active:
		return
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	if hurtbox.owner_actor != null and hurtbox.owner_actor == source:
		return
	var id := hurtbox.get_instance_id()
	if one_hit_per_target and _hit_targets.has(id):
		return
	if not hurtbox.take_hit(self):
		return
	_hit_targets.append(id)
	hit_landed.emit(hurtbox)
	Events.hit_landed.emit(source, hurtbox.owner_actor, damage)
	_apply_feel()


## Hitstop, shake and the impact SFX layer. Every hit gets a swing sound *and*
## an impact sound (GDD §5).
func _apply_feel() -> void:
	if hitstop > 0.0:
		HitStop.freeze(hitstop, hitstop_time_scale)
	if screen_shake > 0.0:
		Events.screen_shake_requested.emit(screen_shake, screen_shake_time)
	if impact_sfx != &"":
		Sfx.play(impact_sfx)


func _draw() -> void:
	if not DebugSettings.show_boxes:
		return
	var color := Color(1.0, 0.25, 0.25, 0.85 if _active else 0.25)
	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var rect := shape_node.shape as RectangleShape2D
		if rect != null:
			var r := Rect2(shape_node.position - rect.size * 0.5, rect.size)
			draw_rect(r, color, false, 1.0)
			continue
		var circle := shape_node.shape as CircleShape2D
		if circle != null:
			draw_arc(shape_node.position, circle.radius, 0.0, TAU, 24, color, 1.0)
