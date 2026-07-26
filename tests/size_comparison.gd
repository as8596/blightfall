extends Node2D
## 16×24 vs 32×48 at true scale, against the 16px tile grid they have to live in.
##
## Sprite size is not a local decision. A character has to fit through a
## doorway, and doorways are made of tiles, so the character's width sets the
## tile size — and the tile size sets the cost of every tileset in the game.
## This scene draws that consequence instead of describing it.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/size_comparison.tscn --shot=/tmp/sizes.png

const SMALL: Texture2D = preload("res://art/sprites/scale_demo_16x24.png")
const LARGE: Texture2D = preload("res://art/sprites/scale_demo_32x48.png")

const TILE: int = 16
const WALL := Color(0.302, 0.286, 0.271)
const INK := Color(0.86, 0.90, 0.76)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 320, 180), Color(0.184, 0.192, 0.208), true)

	var grid_color := Color(1, 1, 1, 0.05)
	for x in range(0, 321, TILE):
		draw_line(Vector2(x, 0), Vector2(x, 180), grid_color, 1.0)
	for y in range(0, 181, TILE):
		draw_line(Vector2(0, y), Vector2(320, y), grid_color, 1.0)

	draw_string(font, Vector2(6, 12), "same character, both at true scale — grid is 16px tiles",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK)

	# ---- left: 16x24 through a one-tile doorway
	_wall(16, 48, 128, 64, 80)
	draw_texture(SMALL, Vector2(80, 72))
	draw_string(font, Vector2(22, 116), "16x24", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK)
	draw_string(font, Vector2(22, 126), "384 px", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, INK)
	draw_string(font, Vector2(22, 136), "fits a 1-tile gap", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, INK)
	draw_string(font, Vector2(22, 146), "16px tiles", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, INK)

	# ---- right: 32x48 against the same doorway
	_wall(176, 48, 288, 64, 240)
	draw_texture(LARGE, Vector2(232, 72))
	draw_string(font, Vector2(182, 136), "32x48", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK)
	draw_string(font, Vector2(182, 146), "1536 px — 4x the work", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, INK)
	draw_string(font, Vector2(182, 156), "needs a 2-tile gap", HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
		Color(0.90, 0.55, 0.45))
	draw_string(font, Vector2(182, 166), "-> 32px tiles -> 4x every tileset", HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
		Color(0.90, 0.55, 0.45))


## A tile wall from x1 to x2 with a one-tile doorway at `gap_x`.
func _wall(x1: int, y: int, x2: int, y2: int, gap_x: int) -> void:
	for x in range(x1, x2, TILE):
		if x == gap_x:
			continue
		draw_rect(Rect2(x, y, TILE, y2 - y), WALL, true)
		draw_rect(Rect2(x, y, TILE, y2 - y), Color(0, 0, 0, 0.35), false, 1.0)
