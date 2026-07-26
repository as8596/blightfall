class_name CameraRig
extends Camera2D
## Camera on a separate rig, never a child of the player (GDD §12, rule 4).
##
## It follows a target it was handed. It does not know what a player is, which
## is what lets it later follow a midpoint, a boss, or a cutscene marker
## without any of those knowing about the camera either.

## Who to follow. Set in the level scene, or via `set_target()` at runtime.
@export var target_path: NodePath

## GDD §10: smoothing ~5.0.
@export var smoothing: float = 5.0

## Room bounds. Zero size = unbounded.
@export var room_bounds: Rect2 = Rect2()

@export_group("Shake")
## GDD §5: 2px on heavy hits only. This is the ceiling, not the default.
@export var max_shake: float = 4.0
## How fast a shake decays, in shake-units per second.
@export var shake_decay: float = 12.0

var _target: Node2D
var _shake_amount: float = 0.0
var _shake_time_left: float = 0.0


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing
	_target = get_node_or_null(target_path) as Node2D
	if room_bounds.size != Vector2.ZERO:
		apply_room_bounds(room_bounds)
	if _target != null:
		# Start on the target rather than smoothing in from wherever the rig
		# happened to be placed in the editor.
		global_position = _target.global_position
		reset_smoothing()
	Events.screen_shake_requested.connect(shake)


func _physics_process(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position

	if _shake_time_left <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return

	_shake_time_left -= delta
	_shake_amount = maxf(_shake_amount - shake_decay * delta, 0.0)
	# Snapped to whole pixels: at 320×180 a sub-pixel shake either does nothing
	# or crawls the whole frame, depending on where the rounding lands.
	offset = Vector2(
		roundf(Rng.randf_range(-_shake_amount, _shake_amount)),
		roundf(Rng.randf_range(-_shake_amount, _shake_amount))
	)


func set_target(node: Node2D, snap: bool = true) -> void:
	_target = node
	if snap and node != null:
		global_position = node.global_position
		reset_smoothing()


func shake(amount: float, duration: float = 0.16) -> void:
	_shake_amount = maxf(_shake_amount, minf(amount, max_shake))
	_shake_time_left = maxf(_shake_time_left, duration)


## Clamp the view to a room (GDD §10: per-room limits).
func apply_room_bounds(bounds: Rect2) -> void:
	room_bounds = bounds
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


func shake_amount() -> float:
	return _shake_amount if _shake_time_left > 0.0 else 0.0
