extends Node
## Global hitstop (BUILD-PLAN week 3, "do not skip").
##
## Freezes `Engine.time_scale` for a real-time duration. Real-time is the whole
## trick: at time_scale 0 a SceneTreeTimer never ticks and `delta` is zero, so
## the countdown is done against the system clock instead.

## Time scale the game returns to. The debug slow-motion toggle changes this,
## so hitstop composes with it rather than fighting it.
var base_time_scale: float = 1.0

var _end_msec: int = 0
var _active: bool = false


func _ready() -> void:
	# Must keep running while the tree is paused and while time is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() < _end_msec:
		return
	_active = false
	Engine.time_scale = base_time_scale
	set_process(false)


## Freeze for `duration` seconds of real time. Overlapping calls extend rather
## than restart, so a group fight can't stack itself into a slideshow.
func freeze(duration: float, time_scale: float = 0.0) -> void:
	if duration <= 0.0:
		return
	var end := Time.get_ticks_msec() + int(duration * 1000.0)
	_end_msec = maxi(_end_msec, end)
	_active = true
	Engine.time_scale = time_scale
	set_process(true)


func is_active() -> bool:
	return _active


func time_remaining() -> float:
	if not _active:
		return 0.0
	return maxf(0.0, float(_end_msec - Time.get_ticks_msec()) / 1000.0)


## Used by the debug slow-motion toggle.
func set_base_time_scale(value: float) -> void:
	base_time_scale = value
	if not _active:
		Engine.time_scale = value
