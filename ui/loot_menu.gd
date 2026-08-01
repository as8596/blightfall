extends CanvasLayer
## What is left on the body, as a grid you take things out of.
##
## **Searching used to be a keypress that emptied the pile into your bags.** One
## button, everything moved, and a line of toast to say what had happened. That
## is fine when the pile is two hides, and wrong the moment it is not: with a
## full pack you found out what you had left behind by reading a message that
## had already scrolled, and there was no way to take the fang and leave the
## rags.
##
## So: the same shape as the trade window (`ui/shop_menu.gd`), because it is the
## same question — a grid of things, click one to move it, a line underneath
## saying what the pointer is on. Learning one of these two windows should teach
## you the other.
##
## It is *smaller* than the shop on purpose. A shop is a decision with a budget
## and three columns; a body is a short list and the only question is what you
## have room for.

## Above the HUD (64) and below the pause menu (110), alongside the shop (107).
## A pile searched with the pause menu already up would be unreachable anyway —
## `open` refuses in that case — so the ordering only has to beat the HUD.
const LAYER: int = 106

## Same metrics as the shop's grid, which is the point: two windows that show a
## row of things you can click should show them at the same size.
const SLOT := 56
const ICON := 40
const COLUMNS := 5
const WIDTH := 560.0

const BACK := Color(0.05, 0.04, 0.04, 0.88)
const PANEL_FILL := Color(0.09, 0.08, 0.08)
const PANEL_EDGE := Color(0.32, 0.27, 0.20)
const ROW_FILL := Color(0.13, 0.12, 0.11)
const ROW_HOVER := Color(0.20, 0.18, 0.14)
const GOLD := Color(0.86, 0.72, 0.36)
const TEXT := Color(0.92, 0.88, 0.80)
const DIM := Color(0.54, 0.50, 0.45)
const REFUSED := Color(0.78, 0.48, 0.42)
const SLOT_EDGE := Color(0.30, 0.26, 0.20)
const SLOT_EDGE_HOT := Color(0.72, 0.61, 0.39)

var _open: bool = false
var _pile: LootPile
var _actor: Node

var _root: Control
var _rows: GridContainer
var _detail: Label
var _note: Label
var _take_all: Button


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


## Show a pile. False if it cannot be shown, which is the caller's cue to fall
## back to taking everything — see `LootPile.interact`.
func open(pile: LootPile, actor: Node) -> bool:
	if _open or pile == null or actor == null:
		return false
	if PauseMenu.is_open() or GameMenu.is_open() or ShopMenu.is_open() or Dialogue.is_open():
		return false
	_pile = pile
	_actor = actor
	_note.text = ""
	_open = true
	_refresh()
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	# Emptied piles go away here rather than inside `take`, so a pile cannot be
	# freed out from under the window that is drawing it.
	if is_instance_valid(_pile):
		_pile.retire()
	_pile = null
	_actor = null
	# Same rule as `GameMenu.close`: only give time back if nothing else wants
	# it stopped.
	if not PauseMenu.is_open() and not GameMenu.is_open() and not Dialogue.is_open():
		get_tree().paused = false
		Hud.enabled = true


## `_input` rather than `_unhandled_input`, for the reason in `ShopMenu`: once a
## Button in here has focus it eats `ui_cancel` before unhandled input runs, and
## a window with no way out is worse than no window.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"open_menu"):
		close()
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- taking

func _on_take(id: StringName, amount: int) -> void:
	var got := _pile.take(_actor, id, amount)
	if got <= 0:
		# The pack is full, or the satchel is. Said here rather than as a toast
		# because the window is open and the pile is still on screen: the player
		# can see exactly what they did not get.
		_say("No room for that.", REFUSED)
	else:
		Sfx.play(&"ui_select", -8.0)
		_say("Took %s x%d." % [LootPile.name_of(id), got], TEXT)
	_refresh()


func _on_take_gold() -> void:
	var coins := _pile.take_gold()
	if coins <= 0:
		return
	Sfx.play(&"ui_select", -8.0)
	_say("Took %d gold." % coins, GOLD)
	_refresh()


func _on_take_all() -> void:
	var before := _pile.count()
	var coins := _pile.take_gold()
	for id in _pile.contents.keys():
		@warning_ignore("return_value_discarded")
		_pile.take(_actor, id, int(_pile.contents[id]))
	var moved := before - _pile.count()
	if moved <= 0 and coins <= 0:
		_say("No room for any of it.", REFUSED)
	else:
		Sfx.play(&"ui_select", -8.0)
		if _pile.is_empty():
			# Nothing left to decide about, so the window has no reason to stay.
			close()
			return
		_say("No room for the rest.", REFUSED)
	_refresh()


func _say(text: String, colour: Color) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", colour)


# ------------------------------------------------------------------ painting

func _refresh() -> void:
	if not is_instance_valid(_pile):
		close()
		return
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)

	for id in LootPile.sorted(_pile.contents):
		var count := int(_pile.contents[id])
		var icon := LootPile.icon_of(id)
		# An id with no icon still has to be a slot you can see and click. It
		# means a loot table naming something that has no art yet — a blank panel
		# reads as a bug in the window rather than as a gap in the data, and it
		# cannot be taken because there is nothing to point at.
		var face := "" if icon != null else String(id).substr(0, 4)
		_rows.add_child(_slot(icon, LootPile.name_of(id), count,
			func(amount: int) -> void: _on_take(id, amount), face))

	if _pile.gold > 0:
		# Coins have no icon, so the number is the picture. Its own slot rather
		# than a line elsewhere, because it is one more thing on the body and
		# splitting it out would make it one more thing to notice.
		_rows.add_child(_slot(null, "Coins", _pile.gold,
			func(_amount: int) -> void: _on_take_gold(), "%d" % _pile.gold, GOLD))

	if _rows.get_child_count() == 0:
		_rows.add_child(_empty("Picked clean."))
	_take_all.disabled = _pile.is_empty()
	_detail.text = ""


func _slot(icon_texture: Texture2D, label: String, count: int,
		on_click: Callable, face: String = "", face_colour: Color = TEXT) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SLOT, SLOT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiKit.frame(ROW_FILL, SLOT_EDGE, 0, 1))

	if icon_texture != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var inset := float(SLOT - ICON) * 0.5
		icon.offset_left = inset
		icon.offset_top = inset - 3.0
		icon.offset_right = -inset
		icon.offset_bottom = -inset - 3.0
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
	elif face != "":
		var text := Label.new()
		text.text = face
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.add_theme_font_override("font", UiKit.DISPLAY)
		text.add_theme_font_size_override("font_size", TypeScale.SMALL)
		text.add_theme_color_override("font_color", face_colour)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(text)

	if count > 1 and face == "":
		var tally := Label.new()
		tally.text = "%d" % count
		tally.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		tally.offset_left = -SLOT
		tally.offset_top = -16.0
		tally.offset_right = -3.0
		tally.offset_bottom = 0.0
		tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tally.add_theme_font_size_override("font_size", TypeScale.TINY)
		tally.add_theme_color_override("font_color", TEXT)
		tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tally)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(count))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", UiKit.frame(ROW_HOVER, SLOT_EDGE_HOT, 0, 1))
		_detail.text = label if count <= 1 else "%s x%d" % [label, count])
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", UiKit.frame(ROW_FILL, SLOT_EDGE, 0, 1))
		_detail.text = "")
	return panel


func _empty(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	label.add_theme_color_override("font_color", DIM)
	return label


# ------------------------------------------------------------------ building

func _build() -> void:
	_root = Control.new()
	_root.name = "LootMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	UiScale.register(self, _root, true)

	var scrim := ColorRect.new()
	scrim.color = BACK
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	# Sized to its contents and centred, same as the shop. A body with two
	# things on it drawing a panel to the bottom of a 1440p screen reads as a
	# layout fault rather than as a small pile.
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	frame.add_theme_stylebox_override("panel", UiKit.frame(PANEL_FILL, PANEL_EDGE, 16))
	_root.add_child(frame)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	frame.add_child(page)

	var title := Label.new()
	title.text = "SEARCH"
	title.add_theme_font_override("font", UiKit.DISPLAY)
	title.add_theme_font_size_override("font_size", TypeScale.SMALL)
	title.add_theme_color_override("font_color", UiKit.HEADING)
	page.add_child(title)

	_rows = GridContainer.new()
	_rows.columns = COLUMNS
	_rows.add_theme_constant_override("h_separation", 4)
	_rows.add_theme_constant_override("v_separation", 4)
	page.add_child(_rows)

	# What the pointer is on. One line under the grid rather than a bubble beside
	# it: the window is small enough that the eye does not have to travel, and a
	# floating panel over a five-slot grid would cover the grid.
	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(0, 20)
	_detail.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_detail.add_theme_color_override("font_color", TEXT)
	page.add_child(_detail)

	_note = Label.new()
	_note.custom_minimum_size = Vector2(0, 20)
	_note.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_note.add_theme_color_override("font_color", DIM)
	page.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	page.add_child(buttons)

	_take_all = Button.new()
	_take_all.text = "Take all"
	_take_all.custom_minimum_size = Vector2(160, 36)
	_take_all.add_theme_font_size_override("font_size", TypeScale.SMALL)
	UiKit.dress_button(_take_all)
	_take_all.pressed.connect(_on_take_all)
	buttons.add_child(_take_all)

	var leave := Button.new()
	leave.text = "Leave it"
	leave.custom_minimum_size = Vector2(160, 36)
	leave.add_theme_font_size_override("font_size", TypeScale.SMALL)
	UiKit.dress_button(leave)
	leave.pressed.connect(close)
	buttons.add_child(leave)
