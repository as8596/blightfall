extends Node
## How big the interface is drawn, in whole steps.
##
## Now that the world renders into its own SubViewport (`ui/world_view.gd`), the
## UI is laid out at the window's real resolution — which is what makes text
## sharp, and also what makes it *small* on a large monitor. This is the knob
## that fixes the second half.
##
## **Whole numbers only, and that is the point.** A UI scaled by 1.5 has every
## other row of pixels duplicated, which is exactly the softness the viewport
## split was done to remove. At 1×, 2× and 3× a nearest-filtered interface is
## pixel-exact, so the setting cannot be used to make the game look worse.
##
## Each registered layer is scaled and its root Control resized to
## `window / factor`, so anchors still reach the real corners of the screen
## rather than a box in the top-left.

signal changed(factor: int)

const CONFIG_PATH := "user://settings.cfg"
const MIN_FACTOR := 1
const MAX_FACTOR := 4

## The height the interface is authored against. A 1440p monitor gets 2× by
## default, a 720p one gets 1×.
const BASE_HEIGHT := 720.0

var factor: int = 1:
	set(value):
		var clamped: int = clampi(value, MIN_FACTOR, MAX_FACTOR)
		if clamped == factor:
			return
		factor = clamped
		_apply()
		_save()
		changed.emit(factor)

var _layers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	factor = _load()
	get_tree().root.size_changed.connect(_apply)
	_apply.call_deferred()


## What the window would suggest, if the player has not chosen.
func suggested() -> int:
	var height := float(get_tree().root.size.y)
	return clampi(int(floorf(height / BASE_HEIGHT)), MIN_FACTOR, MAX_FACTOR)


## A UI layer and the Control filling it. Both are needed: the layer carries the
## scale, the Control has to be resized or its anchors point at the wrong edges.
func register(layer: CanvasLayer, root: Control) -> void:
	_layers.append({"layer": layer, "root": root})
	_apply()


func _apply() -> void:
	var window := Vector2(get_tree().root.size)
	if window.x <= 0.0 or window.y <= 0.0:
		return
	for entry in _layers:
		var layer: CanvasLayer = entry["layer"]
		var root: Control = entry["root"]
		if not is_instance_valid(layer) or not is_instance_valid(root):
			continue
		layer.scale = Vector2(factor, factor)
		root.position = Vector2.ZERO
		root.size = (window / float(factor)).floor()


# ------------------------------------------------------------------ storage

func _load() -> int:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return suggested()
	return clampi(int(config.get_value("display", "ui_scale", suggested())),
		MIN_FACTOR, MAX_FACTOR)


func _save() -> void:
	var config := ConfigFile.new()
	# Read first so this never becomes the file that eats every other setting.
	@warning_ignore("return_value_discarded")
	config.load(CONFIG_PATH)
	config.set_value("display", "ui_scale", factor)
	@warning_ignore("return_value_discarded")
	config.save(CONFIG_PATH)
