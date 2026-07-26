extends Node2D
## Render the project palette as a labelled swatch sheet, with a saturation audit.
##
## Reads the first .gpl / .hex / .txt in art/palettes/. Shows every colour with
## its hex value, and marks the ones saturated enough to compete with the blight
## accent — because "corruption is the one saturated colour" (GDD §8) is a rule
## about the whole palette, not about individual sprites, and it is much easier
## to hold if you can see which colours are dangerous before you use them.
##
## Open in the editor with F6, or:
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/palette_sheet.tscn --shot=/tmp/palette.png

## Above this HSV saturation, a colour reads as "glowing" at 1280×720 and will
## compete with the blight accent for the player's eye.
@export_range(0.0, 1.0, 0.05) var saturation_threshold: float = 0.65

## Swatches are drawn at this size; the grid wraps to fit the viewport.
@export var swatch: Vector2 = Vector2(96, 72)

const INK := Color(0.86, 0.90, 0.76)

var _colours: PackedColorArray = []
var _source: String = ""


func _ready() -> void:
	_load_palette()
	queue_redraw()


func _load_palette() -> void:
	var dir := DirAccess.open("res://art/palettes")
	if dir == null:
		return
	for file in dir.get_files():
		var lower := file.to_lower()
		if lower.ends_with(".gpl") or lower.ends_with(".hex") or lower.ends_with(".txt"):
			_source = "res://art/palettes/".path_join(file)
			_colours = _parse(_source)
			if not _colours.is_empty():
				return


func _parse(path: String) -> PackedColorArray:
	var out := PackedColorArray()
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return out
	var lines := handle.get_as_text().split("\n")
	var is_gpl := lines.size() > 0 and lines[0].strip_edges().to_lower().begins_with("gimp palette")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.is_empty() or line.begins_with("#") and not is_gpl:
			# A leading '#' is a comment in .gpl and a hex prefix in .hex.
			if is_gpl:
				continue
		if is_gpl:
			if i == 0 or line.begins_with("#") or line.is_empty():
				continue
			var parts := line.split(" ", false)
			if parts.size() >= 3 and parts[0].is_valid_int():
				out.append(Color8(parts[0].to_int(), parts[1].to_int(), parts[2].to_int()))
		else:
			var token := line.lstrip("#").strip_edges()
			if token.length() == 6 and token.is_valid_hex_number():
				out.append(Color(("#" + token)))
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.12, 0.125, 0.14), true)

	if _colours.is_empty():
		draw_string(font, Vector2(40, 120), "No palette found in art/palettes/",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, INK)
		draw_string(font, Vector2(40, 168),
			"Download the 64-colour palette as .gpl and commit it there.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.86, 0.90, 0.76, 0.75))
		draw_string(font, Vector2(40, 200), "See art/palettes/README.md",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.86, 0.90, 0.76, 0.6))
		return

	var hot := 0
	for colour in _colours:
		if colour.s >= saturation_threshold:
			hot += 1

	draw_string(font, Vector2(24, 34), "%s — %d colours" % [_source.get_file(), _colours.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	var warn := Color(0.95, 0.62, 0.42) if hot > 8 else Color(0.86, 0.90, 0.76, 0.75)
	draw_string(font, Vector2(24, 60),
		"%d of %d above %.0f%% saturation — these compete with the blight accent"
		% [hot, _colours.size(), saturation_threshold * 100.0],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, warn)

	var columns := maxi(1, int((view.x - 48.0) / swatch.x))
	var top := 84.0
	for i in _colours.size():
		var colour := _colours[i]
		var pos := Vector2(24.0 + float(i % columns) * swatch.x,
			top + float(i / columns) * swatch.y)
		var rect := Rect2(pos, swatch - Vector2(4, 4))
		draw_rect(rect, colour, true)

		# Label in whichever of black/white actually reads on this swatch.
		var label_colour := Color.BLACK if colour.get_luminance() > 0.45 else Color.WHITE
		draw_string(font, pos + Vector2(6, swatch.y - 28.0),
			"#%02x%02x%02x" % [colour.r8, colour.g8, colour.b8],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_colour)

		if colour.s >= saturation_threshold:
			draw_rect(rect, Color(1, 1, 1, 0.9), false, 2.0)
			draw_string(font, pos + Vector2(6, 20.0), "HOT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_colour)
