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

## The box the menus are laid out in, and the reason `menu_scale` exists rather
## than menus simply taking `suggested()`.
##
## The inventory page is the widest thing in the game: twelve 50px slots with
## 5px gaps, a 216px character column and a 250px detail column either side, and
## 40px page margins — 1245x702 measured, against this 1280x720 box.
const MENU_DESIGN := Vector2(1280.0, 720.0)

## How far a menu is allowed to shrink when the window is smaller than the box
## it was drawn in. Below this the text stops being legible and the honest
## answer is a scroll bar, not a smaller font.
const MENU_MIN_FACTOR := 0.5

## Assigning this is *the player choosing*, which is why it saves and stops
## following the window. Everything internal goes through `_set_factor` instead.
##
## **These used to be the same path, and it was a real bug.** `_restore()` set
## `factor = suggested()` when there was no saved setting — which ran this
## setter, which marked the scale as chosen and wrote it to disk. At boot the
## window is still the project's default 720 tall, so the guess was always 1.0.
## Every first launch therefore saved `ui_scale=1.0` as though it had been
## picked deliberately, and every launch after that was pinned to 1× on a
## monitor of any size, with the interface laid out in a box far bigger than it
## was designed for.
var factor: float = 1.0:
	set(value):
		_set_factor(value, true)
	get:
		return _factor

## The real storage. `factor` is a façade over it so that writing to `factor`
## can mean "the player picked this" while the internals still have a way to
## move the number without that claim.
var _factor: float = 1.0

## False until the player touches the setting. Until then the scale follows the
## window, so booting fullscreen on a 1440p monitor does not hand somebody a
## 1x interface and expect them to find the menu that fixes it.
var _chosen: bool = false


## `chosen` is what separates a preference from a guess: only a preference is
## written to disk, and only a preference stops the window being followed.
func _set_factor(value: float, chosen: bool) -> void:
	# Snapped before clamping so a stored 1.37 from a hand-edited config lands
	# on a step rather than being honoured.
	var clamped: float = clampf(snappedf(value, STEP), MIN_FACTOR, MAX_FACTOR)
	if chosen:
		_chosen = true
	if is_equal_approx(clamped, _factor):
		if chosen:
			_save()
		return
	_factor = clamped
	_apply()
	if _chosen:
		_save()
	changed.emit(_factor)


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


## What a menu is drawn at: the largest step that still leaves `MENU_DESIGN`
## worth of room inside the window.
##
## **Menus used to take `suggested()`, and it ran them off the screen.**
## `suggested()` snaps to the *nearest* step, so it rounds up — a 1600x900
## window measures 1.25 and was handed 1.5, which left the menu a 1067x600 box
## to lay 1245x702 of inventory out in. Both axes overflowed, and the bottom of
## the page went off the bottom of the screen, which is exactly the report.
## 1366x768 and 1440x900 round up the same way; 1080p and 1440p happen to land
## on a step and were fine, which is why this survived so long — the two
## resolutions anyone tests at are the two it got right.
##
## So this floors instead of snapping, and floors against the whole box rather
## than against the height alone. A short-but-wide window (2560x1080) and a
## narrow-but-tall one are both cases where one axis fits and the other does
## not, and only the smaller of the two is safe to use.
##
## Below 1x it stops stepping and returns the raw fit: a window smaller than the
## box the menus were drawn in has no whole step to offer, and a slightly soft
## menu that fits beats a crisp one with its buttons off the edge.
func menu_scale() -> float:
	var area := content_rect().size
	var fit: float = minf(area.x / MENU_DESIGN.x, area.y / MENU_DESIGN.y)
	if fit < MIN_FACTOR:
		return maxf(fit, MENU_MIN_FACTOR)
	return clampf(floorf(fit / STEP) * STEP, MIN_FACTOR, MAX_FACTOR)


## A UI layer and the Control filling it. Both are needed: the layer carries the
## scale, the Control has to be resized or its anchors point at the wrong edges.
## `menu` layers ignore the player's scale setting and follow the window
## instead.
##
## **The setting is for the HUD.** Somebody who turns the interface down to 1x
## is asking for less of the screen covered *while playing* — hearts, hotbar,
## satchel. A menu is the opposite situation: the world is paused, the screen is
## theirs, and shrinking a wall of text because the health bar was in the way is
## answering a question nobody asked. So menus take `menu_scale()`, which is what
## the window says rather than what the slider says.
##
## Note that is a *fit*, not a fixed 2x — see `menu_scale`. On a 1440p screen it
## comes out at 2x; below that it is whatever the window has room for.
func register(layer: CanvasLayer, root: Control = null, menu: bool = false) -> void:
	_layers.append({"layer": layer, "root": root, "menu": menu})
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
		var used: float = menu_scale() if entry.get("menu", false) else factor
		layer.scale = Vector2(used, used)
		# The layer's offset is a translation in window pixels, applied outside
		# the scale — so it moves the whole layer onto the picture without the
		# children having to know anything about letterboxing.
		layer.offset = area.position.floor()
		if is_instance_valid(root):
			root.position = Vector2.ZERO
			root.size = (area.size / used).floor()


# ------------------------------------------------------------------ storage

func _on_window_changed() -> void:
	if not _chosen:
		_follow_window()
	_apply()


func _follow_window() -> void:
	_set_factor(suggested(), false)


func _restore() -> void:
	var stored := _load()
	if stored > 0.0:
		_set_factor(stored, true)
		return
	# A guess, not a choice: no save, and the window keeps being followed. At
	# this point the window is often still the project's default size, so this
	# number is usually wrong and is meant to be corrected by the first
	# `set_content_rect` — which cannot happen if it has been written to disk.
	_set_factor(suggested(), false)


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
