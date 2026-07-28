extends CanvasLayer
## The three things the player has to be able to read without stopping.
##
## **Hotbar** bottom-centre, **hearts** bottom-left, **satchel** bottom-right. Stamina is not here at all —
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

## Health is a bar, not a row of hearts (amends GDD §5's wording). It keeps one
## tick per heart, though: "two hits left" is a decision you can make mid-fight
## and "31%" is not, so the discreteness the hearts were carrying stays.
const HEALTH_SIZE: Vector2 = Vector2(232.0, 18.0)
const HEALTH_FULL := Color(0.80, 0.28, 0.26)
const HEALTH_LOW := Color(0.88, 0.46, 0.24)
const HEALTH_BACK := Color(0.20, 0.16, 0.16, 0.85)
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

const SLOT_SIZE: float = 52.0
const SLOT_GAP: float = 6.0
const SLOT_BACK := Color(0.13, 0.11, 0.10, 0.82)
const SLOT_EDGE := Color(0.42, 0.35, 0.26)
const SLOT_REFUSED := Color(0.86, 0.45, 0.30)
const SLOT_SELECTED := Color(0.95, 0.88, 0.70)
## Extra space between the numbered ten and the reserved potion pair.
const POTION_GAP: float = 26.0

var health: int = 0
var max_health: int = 0
var carried: int = 0
var capacity: int = 0
var slot_items: Array = []
var slot_counts: Array = []

var selected: int = 0

## Seconds left on the "that did nothing" flash, per slot.
var _refused: Dictionary = {}

## Where the health bar last drew, so hover-testing uses the same rectangle the
## player is actually pointing at rather than a second copy of the maths.
var _health_rect: Rect2 = Rect2()
var _health_hovered: bool = false

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
	UiScale.register(self, _canvas)

	Events.player_health_changed.connect(_on_health)
	Events.player_inventory_changed.connect(_on_inventory)
	Events.player_items_changed.connect(_on_items)
	Events.player_item_refused.connect(_on_item_refused)
	Events.player_hotbar_selected.connect(_on_selected)
	# Always processing: the hover test polls the pointer. The canvas ignores
	# mouse input by design — a HUD that swallows clicks is a HUD that breaks
	# whatever is underneath it — so it cannot be told by `gui_input`.
	set_process(true)


func _on_health(current: int, maximum: int) -> void:
	health = current
	max_health = maximum
	_canvas.queue_redraw()


func _on_inventory(units: int, limit: int) -> void:
	carried = units
	capacity = limit
	_canvas.queue_redraw()


func _on_items(entries: Array, counts: Array) -> void:
	slot_items = entries.duplicate()
	slot_counts = counts.duplicate()
	_canvas.queue_redraw()


func _on_item_refused(slot: int) -> void:
	_refused[slot] = 0.45
	_canvas.queue_redraw()


func _on_selected(slot: int) -> void:
	selected = slot
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	var hovered := _health_rect.has_point(_canvas.get_local_mouse_position())
	if hovered != _health_hovered:
		_health_hovered = hovered
		_canvas.queue_redraw()

	if _refused.is_empty():
		return
	for slot in _refused.keys():
		_refused[slot] -= delta
		if _refused[slot] <= 0.0:
			_refused.erase(slot)
	_canvas.queue_redraw()


# --------------------------------------------------------------------- drawing

func _draw_hud() -> void:
	var size := _canvas.size
	_draw_health(Vector2(MARGIN.x, size.y - MARGIN.y - HEALTH_SIZE.y))
	_draw_hotbar(size)
	_draw_satchel(Vector2(size.x - MARGIN.x - SATCHEL_SIZE.x, size.y - MARGIN.y - SATCHEL_SIZE.y))


## One tick per heart container, so the bar still answers "how many more hits"
## at a glance. Turns warm below a quarter — the only moment the bar needs to
## raise its voice.
func _draw_health(origin: Vector2) -> void:
	if max_health <= 0:
		return
	var ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_rect = Rect2(origin, HEALTH_SIZE)
	_canvas.draw_rect(Rect2(origin - Vector2(2, 2), HEALTH_SIZE + Vector2(4, 4)), HEART_EDGE)
	_canvas.draw_rect(Rect2(origin, HEALTH_SIZE), HEALTH_BACK)
	_canvas.draw_rect(
		Rect2(origin, Vector2(HEALTH_SIZE.x * ratio, HEALTH_SIZE.y)),
		HEALTH_LOW if ratio <= 0.25 else HEALTH_FULL
	)
	var step := HEALTH_SIZE.x / float(max_health)
	for i in range(1, max_health):
		var x := origin.x + step * i
		_canvas.draw_line(Vector2(x, origin.y), Vector2(x, origin.y + HEALTH_SIZE.y),
			HEART_EDGE, 2.0)

	# On hover only. The bar's job is to be readable without reading — a number
	# sitting on it permanently is a number the eye stops at every time it
	# glances down, which is the opposite of what a bar is for.
	if not _health_hovered:
		return
	var font := ThemeDB.fallback_font
	var label := "%d / %d" % [health, max_health]
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
	var at := origin + Vector2((HEALTH_SIZE.x - width) * 0.5, -8.0)
	_canvas.draw_string(font, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		FONT_SIZE, Color(0.05, 0.04, 0.04, 0.9))
	_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, TEXT)


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



## Five slots, centred along the bottom edge — the row the hand finds without
## looking, and the reason the bar is slots rather than a bag: a hotbar that
## cannot show everything it holds is a menu wearing a hotbar's clothes.
##
## Numbered, because the binding *is* the affordance. An unlabelled row teaches
## nobody that 1–5 do anything.
func _draw_hotbar(screen: Vector2) -> void:
	# Only the hotbar's share. The pack behind Tab uses the same array, and
	# drawing all forty across the bottom of the screen would be a wall.
	var count: int = mini(slot_items.size(), ItemsComponent.HOTBAR_SLOTS)
	if count <= 0:
		return
	# A wider gap before the reserved pair, so the bar reads as "ten, and two"
	# rather than as twelve of the same thing.
	var width := count * SLOT_SIZE + (count - 1) * SLOT_GAP + POTION_GAP
	var origin := Vector2((screen.x - width) * 0.5, screen.y - MARGIN.y - SLOT_SIZE)
	var font := ThemeDB.fallback_font

	for i in count:
		var shift: float = POTION_GAP if ItemsComponent.is_potion_slot(i) else 0.0
		var at := origin + Vector2(i * (SLOT_SIZE + SLOT_GAP) + shift, 0.0)
		var box := Rect2(at, Vector2(SLOT_SIZE, SLOT_SIZE))
		_canvas.draw_rect(box, SLOT_BACK)
		var chosen := i == selected
		var edge: Color = SLOT_REFUSED if _refused.has(i) else (SLOT_SELECTED if chosen else SLOT_EDGE)
		if chosen:
			# Grown outward rather than recoloured alone, so the selection is
			# legible at a glance and in a screenshot with no colour at all.
			_canvas.draw_rect(box.grow(3.0), edge, false, 3.0)
		_canvas.draw_rect(box, edge, false, 2.0)

		var item: ItemData = slot_items[i] if slot_items[i] is ItemData else null
		if item != null and item.icon != null:
			# Icons are drawn to fit rather than 1:1: the uploaded set is not all
			# one size, and a hotbar where the bread is bigger than the key reads
			# as a bug rather than as bread.
			var pad := 6.0
			_canvas.draw_texture_rect(item.icon,
				Rect2(at + Vector2(pad, pad), Vector2(SLOT_SIZE - pad * 2.0, SLOT_SIZE - pad * 2.0)),
				false)

		_canvas.draw_string(font, at + Vector2(4.0, 14.0), _slot_key(i),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.75, 0.70, 0.62, 0.85))

		var held: int = int(slot_counts[i]) if i < slot_counts.size() else 0
		if item != null and held > 1:
			var label := str(held)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x

			var text_at := at + Vector2(SLOT_SIZE - w - 4.0, SLOT_SIZE - 5.0)
			_canvas.draw_string(font, text_at + Vector2(1, 1), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, Color(0.05, 0.04, 0.04, 0.9))
			_canvas.draw_string(font, text_at, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, TEXT)


## What the slot's key is called on the bar. Ten numbers, then the two reserved
## slots, which are bound to the keys next to them on the row.
static func _slot_key(slot: int) -> String:
	if slot < 9:
		return str(slot + 1)
	if slot == 9:
		return "0"
	return "-" if slot == 10 else "="
