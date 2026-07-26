extends Node2D
## The same character at three resolutions, each with the tile size it implies.
##
## Sprite size is not a local decision. A character has to fit through a
## doorway, doorways are built from tiles, so the character's width sets the
## tile size — and the tile size sets the cost of every tileset in the game.
## Each panel below draws a character against the grid it would actually live
## on, so that coupling is visible rather than argued about.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/size_comparison.tscn --shot=/tmp/sizes.png

const SPRITES: Array[Texture2D] = [
	preload("res://art/sprites/scale_demo_16x24.png"),
	preload("res://art/sprites/scale_demo_32x48.png"),
	preload("res://art/sprites/scale_demo_64x96.png"),
]

## sprite index, tile size, then two lines of caption under each panel.
const PANELS: Array = [
	[0, 16, "16x24", "384px / 8 col"],
	[1, 32, "32x48", "1536px / 16 col"],
	[2, 64, "64x96  <- STANDARD", "6144px / 21 col"],
]

const BASELINE: float = 600.0
const PANEL_W: float = 400.0
const PANEL_TOP: float = 80.0
const INK := Color(0.86, 0.90, 0.76)
const FLOOR := Color(0.223, 0.231, 0.247)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.145, 0.152, 0.168), true)
	draw_string(font, Vector2(24, 40), "one character, three resolutions - all at true 1:1 scale",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)

	var x := 24.0
	for panel in PANELS:
		_panel(font, x, SPRITES[panel[0]], panel[1], panel[2], panel[3])
		x += PANEL_W + 16.0


func _panel(font: Font, x: float, texture: Texture2D, tile: int, title: String, sub: String) -> void:
	var area := Rect2(x, PANEL_TOP, PANEL_W, BASELINE - PANEL_TOP)

	# Each panel stands on its own tile grid, so what is being compared is the
	# character-to-tile ratio rather than an abstract pixel count.
	draw_rect(area, FLOOR, true)
	var grid_color := Color(1, 1, 1, 0.08)
	var gx := x
	while gx <= area.end.x:
		draw_line(Vector2(gx, area.position.y), Vector2(gx, area.end.y), grid_color, 1.0)
		gx += tile
	var gy := BASELINE
	while gy >= area.position.y:
		draw_line(Vector2(x, gy), Vector2(area.end.x, gy), grid_color, 1.0)
		gy -= tile
	draw_line(Vector2(x, BASELINE), Vector2(area.end.x, BASELINE), Color(1, 1, 1, 0.25), 1.0)

	var size := texture.get_size()
	draw_texture(texture, Vector2(x + roundf((PANEL_W - size.x) * 0.5), BASELINE - size.y))

	draw_string(font, Vector2(x + 4.0, BASELINE + 34.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)
	draw_string(font, Vector2(x + 4.0, BASELINE + 60.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.86, 0.90, 0.76, 0.75))
	draw_string(font, Vector2(x + 230.0, BASELINE + 60.0), "%dpx tiles" % tile,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.78, 0.84, 0.62, 0.9))
