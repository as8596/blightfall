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
	panel.add_theme_stylebox_override("panel", panel_box())

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


## Where the recessed channel sits inside `trough.png`, measured off the art.
##
## **Horizontal is in pixels and vertical is a fraction**, and that asymmetry is
## not an oversight — it is what `three_slice_h` does. The domed caps keep their
## own size however wide the trough is drawn, so the channel starts a fixed
## number of pixels in from each end. Vertically the whole thing stretches, so
## the channel keeps its share.
##
## Getting this wrong is what put the first health bar *over* its trough instead
## of in it: the bar was given an arbitrary four-pixel inset, the trough's rim is
## thicker than that, and the fill covered the rim on all four sides.
const TROUGH_CHANNEL_LEFT: float = 15.0
const TROUGH_CHANNEL_RIGHT: float = 14.0
const TROUGH_CHANNEL_TOP: float = 10.0 / 38.0
const TROUGH_CHANNEL_HEIGHT: float = 19.0 / 38.0


## The trough to draw so its channel lands exactly on `bar`.
##
## Callers size the *bar*, because the bar is the thing with a meaning — a
## quarter of it is a quarter of your health. The steel around it is then
## whatever it has to be for the two to line up, which is arithmetic nobody
## should be doing at four call sites.
static func trough_for(bar: Rect2) -> Rect2:
	var height := bar.size.y / TROUGH_CHANNEL_HEIGHT
	return Rect2(
		bar.position - Vector2(TROUGH_CHANNEL_LEFT, height * TROUGH_CHANNEL_TOP),
		Vector2(bar.size.x + TROUGH_CHANNEL_LEFT + TROUGH_CHANNEL_RIGHT, height))


## Draw the steel trough around `bar`, and nothing else. The bar itself is the
## caller's business — this only ever puts the frame around it.
static func trough(canvas: CanvasItem, bar: Rect2) -> void:
	three_slice_h(canvas, TROUGH, trough_for(bar), TROUGH_CAP)


# ----------------------------------------------------------- panels and buttons

const PANEL_FRAME: Texture2D = preload("res://art/ui/panel.png")
const BUTTON_PLATE: Texture2D = preload("res://art/ui/button.png")

## Where the panel frame's corner ornaments end. Must match `FRAME_CORNER` in
## `tools/import_ui_borders.py` — that is the tool's promise about what it left
## untouched, and this is the code cashing it in.
const PANEL_CORNER: int = 48

## The rounded caps on the button plate, and enough of its top and bottom to
## keep the corners from being stretched into ramps.
const BUTTON_CAP_X: int = 34
const BUTTON_CAP_Y: int = 20


## The steel frame, as a nine-patch, with `pad` pixels of breathing room inside.
##
## **The middle of the art is transparent**, so this frames whatever is behind it
## rather than covering it. That is deliberate: every one of these sits on the
## menu's own scrim, and a panel that painted its own dark rectangle would put a
## second, slightly different dark on top of the first.
static func panel_box(pad: int = 3) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = PANEL_FRAME
	box.texture_margin_left = PANEL_CORNER
	box.texture_margin_right = PANEL_CORNER
	box.texture_margin_top = PANEL_CORNER
	box.texture_margin_bottom = PANEL_CORNER
	# Inside the steel, not inside the texture. The band is 29px of which the
	# outer few are bevel and shadow, so 26 clears the part that reads as metal
	# and `pad` is breathing room on top.
	#
	# **This is a budget, not a preference.** Every panel spends twice this on
	# width, and there are three of them across the inventory — the first go at
	# 14px of padding put the right-hand column off the side of the screen. See
	# the arithmetic in `ui/game_menu.gd`.
	var inset := 26 + pad
	box.content_margin_left = inset
	box.content_margin_right = inset
	# More at the top: the band is thickest there, and a heading set to the same
	# inset as the sides came out resting on the steel rather than under it.
	box.content_margin_top = inset + 14
	box.content_margin_bottom = inset
	return box


## The button plate. `tint` is how the three states are told apart — the art has
## one plate and recolouring it is cheaper and steadier than three near-identical
## textures that can drift apart.
static func button_box(tint: Color = Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = BUTTON_PLATE
	box.texture_margin_left = BUTTON_CAP_X
	box.texture_margin_right = BUTTON_CAP_X
	box.texture_margin_top = BUTTON_CAP_Y
	box.texture_margin_bottom = BUTTON_CAP_Y
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.modulate_color = tint
	return box


## Dress a `Button` in the plate, in all four states it can be in.
##
## One call rather than eight lines at each of the five places a button is made.
## The states are the same plate at different brightness: normal, a lift on
## hover, a press that goes *darker* because a pressed plate is one you have
## pushed into its recess, and a disabled one that loses its colour rather than
## just its edge.
static func dress_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_box())
	button.add_theme_stylebox_override("hover", button_box(Color(1.18, 1.16, 1.10)))
	button.add_theme_stylebox_override("pressed", button_box(Color(0.78, 0.76, 0.72)))
	button.add_theme_stylebox_override("focus", button_box(Color(1.10, 1.08, 1.04)))
	button.add_theme_stylebox_override("disabled", button_box(Color(0.62, 0.60, 0.58, 0.75)))
	button.add_theme_color_override("font_color", BODY_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1, 0.98, 0.92))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.48))


const BODY_TEXT := Color(0.92, 0.87, 0.77)
