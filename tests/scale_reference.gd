extends Node2D
## Sprite sizes drawn at true scale in the real 320×180 viewport.
##
## "How big should this be" is a question that reads completely differently as a
## number and as a picture. 64×64 sounds modest until you see that it is a third
## of the screen height. Open this before starting a new sprite.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/scale_reference.tscn --shot=/tmp/scale.png

## A hand-drawn 16x24 humanoid, so "does this size hold any detail" is a
## question you answer by looking rather than by arguing. Placeholder art —
## not in the palette, not used by the game.
const DEMO: Texture2D = preload("res://art/sprites/scale_demo_16x24.png")

const BASELINE: float = 132.0
const GRID: int = 16

## label, size, colour — the sizes GDD §8 actually specifies.
const SAMPLES: Array = [
	["player\n16x24", Vector2(16, 24), Color(0.784, 0.820, 0.878)],
	["villager\n16x16", Vector2(16, 16), Color(0.420, 0.400, 0.361)],
	["big enemy\n32x32", Vector2(32, 32), Color(0.545, 0.451, 0.361)],
	["BOSS CAP\n64x64", Vector2(64, 64), Color(0.776, 0.839, 0.345)],
]


func _draw() -> void:
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(0, 0, 320, 180), Color(0.184, 0.192, 0.208), true)

	# 16px tile grid, so every size is legible in tiles as well as pixels.
	var grid_color := Color(1, 1, 1, 0.06)
	for x in range(0, 321, GRID):
		draw_line(Vector2(x, 0), Vector2(x, 180), grid_color, 1.0)
	for y in range(0, 181, GRID):
		draw_line(Vector2(0, y), Vector2(320, y), grid_color, 1.0)

	draw_line(Vector2(0, BASELINE), Vector2(320, BASELINE), Color(1, 1, 1, 0.18), 1.0)

	var x_cursor := 20.0
	for sample in SAMPLES:
		var label: String = sample[0]
		var size: Vector2 = sample[1]
		var color: Color = sample[2]
		# Standing on the baseline, like an actor whose origin is at its feet.
		var rect := Rect2(x_cursor, BASELINE - size.y, size.x, size.y)
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)
		var line_y := BASELINE + 9.0
		for line in label.split("\n"):
			draw_string(font, Vector2(x_cursor, line_y), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76))
			line_y += 8.0
		x_cursor += size.x + 24.0

	draw_string(font, Vector2(8, 14), "320x180 internal — true scale",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.86, 0.90, 0.76))
	draw_string(font, Vector2(8, 26), "grid = 16px tiles",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76, 0.7))
	# The same 16x24 sprite at 1x (true in-game size) and 3x (to inspect it).
	var demo_x := 236.0
	draw_texture(DEMO, Vector2(demo_x, BASELINE - 24.0))
	draw_string(font, Vector2(demo_x - 4.0, BASELINE + 9.0), "16x24",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76))
	draw_string(font, Vector2(demo_x - 4.0, BASELINE + 17.0), "actual",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76))
	draw_texture_rect(DEMO, Rect2(demo_x + 26.0, BASELINE - 72.0, 48.0, 72.0), false)
	draw_string(font, Vector2(demo_x + 26.0, BASELINE + 9.0), "same,",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76, 0.8))
	draw_string(font, Vector2(demo_x + 26.0, BASELINE + 17.0), "3x zoom",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76, 0.8))

	draw_string(font, Vector2(8, 172), "a 64x64 boss is 36% of screen height; the player is 13%",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.86, 0.90, 0.76, 0.75))
