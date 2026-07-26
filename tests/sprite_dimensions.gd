extends Node2D
## Every sprite class at true scale: frame canvas (outline) and body (filled).
##
## The frame canvas is deliberately bigger than the body. An attack frame has to
## put the swing somewhere, and if each animation is cropped to its own content
## then every animation has a different frame size, the origin shifts between
## them, and the character jitters as it animates. One canvas per actor class,
## body drawn inside it, feet on a fixed anchor.
##
##     godot --path . tests/screenshot.tscn -- --scene=res://tests/sprite_dimensions.tscn --shot=/tmp/dims.png

const DEMO: Texture2D = preload("res://art/sprites/scale_demo_64x96.png")

## label, body size, frame canvas size.
const CLASSES: Array = [
	["player\nNPCs", Vector2(64, 96), Vector2(128, 128)],
	["humanoid\nenemy", Vector2(64, 96), Vector2(128, 128)],
	["quadruped\nRot Hound", Vector2(96, 64), Vector2(128, 128)],
	["large\nStag, Bloom", Vector2(128, 128), Vector2(192, 192)],
	["boss", Vector2(256, 256), Vector2(320, 320)],
]

const BASELINE: float = 620.0
const INK := Color(0.86, 0.90, 0.76)
const FRAME := Color(0.60, 0.66, 0.52, 0.85)
const BODY := Color(0.38, 0.43, 0.36, 0.9)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.145, 0.152, 0.168), true)

	# 64px tile grid, so every size is readable in tiles as well as pixels.
	var grid_color := Color(1, 1, 1, 0.05)
	for x in range(0, int(view.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, view.y), grid_color, 1.0)
	for y in range(0, int(view.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(view.x, y), grid_color, 1.0)

	draw_string(font, Vector2(20, 30), "sprite dimensions at true scale — grid is 64px tiles",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, Vector2(20, 54), "outline = frame canvas (uniform per class)   filled = body   dot = feet anchor",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.90, 0.76, 0.7))

	var x_cursor := 20.0
	for entry in CLASSES:
		x_cursor = _draw_class(font, x_cursor, entry[0], entry[1], entry[2])

	draw_line(Vector2(0, BASELINE), Vector2(view.x, BASELINE), Color(1, 1, 1, 0.2), 1.0)


func _draw_class(font: Font, x: float, label: String, body: Vector2, frame: Vector2) -> float:
	# Frame sits on the baseline; the body sits inside it with a margin below the
	# feet for shadow and dust.
	var frame_rect := Rect2(x, BASELINE - frame.y, frame.x, frame.y)
	draw_rect(frame_rect, Color(1, 1, 1, 0.04), true)
	draw_rect(frame_rect, FRAME, false, 2.0)

	var floor_margin := (frame.y - body.y) * 0.5
	var feet := Vector2(x + frame.x * 0.5, BASELINE - floor_margin)
	var body_rect := Rect2(feet.x - body.x * 0.5, feet.y - body.y, body.x, body.y)
	draw_rect(body_rect, BODY, true)
	draw_rect(body_rect, Color(0, 0, 0, 0.4), false, 1.0)

	# The 64x96 reference, so one class has something real to be checked against.
	if body == Vector2(64, 96):
		draw_texture(DEMO, Vector2(feet.x - 32.0, feet.y - 96.0))

	draw_circle(feet, 3.0, Color(0.95, 0.78, 0.35))

	var line_y := BASELINE + 24.0
	for line in label.split("\n"):
		draw_string(font, Vector2(x, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
		line_y += 20.0
	draw_string(font, Vector2(x, line_y), "body %dx%d" % [body.x, body.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.86, 0.90, 0.76, 0.8))
	draw_string(font, Vector2(x, line_y + 18.0), "frame %dx%d" % [frame.x, frame.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.80, 0.60, 0.9))

	return x + frame.x + 24.0
