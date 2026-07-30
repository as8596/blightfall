class_name UiKit
extends RefCounted
## The bits of chrome that more than one window draws.
##
## Extracted when the shop window turned out to want the same bordered, titled
## box the character sheet uses. Two copies of a stylebox is how two windows end
## up *nearly* matching — one of them gains a pixel of padding in a hurry and
## nobody notices until a screenshot puts them side by side.
##
## Deliberately small, and deliberately not a theme. Godot themes are the right
## answer for widget defaults and the wrong one for "this game draws boxes like
## this"; a theme would put these colours three inspector levels away from the
## code that reasons about them. `art/fonts/ui_theme.tres` still owns the font
## and the widget defaults, which is the half a theme is good at.

## The warm gold that headings and item names use. Everything else in the
## palette lives with the window that draws it — these are the two that have to
## agree across windows or the game looks like two games.
const HEADING := Color(0.72, 0.61, 0.39)
const DISPLAY: Font = preload("res://art/fonts/ui_display.tres")

const PANEL_FILL := Color(0.11, 0.10, 0.09)
const PANEL_EDGE := Color(0.30, 0.25, 0.19)


## A bordered box with a heading. Returns the *inside*: add children to what
## comes back, and add `frame_of(result)` to your layout.
##
## The frames are what make a page read as regions rather than as a wall of
## boxes — they do the grouping a second font weight would normally do, and this
## project has one weight (`art/fonts/README.md`).
static func framed(title: String, tip: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", frame(PANEL_FILL, PANEL_EDGE, 12))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	if not title.is_empty():
		var heading := Label.new()
		heading.text = title.to_upper()
		heading.tooltip_text = tip
		heading.add_theme_font_override("font", DISPLAY)
		heading.add_theme_font_size_override("font_size", TypeScale.SMALL)
		heading.add_theme_color_override("font_color", HEADING)
		column.add_child(heading)

	# The caller wants the inside; the frame is plumbing. Stash it so a layout
	# can add the panel rather than the column.
	column.set_meta(&"frame", panel)
	return column


static func frame_of(column: Control) -> Control:
	return column.get_meta(&"frame", column)


static func frame(fill: Color, edge: Color, pad: int = 0, width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	if pad > 0:
		box.set_content_margin_all(pad)
	return box
