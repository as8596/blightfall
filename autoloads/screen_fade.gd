extends CanvasLayer
## A black rectangle over everything, and the two calls that move it.
##
## An autoload rather than something a level owns, because a transition has to
## **outlive the scene that started it**. The whole purpose of the fade is to
## hide a `change_scene_to_file`, and anything parented to the outgoing scene is
## freed halfway through its own tween — which leaves the screen stuck at
## whatever opacity it had reached.

## Long enough to read as a beat, short enough that a door you use two hundred
## times never feels like it is asking permission.
const DEFAULT_TIME: float = 0.22

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	# Above every other CanvasLayer, including the debug overlay: a fade that
	# something else draws on top of is not a fade.
	layer = 128
	# Transitions keep running while the game is paused, which is what a pause
	# menu fading in and out will need.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


## Fully black right now, with nothing in flight.
func is_covered() -> bool:
	return _rect != null and _rect.visible and _rect.color.a >= 0.999


func alpha() -> float:
	return _rect.color.a if _rect != null else 0.0


## To black.
func fade_out(duration: float = DEFAULT_TIME) -> void:
	await _to(1.0, duration)


## Back from black. Leaves the rectangle hidden rather than transparent, so it
## costs nothing when nothing is happening.
func fade_in(duration: float = DEFAULT_TIME) -> void:
	await _to(0.0, duration)
	_rect.visible = false


func _to(target: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_rect.visible = true

	if duration <= 0.0:
		_rect.color.a = target
		return

	_tween = create_tween()
	# Slow motion (F3) is a debug tool for reading combat, not an instruction to
	# spend two seconds on a door.
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "color:a", target, duration)

	# Waiting on a timer rather than on `_tween.finished`: a tween that gets
	# killed by an overlapping transition never emits `finished`, and awaiting
	# it would hang the caller forever with the screen black.
	await get_tree().create_timer(duration, true, false, true).timeout
