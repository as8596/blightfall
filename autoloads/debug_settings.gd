extends Node
## Debug toggles, shared by the overlay and by every Hitbox/Hurtbox.
##
## BUILD-PLAN, week 1, rule 2: "build a debug overlay in week one and never turn
## it off." This autoload is the switchboard behind it.

signal changed

## F1 — the text overlay.
var show_overlay: bool = true:
	set(value):
		if show_overlay == value:
			return
		show_overlay = value
		changed.emit()

## F2 — hitbox / hurtbox shape visualisation.
var show_boxes: bool = false:
	set(value):
		if show_boxes == value:
			return
		show_boxes = value
		changed.emit()

## F3 — slow motion, for reading frame data with your eyes.
var slow_motion: bool = false:
	set(value):
		if slow_motion == value:
			return
		slow_motion = value
		HitStop.set_base_time_scale(slow_motion_scale if value else 1.0)
		changed.emit()

var slow_motion_scale: float = 0.2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## F11 — fullscreen, and the way back out.
##
## Living here is a stopgap. Display mode is a real setting rather than a debug
## toggle and belongs in the options screen GDD §14 calls for; it is here now
## because there is no options screen, and a game that starts fullscreen with no
## way back to a window is worse than one that never went fullscreen.
##
## The project boots fullscreen (`display/window/size/mode=3`). Note that 720p
## content on a 1080p display is a 1.5x upscale, so pixels are very slightly
## uneven — see docs/M1-NOTES.md. An "integer scaling only" option is the fix,
## and it is the same options screen's job.
func toggle_fullscreen() -> void:
	var windowed := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if windowed else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			show_overlay = not show_overlay
			get_viewport().set_input_as_handled()
		KEY_F2:
			show_boxes = not show_boxes
			get_viewport().set_input_as_handled()
		KEY_F3:
			slow_motion = not slow_motion
			get_viewport().set_input_as_handled()
		KEY_F11:
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
