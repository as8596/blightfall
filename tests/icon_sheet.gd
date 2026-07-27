extends Node2D
## Contact sheet of every icon in art/icons/, at true scale and magnified.
##
## Icons are judged against each other, not one at a time — a set where three
## are busy and two are sparse reads as a mistake even when each is fine alone.
## This puts them side by side, and flags any whose canvas doesn't match the
## size its folder expects.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/icon_sheet.tscn --shot=/tmp/icons.png

## folder, expected canvas, magnification for the inspection row
const FOLDERS: Array = [
	["res://art/icons/items", Vector2i(64, 64), 3],
	["res://art/icons/ui", Vector2i(32, 32), 4],
]

const INK := Color(0.86, 0.90, 0.76)
const WARN := Color(0.95, 0.6, 0.45)

## Icons are loaded here rather than inside _draw().
##
## A texture fetched with runtime `load()` is not on the GPU yet when the same
## frame draws it — it samples as opaque white. `_draw()` normally runs once, so
## it would stay white forever. Loading up front and forcing a few redraws lets
## the upload land.
var _folders: Array = []
var _warmup: int = 4


func _ready() -> void:
	for entry in FOLDERS:
		_folders.append(_load_folder(entry[0]))
	queue_redraw()


func _process(_delta: float) -> void:
	if _warmup <= 0:
		set_process(false)
		return
	_warmup -= 1
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.12, 0.125, 0.14), true)

	var y := 40.0
	var total := 0
	for i in FOLDERS.size():
		var entry: Array = FOLDERS[i]
		var found: Array = _folders[i] if i < _folders.size() else []
		total += found.size()
		y = _draw_folder(font, view, y, entry[0], entry[1], entry[2], found)
		y += 24.0

	if total == 0:
		draw_string(font, Vector2(40, view.y * 0.5), "No icons yet — drop them in art/icons/",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
		draw_string(font, Vector2(40, view.y * 0.5 + 34.0),
			"items/ is 64x64, ui/ is 32x32. See art/icons/README.md",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.86, 0.90, 0.76, 0.7))


func _load_folder(path: String) -> Array:
	var found: Array = []
	_collect(path, "", found)
	found.sort_custom(func(a, b): return a[0] < b[0])
	return found


## Recurses, because items/ is sorted into role subfolders. Labels carry the
## subfolder so the sheet says which bucket a thing is in.
func _collect(path: String, prefix: String, into: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.to_lower().ends_with(".png"):
			continue
		var texture: Texture2D = load(path.path_join(file))
		if texture != null:
			into.append([prefix + file.get_basename(), texture])
	for sub in dir.get_directories():
		_collect(path.path_join(sub), prefix + sub + "/", into)


func _draw_folder(font: Font, view: Vector2, y: float, path: String,
		expected: Vector2i, zoom: int, found: Array) -> float:
	var wrong := 0
	for entry in found:
		if (entry[1] as Texture2D).get_size() != Vector2(expected):
			wrong += 1

	var header := "%s — %d icon(s), expected %dx%d" % [
		path.trim_prefix("res://art/icons/"), found.size(), expected.x, expected.y]
	draw_string(font, Vector2(24, y), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	if wrong > 0:
		draw_string(font, Vector2(24 + font.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 16, y),
			"%d wrong size" % wrong, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, WARN)
	y += 16.0

	if found.is_empty():
		return y + 20.0

	# Row 1 — magnified, for judging the drawing.
	var cell := float(expected.x * zoom) + 20.0
	var x := 24.0
	var row_top := y
	for entry in found:
		if x + cell > view.x - 24.0:
			x = 24.0
			row_top += cell + 34.0
		var texture: Texture2D = entry[1]
		var size := texture.get_size() * zoom
		var slot := Rect2(x, row_top + 8.0, size.x, size.y)
		# Checker behind, so transparent backgrounds are visible as transparent
		# rather than reading as black.
		_checker(slot)
		draw_texture_rect(texture, slot, false)
		draw_rect(slot, Color(1, 1, 1, 0.14), false, 1.0)
		var label := String(entry[0])
		if texture.get_size() != Vector2(expected):
			label += " (%dx%d)" % [texture.get_size().x, texture.get_size().y]
		draw_string(font, Vector2(x, row_top + size.y + 26.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			WARN if texture.get_size() != Vector2(expected) else INK)
		x += cell

	# Row 2 — true scale, which is the only row that says whether it reads in
	# game. Given its own band below the labels rather than sharing a baseline.
	var band := row_top + cell + 34.0
	draw_string(font, Vector2(24, band + 40.0), "at true scale:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.86, 0.90, 0.76, 0.7))
	x = 150.0
	for entry in found:
		var texture: Texture2D = entry[1]
		draw_texture(texture, Vector2(x, band))
		x += texture.get_size().x + 16.0
	return band + float(expected.y) + 26.0


func _checker(rect: Rect2) -> void:
	var step := 8.0
	var light := Color(0.22, 0.23, 0.25)
	var dark := Color(0.17, 0.18, 0.2)
	var row := 0
	var y := rect.position.y
	while y < rect.end.y:
		var col := 0
		var x := rect.position.x
		while x < rect.end.x:
			var w := minf(step, rect.end.x - x)
			var h := minf(step, rect.end.y - y)
			draw_rect(Rect2(x, y, w, h), light if (row + col) % 2 == 0 else dark, true)
			x += step
			col += 1
		y += step
		row += 1
