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


# ------------------------------------------------------------ item detail

## Colours for the BBCode helpers below. Hex strings rather than `Color`,
## because `[color=...]` takes text.
const KEY := "b79a63"      ## labels and item names — warm, a step up from body
const ASIDE := "8a8378"    ## flavour text, parentheticals, "nothing here"
const KIND := "6e695f"     ## the category aside, dimmer than even flavour
const DISPLAY_PATH := "res://art/fonts/ui_display.tres"


## An item's name, in the display face. `[font]` takes a path rather than a
## resource, which is why that is a string constant and not `DISPLAY`.
static func named(text: String) -> String:
	return "[font=%s][color=%s]%s[/color][/font]" % [DISPLAY_PATH, KEY, text]


static func aside(text: String) -> String:
	return "[color=%s]%s[/color]" % [ASIDE, text]


## The item's category, set apart from its name.
##
## **`[i]` is not available and would do nothing.** `art/fonts/ui_theme.tres`
## points italics at the regular face on purpose: Godot has no italic to use, so
## it shears the glyphs, and a sheared pixel font stops having whole-pixel
## strokes — the one thing the whole font depends on.
##
## So the two axes that do exist carry it: an asterisk to mark it as an aside
## rather than part of the name, and a dimmer colour than even flavour text.
static func kind(text: String) -> String:
	return "[color=%s]*%s[/color]" % [KIND, text]


## Everything worth knowing about an item, as BBCode.
##
## Shared so the shop and the inventory cannot describe the same loaf
## differently — which they already would have, because the shop needed this
## and the only copy lived on `GameMenu` behind an underscore.
static func item_detail(item: ItemData, extra: String = "") -> String:
	if item == null:
		return "\n  " + aside("Nothing there.")
	const KINDS := ["Consumable", "Tool", "Key", "Gear"]
	var label: String = KINDS[item.kind] if item.kind < KINDS.size() else "?"
	var lines: Array[String] = ["", "  %s    %s" % [named(item.display_name), kind(label)]]
	if extra != "":
		lines.append("  " + extra)
	if item.heals > 0:
		lines.append("  Restores %d health." % item.heals)
	if item.kind == ItemData.Kind.TOOL:
		lines.append("  Used with the tool key.")
	if item.kind == ItemData.Kind.KEY:
		lines.append("  Not something you use. It opens something.")
	if item.stack_size > 1:
		lines.append("  Stacks to %d." % item.stack_size)
	if item.is_equippable():
		lines.append("  Worn in the %s slot." % ItemData.slot_name(item.slot).to_lower())
	for stat in item.modifiers:
		var delta: int = int(item.modifiers[stat])
		lines.append("  %s %s%d" % [String(stat).capitalize().replace("_", " "),
			"+" if delta >= 0 else "", delta])
	if not item.description.is_empty():
		lines.append("")
		lines.append("  " + aside(item.description))
	return "\n".join(lines)


static func frame(fill: Color, edge: Color, pad: int = 0, width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	if pad > 0:
		box.set_content_margin_all(pad)
	return box


# ---------------------------------------------------------------- steel plates
#
# The imported border set (`tools/import_ui_borders.py`), drawn in immediate
# mode. The HUD paints itself with `draw_*` calls rather than assembling
# Controls, so a `NinePatchRect` node is no use to it — these do the same job
# as a function.

const SLOT_PLATE: Texture2D = preload("res://art/ui/slot.png")
const TROUGH: Texture2D = preload("res://art/ui/trough.png")
const KEY_E: Texture2D = preload("res://art/ui/key_e.png")

## How much of each end of `trough.png` is the rounded cap rather than the
## stretchable middle. Measured off the art: the cap is the domed end and the
## bar is uniform between them.
const TROUGH_CAP: float = 16.0


## Draw `texture` into `into`, stretching only the middle and leaving `cap`
## pixels at each end at their own size.
##
## **Not a plain `draw_texture_rect`.** Stretching a 326px bar down to 232 pulls
## the domed caps into ovals, and stretching it up to 1100 for a shop row turns
## them into slugs. A three-slice keeps the ends the shape they were drawn and
## puts every pixel of the difference into the flat middle, which is the part
## that has nothing to lose.
static func three_slice_h(canvas: CanvasItem, texture: Texture2D, into: Rect2,
		cap: float, modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var source := texture.get_size()
	# A target narrower than its own two caps has no middle to stretch; draw it
	# whole rather than drawing the caps overlapping each other.
	if into.size.x <= cap * 2.0 or source.x <= cap * 2.0:
		canvas.draw_texture_rect(texture, into, false, modulate)
		return
	var left := Rect2(Vector2.ZERO, Vector2(cap, source.y))
	var right := Rect2(Vector2(source.x - cap, 0.0), Vector2(cap, source.y))
	var middle := Rect2(Vector2(cap, 0.0), Vector2(source.x - cap * 2.0, source.y))
	canvas.draw_texture_rect_region(texture,
		Rect2(into.position, Vector2(cap, into.size.y)), left, modulate)
	canvas.draw_texture_rect_region(texture,
		Rect2(into.position + Vector2(into.size.x - cap, 0.0),
			Vector2(cap, into.size.y)), right, modulate)
	canvas.draw_texture_rect_region(texture,
		Rect2(into.position + Vector2(cap, 0.0),
			Vector2(into.size.x - cap * 2.0, into.size.y)), middle, modulate)
