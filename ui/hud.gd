extends CanvasLayer
## The three things the player has to be able to read without stopping.
##
## **Hearts** bottom-left, **satchel** bottom-right. Stamina is not here at all —
## it is a ring around the character (`ui/stamina_wheel.gd`), where you are
## already looking when you dash. Bottom-aligned because the debug overlay owns the top-left corner and
## BUILD-PLAN week 1 rule 2 says that never comes off; a HUD you have to hide a
## dev tool to read is a HUD nobody checks.
##
## An autoload, like `ScreenFade`, so it survives `change_scene_to_file` and
## every level gets it without remembering to add it. It holds no game state —
## it listens to `Events` and draws what it is told. Before this, seven of the
## nine signals on that bus had no listener at all.
##
## Drawn in code rather than assembled from art, for the same reason the village
## is grey boxes: the question right now is whether the *loop* reads, and a
## satchel gauge made of rectangles answers that as well as a beautiful one.

## Below ScreenFade (128), above the world.
const LAYER: int = 64

const MARGIN: Vector2 = Vector2(28.0, 24.0)

const HEART_SIZE: float = 26.0
const HEART_STEP: float = 32.0

const HEART_FULL := Color(0.80, 0.28, 0.26)
const HEART_EMPTY := Color(0.20, 0.16, 0.16, 0.85)
const HEART_EDGE := Color(0.10, 0.08, 0.08, 0.9)

const SATCHEL_SIZE: Vector2 = Vector2(148.0, 14.0)
const SATCHEL_BACK := Color(0.14, 0.12, 0.11, 0.85)
const SATCHEL_FILL := Color(0.78, 0.60, 0.32)
## Full is the moment the run's central question — turn back, or one more room —
## stops being hypothetical, so it gets its own colour rather than a full bar.
const SATCHEL_FULL := Color(0.88, 0.76, 0.44)
const TEXT := Color(0.95, 0.92, 0.85)

## Authored against the 1280x720 viewport and scaled up with everything else, so
## this is "how big on a 720p screen", not "how big in pixels". 16 was legible
## in a window and thin across a fullscreen monitor.
const FONT_SIZE: int = 20

var health: int = 0
var max_health: int = 0
var carried: int = 0
var capacity: int = 0

## Off for a title screen or a cutscene. Nothing sets it yet.
var enabled: bool = true:
	set(value):
		enabled = value
		if _canvas != null:
			_canvas.visible = value

var _canvas: Control


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_canvas = Control.new()
	_canvas.name = "Hud"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)

	Events.player_health_changed.connect(_on_health)
	Events.player_inventory_changed.connect(_on_inventory)


func _on_health(current: int, maximum: int) -> void:
	health = current
	max_health = maximum
	_canvas.queue_redraw()


func _on_inventory(units: int, limit: int) -> void:
	carried = units
	capacity = limit
	_canvas.queue_redraw()


# --------------------------------------------------------------------- drawing

func _draw_hud() -> void:
	var size := _canvas.size
	_draw_hearts(Vector2(MARGIN.x, size.y - MARGIN.y - HEART_SIZE))
	_draw_satchel(Vector2(size.x - MARGIN.x - SATCHEL_SIZE.x, size.y - MARGIN.y - SATCHEL_SIZE.y))


## GDD §5: six hearts to start, twelve at most. Discrete, because "three hits
## left" is a thing you can act on and "62%" is not.
func _draw_hearts(origin: Vector2) -> void:
	for i in max_health:
		_draw_heart(origin + Vector2(i * HEART_STEP, 0.0), i < health)


func _draw_heart(at: Vector2, filled: bool) -> void:
	var body := HEART_FULL if filled else HEART_EMPTY
	var s := HEART_SIZE
	var lobe := s * 0.27
	# Outline first, as a slightly larger copy underneath — cheaper than stroking
	# and it keeps the hearts legible against a pale floor as well as a dark one.
	for pass_index in 2:
		var colour := HEART_EDGE if pass_index == 0 else body
		var grow: float = 2.0 if pass_index == 0 else 0.0
		_canvas.draw_circle(at + Vector2(lobe, lobe * 1.15), lobe + grow, colour, true, -1.0, false)
		_canvas.draw_circle(at + Vector2(s - lobe, lobe * 1.15), lobe + grow, colour, true, -1.0, false)
		_canvas.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-grow, lobe * 1.15),
			at + Vector2(s + grow, lobe * 1.15),
			at + Vector2(s * 0.5, s + grow),
		]), colour)


## The haul. This is the one that carries GDD §15 A4 — the interesting decision
## in the loop is *when to turn back*, and that decision cannot be made by a
## player who has to guess how full they are.
func _draw_satchel(origin: Vector2) -> void:
	if capacity <= 0:
		return
	var ratio: float = clampf(float(carried) / float(capacity), 0.0, 1.0)
	var full := carried >= capacity
	_canvas.draw_rect(Rect2(origin - Vector2(2, 2), SATCHEL_SIZE + Vector2(4, 4)), HEART_EDGE)
	_canvas.draw_rect(Rect2(origin, SATCHEL_SIZE), SATCHEL_BACK)
	_canvas.draw_rect(
		Rect2(origin, Vector2(SATCHEL_SIZE.x * ratio, SATCHEL_SIZE.y)),
		SATCHEL_FULL if full else SATCHEL_FILL
	)

	var font := ThemeDB.fallback_font
	var label := "%d / %d" % [carried, capacity]
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
	var at := origin + Vector2(SATCHEL_SIZE.x - width, -6.0)
	_canvas.draw_string(font, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE,
		Color(0.05, 0.04, 0.04, 0.9))
	_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, TEXT)
