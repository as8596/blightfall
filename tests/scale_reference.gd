extends Node2D
## Sprite sizes drawn at true scale in the real viewport.
##
## "How big should this be" is a question that reads completely differently as a
## number and as a picture. Open this before starting a new sprite; add a row to
## SAMPLES to try a size before committing a week to it.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/scale_reference.tscn --shot=/tmp/scale.png

## The standard character, drawn at the project's sprite resolution.
const DEMO: Texture2D = preload("res://art/sprites/scale_demo_64x96.png")

## Tile size. Sized so the character is exactly one tile wide.
const GRID: int = 64

## label, size, colour.
const SAMPLES: Array = [
	["player\n64x96", Vector2(64, 96), Color(0.784, 0.820, 0.878)],
	["villager\n64x64", Vector2(64, 64), Color(0.420, 0.400, 0.361)],
	["big enemy\n128x128", Vector2(128, 128), Color(0.545, 0.451, 0.361)],
	["BOSS CAP\n256x256", Vector2(256, 256), Color(0.776, 0.839, 0.345)],
]

const INK := Color(0.86, 0.90, 0.76)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	var baseline := view.y - 90.0

	draw_rect(Rect2(Vector2.ZERO, view), Color(0.184, 0.192, 0.208), true)

	var grid_color := Color(1, 1, 1, 0.06)
	for x in range(0, int(view.x) + 1, GRID):
		draw_line(Vector2(x, 0), Vector2(x, view.y), grid_color, 1.0)
	for y in range(0, int(view.y) + 1, GRID):
		draw_line(Vector2(0, y), Vector2(view.x, y), grid_color, 1.0)
	draw_line(Vector2(0, baseline), Vector2(view.x, baseline), Color(1, 1, 1, 0.18), 1.0)

	var x_cursor := 40.0
	for sample in SAMPLES:
		var label: String = sample[0]
		var size: Vector2 = sample[1]
		# Standing on the baseline, like an actor whose origin is at its feet.
		var rect := Rect2(x_cursor, baseline - size.y, size.x, size.y)
		draw_rect(rect, sample[2], true)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 2.0)
		var line_y := baseline + 22.0
		for line in label.split("\n"):
			draw_string(font, Vector2(x_cursor, line_y), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
			line_y += 18.0
		x_cursor += size.x + 60.0

	# The real sprite at 1x, so the boxes above have something to be checked
	# against rather than being trusted.
	draw_texture(DEMO, Vector2(x_cursor, baseline - 96.0))
	draw_string(font, Vector2(x_cursor, baseline + 22.0), "drawn",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	draw_string(font, Vector2(x_cursor, baseline + 40.0), "64x96",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)

	draw_string(font, Vector2(20, 30), "%dx%d internal — true scale" % [view.x, view.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	draw_string(font, Vector2(20, 52), "grid = %dpx tiles — %.0f x %.1f tiles on screen"
		% [GRID, view.x / GRID, view.y / GRID],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.90, 0.76, 0.7))
	draw_string(font, Vector2(20, view.y - 20.0),
		"the player is %.0f%% of screen height; a 256px boss is %.0f%%"
		% [96.0 / view.y * 100.0, 256.0 / view.y * 100.0],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.90, 0.76, 0.75))
