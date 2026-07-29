extends Control
## Draw the UI font at a range of sizes, for judging whether text is crisp.
##
##     xvfb-run -a godot --path . tests/font_sheet.tscn -- --shot=/tmp/font.png
##
## Pixel fonts are the whole reason this exists. They are drawn on a grid and
## rasterising them off it — with antialiasing, with hinting, or at a size that
## is not a multiple of the grid — turns crisp strokes into grey mush, and the
## damage is invisible in a code review and obvious on screen.

const SIZES: Array[int] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48]
const SAMPLE := "Hamburgefonstiv 0123 — the valley remembers"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture.call_deferred()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.07, 0.08))
	var y := 30.0
	for s in SIZES:
		draw_string(font, Vector2(16, y), "%2d  %s" % [s, SAMPLE],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, s, Color(0.95, 0.92, 0.85))
		y += s + 22.0


func _capture() -> void:
	var out := "user://font.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			out = arg.trim_prefix("--shot=")
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	@warning_ignore("return_value_discarded")
	image.save_png(out)
	print("font sheet: %s" % out)
	get_tree().quit()
