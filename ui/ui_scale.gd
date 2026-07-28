extends Node
## How big the interface is drawn, in whole steps.
##
## Now that the world renders into its own SubViewport (`ui/world_view.gd`), the
## UI is laid out at the window's real resolution — which is what makes text
## sharp, and also what makes it *small* on a large monitor. This is the knob
## that fixes the second half.
##
## **Half steps.** Whole numbers are pixel-exact and half steps are very
## slightly softer, since the layer transform scales glyphs rather than
## re-rasterising them. Worth it: the gap between 1× and 2× is enormous on a
## 1440p screen, and a setting that only offers "too small" and "too big" is a
## setting nobody is happy with.
##
## Each registered layer is scaled and its root Control resized to
## `window / factor`, so anchors still reach the real corners of the screen
## rather than a box in the top-left.

signal changed(factor: float)

const CONFIG_PATH := "user://settings.cfg"
const MIN_FACTOR := 1.0
const MAX_FACTOR := 4.0
const STEP := 0.5

## The height the interface is authored against. A 1440p monitor gets 2× by
## default, a 720p one gets 1×.
const BASE_HEIGHT := 720.0

var factor: float = 1.0:
	set(value):
		# Snapped before clamping so a stored 1.37 from a hand-edited config
		# lands on a step rather than being honoured.
		var clamped: float = clampf(snappedf(value, STEP), MIN_FACTOR, MAX_FACTOR)
		_chosen = true
		if is_equal_approx(clamped, factor):
			return
		factor = clamped
		_apply()
		_save()
		changed.emit(factor)

## False until the player touches the setting. Until then the scale follows the
## window, so booting fullscreen on a 1440p monitor does not hand somebody a
## 1x interface and expect them to find the menu that fixes it.
var _chosen: bool = false

var _layers: Array = []

## Where the world image sits in the window. Zero-sized until a `WorldView`
## reports one, in which case the whole window is used — which is right for a
## title screen, and would be wrong for a level.
var _content: Rect2 = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_restore()
	get_tree().root.size_changed.connect(_on_window_changed)
	_apply.call_deferred()


## What the window would suggest, if the player has not chosen.
func suggested() -> float:
	# Suggested off the *world image*, not the window — an ultrawide is no reason
	# for a bigger interface, it is a reason for wider bars.
	var height := float(content_rect().size.y)
	if height <= 0.0:
		height = float(get_tree().root.size.y)
	return clampf(snappedf(height / BASE_HEIGHT, STEP), MIN_FACTOR, MAX_FACTOR)


## A UI layer and the Control filling it. Both are needed: the layer carries the
## scale, the Control has to be resized or its anchors point at the wrong edges.
func register(layer: CanvasLayer, root: Control = null) -> void:
	_layers.append({"layer": layer, "root": root})
	_apply()


## Called by `ui/world_view.gd` every time it fits itself to the window.
func set_content_rect(rect: Rect2) -> void:
	if rect.is_equal_approx(_content):
		return
	_content = rect
	if not _chosen:
		_follow_window()
	_apply()


## The area the UI is laid out in: the world image if there is one, the whole
## window otherwise.
func content_rect() -> Rect2:
	if _content.size.x > 0.0 and _content.size.y > 0.0:
		return _content
	return Rect2(Vector2.ZERO, Vector2(get_tree().root.size))


func _apply() -> void:
	var window := Vector2(get_tree().root.size)
	if window.x <= 0.0 or window.y <= 0.0:
		return
	var area := content_rect()
	# Levels come and go, and each one brings a debug overlay that is freed with
	# it. Pruning here rather than asking every scene to unregister keeps the
	# contract one-sided: hand it a layer and forget about it.
	_layers = _layers.filter(func(e): return is_instance_valid(e["layer"]))
	for entry in _layers:
		var layer: CanvasLayer = entry["layer"]
		var root = entry["root"]
		if not is_instance_valid(layer):
			continue
		layer.scale = Vector2(factor, factor)
		# The layer's offset is a translation in window pixels, applied outside
		# the scale — so it moves the whole layer onto the picture without the
		# children having to know anything about letterboxing.
		layer.offset = area.position.floor()
		if is_instance_valid(root):
			root.position = Vector2.ZERO
			root.size = (area.size / factor).floor()


# ------------------------------------------------------------------ storage

func _on_window_changed() -> void:
	if not _chosen:
		_follow_window()
	_apply()


func _follow_window() -> void:
	var wanted := suggested()
	if is_equal_approx(wanted, factor):
		return
	factor = wanted
	_chosen = false
	changed.emit(factor)


func _restore() -> void:
	var stored := _load()
	if stored > 0.0:
		factor = stored
	else:
		factor = suggested()
		_chosen = false


## The saved factor, or 0 if the player has never chosen one.
func _load() -> float:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return 0.0
	if not config.has_section_key("display", "ui_scale"):
		return 0.0
	return clampf(snappedf(float(config.get_value("display", "ui_scale", 0.0)), STEP),
		MIN_FACTOR, MAX_FACTOR)


func _save() -> void:
	var config := ConfigFile.new()
	# Read first so this never becomes the file that eats every other setting.
	@warning_ignore("return_value_discarded")
	config.load(CONFIG_PATH)
	config.set_value("display", "ui_scale", factor)
	@warning_ignore("return_value_discarded")
	config.save(CONFIG_PATH)
