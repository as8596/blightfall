extends CanvasLayer
## Buying and selling. Her shelf on the left, your pack on the right.
##
## An autoload for the same reason `GameMenu` and `Dialogue` are: it has to
## exist in every scene without each one remembering to add it, and a shop is
## not something a level should own.
##
## **It decides nothing.** Every rule about whether a trade can happen lives in
## `Shops`, and this window's entire job is to show two lists and forward a
## click. That split is why the trade rules can be tested without a viewport,
## and it is why a refusal here is always a sentence somebody wrote rather than
## a button that mysteriously does nothing.
##
## ## Why two lists and not a grid
##
## The pack is already a grid behind Tab, and copying it here would mean the
## player reads a 42-slot grid to find the one loaf they meant to sell. A shop
## is a list of *prices*, and a price needs a row: name on the left, number on
## the right, aligned down the column so two of them can be compared without
## moving your eyes horizontally. That is the whole reason this looks like a
## ledger and the inventory looks like a bag.

const LAYER: int = 107

## Above `Dialogue` (106), because a shop is opened *from* a conversation and
## has to cover it. Below `GameMenu` (108) and `PauseMenu` (110), because both
## of those are ways out and a way out that draws underneath is a trap.
const ROW := 44
const ICON := 32
const MARGIN := 64.0

const BACK := Color(0.05, 0.04, 0.04, 0.88)
const PANEL_FILL := Color(0.09, 0.08, 0.08)
const PANEL_EDGE := Color(0.32, 0.27, 0.20)
const ROW_FILL := Color(0.13, 0.12, 0.11)
const ROW_HOVER := Color(0.20, 0.18, 0.14)
const ROW_DEAD := Color(0.10, 0.09, 0.09)
const GOLD := Color(0.86, 0.72, 0.36)
const TEXT := Color(0.92, 0.88, 0.80)
const DIM := Color(0.54, 0.50, 0.45)
const REFUSED := Color(0.78, 0.48, 0.42)

var _open: bool = false
var _shop: ShopData
var _root: Control
var _title: Label
var _greeting: Label
var _gold: Label
var _buy_rows: VBoxContainer
var _sell_rows: VBoxContainer
var _note: Label
var _note_colour: Color = DIM

## Cleared on the next successful trade, so a refusal does not sit on screen
## looking like it applies to the thing you just did.
var _said: String = ""


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Dialogue.action_chosen.connect(_on_dialogue_action)
	Purse.changed.connect(func(_amount: int) -> void:
		if _open:
			_refresh())


func is_open() -> bool:
	return _open


## The seam from the conversation. A choice marked `"action": "shop"` names its
## shop in the same object; anything else is somebody else's action.
func _on_dialogue_action(action: StringName, params: Dictionary) -> void:
	if action != &"shop":
		return
	var id := StringName(String(params.get("shop", "")))
	if id == &"":
		push_warning("ShopMenu: a 'shop' action named no shop.")
		return
	# Deferred so the dialogue box finishes closing first. Opening on top of a
	# box that is still tearing down leaves its replies drawn over the shelf.
	open.call_deferred(id)


func open(id: StringName) -> bool:
	if _open or PauseMenu.is_open() or GameMenu.is_open():
		return false
	var shop := Shops.get_shop(id)
	if shop == null:
		push_warning("ShopMenu: no shop '%s'." % id)
		return false
	_shop = shop
	_said = ""
	_open = true
	_refresh()
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	Events.shop_opened.emit(id)
	return true


func close() -> void:
	if not _open:
		return
	var id := _shop.id if _shop != null else &""
	_open = false
	_root.visible = false
	_shop = null
	# Only give time back if nothing else wants it stopped — same rule as
	# `GameMenu.close`, and for the same reason.
	if not PauseMenu.is_open() and not GameMenu.is_open() and not Dialogue.is_open():
		get_tree().paused = false
		Hud.enabled = true
	Events.shop_closed.emit(id)


## `_input` rather than `_unhandled_input`: Escape is also `ui_cancel`, and once
## a Control in here has focus the UI system eats it before unhandled input is
## reached — which would leave the shop as a room with no door. Same fix as
## `GameMenu`.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"open_menu"):
		close()
		get_viewport().set_input_as_handled()


func _pack() -> ItemsComponent:
	return _player().items if _player() != null else null


func _sack() -> InventoryComponent:
	return _player().inventory if _player() != null else null


func _player() -> Player:
	var scene := get_tree().current_scene
	return scene.get("player") as Player if scene != null else null


# ------------------------------------------------------------------ trading

func _on_buy(item: ItemData) -> void:
	var refusal := Shops.buy(_shop, item, _pack())
	if refusal != "":
		_say(refusal, REFUSED)
	else:
		_say("Bought %s. %d gold." % [item.display_name, _shop.price_of(item)], DIM)
	_refresh()


func _on_sell(slot: int) -> void:
	var pack := _pack()
	var item := pack.item_at(slot) if pack != null else null
	if item == null:
		return
	# Read the payment before the sale: afterwards the slot may be empty, and
	# reporting "sold for 0" is worse than not reporting at all.
	var paid := _shop.offer_for(item)
	var refusal := Shops.sell(_shop, pack, slot)
	if refusal != "":
		_say(refusal, REFUSED)
	else:
		_say("Sold %s. %d gold." % [item.display_name, paid], DIM)
	_refresh()


func _on_sell_material(id: StringName, amount: int) -> void:
	var each := _shop.offer_for_material(id)
	var sack := _sack()
	var selling := mini(amount, sack.count_of(id)) if sack != null else 0
	var refusal := Shops.sell_material(_shop, sack, id, amount)
	if refusal != "":
		_say(refusal, REFUSED)
	else:
		_say("Sold %d %s. %d gold." % [selling, Materials.name_of(id).to_lower(),
			each * selling], DIM)
	_refresh()


func _say(text: String, colour: Color) -> void:
	_said = text
	_note_colour = colour


# ------------------------------------------------------------------ drawing

func _refresh() -> void:
	if _shop == null:
		return
	_title.text = _shop.display_name
	_greeting.text = _shop.greeting
	_gold.text = "%d gold" % Purse.amount()
	_note.text = _said if _said != "" else \
		"Click to buy. Click something of yours to sell — shift-click sells the stack."
	_note.add_theme_color_override("font_color", _note_colour if _said != "" else DIM)
	_fill_buy()
	_fill_sell()


func _fill_buy() -> void:
	_clear(_buy_rows)
	for item in _shop.stock:
		if item == null:
			continue
		var price := _shop.price_of(item)
		var affordable := Shops.why_not_buy(_shop, item, _pack()) == ""
		_buy_rows.add_child(_row(item, price, affordable, _on_buy.bind(item)))
	if _buy_rows.get_child_count() == 0:
		_buy_rows.add_child(_empty("Shelves are bare."))


## The pack, read from `Hud`'s cache rather than off the player.
##
## `Hud` holds the last `Events.player_items_changed`, and `GameMenu` draws its
## grid from exactly the same two arrays — so the shop and the inventory can
## never disagree about what you are carrying.
##
## Fetching the player worked and was still wrong, and it announced itself the
## first time this was screenshotted: the harness parents the level under
## itself, so `current_scene` is the harness, `get("player")` was null, and the
## sell column rendered "Nothing to sell." for a player holding bread.
func _fill_sell() -> void:
	_clear(_sell_rows)

	# Satchel first. It is the bulk of what comes home from a run, it is worth
	# far more than anything in the pack, and putting it second would bury the
	# reason to be standing here under a list of half-eaten meals.
	var haul := Materials.sorted(Hud.materials)
	if not haul.is_empty() and _shop.buys_materials:
		_sell_rows.add_child(_group("Satchel"))
		for id in haul:
			var held: int = int(Hud.materials[id])
			var each := _shop.offer_for_material(id)
			_sell_rows.add_child(_material_row(id, held, each))

	# The pack, built aside first so its heading can be skipped when there is
	# nothing under it. A "Pack" label above empty space reads as a bug.
	var carried: Array[Control] = []
	for slot in Hud.slot_items.size():
		var item: ItemData = Hud.slot_items[slot] if Hud.slot_items[slot] is ItemData else null
		if item == null:
			continue
		var offer := _shop.offer_for(item)
		var wanted := Shops.why_not_sell(_shop, item) == ""
		var held: int = int(Hud.slot_counts[slot]) if slot < Hud.slot_counts.size() else 1
		carried.append(_row(item, offer, wanted, _on_sell.bind(slot), held))

	if not carried.is_empty():
		# Only worth a heading when there is a satchel section above it to be
		# told apart from.
		if _sell_rows.get_child_count() > 0:
			_sell_rows.add_child(_group("Pack"))
		for row in carried:
			_sell_rows.add_child(row)

	if _sell_rows.get_child_count() == 0:
		_sell_rows.add_child(_empty("You are carrying nothing she wants."))


## One line of the ledger: icon, name, price. `live` is whether the click will
## do anything — a dead row is dimmed and still says its price, because "this
## costs more than you have" is information and a hidden row is not.
func _row(item: ItemData, price: int, live: bool, on_click: Callable,
		held: int = 0) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, ROW)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UiKit.frame(ROW_FILL if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0))

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8.0
	line.offset_right = -10.0
	line.add_theme_constant_override("separation", 10)
	line.alignment = BoxContainer.ALIGNMENT_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color.WHITE if live else Color(0.5, 0.48, 0.45)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)

	var name_label := Label.new()
	name_label.text = item.display_name if held <= 1 else "%s  x%d" % [item.display_name, held]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	name_label.add_theme_color_override("font_color", TEXT if live else DIM)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d" % price if price > 0 else "—"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.custom_minimum_size = Vector2(56, 0)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_theme_font_override("font", UiKit.DISPLAY)
	cost.add_theme_font_size_override("font_size", TypeScale.SMALL)
	cost.add_theme_color_override("font_color", GOLD if live else DIM)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cost)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", UiKit.frame(
			ROW_HOVER if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0)))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", UiKit.frame(
			ROW_FILL if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0)))
	return panel


## A satchel line. Reads "Timber x7" with what one is worth on the right, the
## same as every other row — the price column always means *per one*, so the two
## halves of the ledger can be compared without a footnote.
##
## Left click sells one, **shift-click sells the lot.** Selling twelve timber
## one click at a time is the kind of thing that makes a player stop selling
## timber, and a second button per row would double the width of the column.
func _material_row(id: StringName, held: int, each: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, ROW)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UiKit.frame(ROW_FILL, Color(0, 0, 0, 0), 0, 0))

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8.0
	line.offset_right = -10.0
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.texture = Materials.icon_of(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s  x%d" % [Materials.name_of(id), held]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	name_label.add_theme_color_override("font_color", TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d" % each
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.custom_minimum_size = Vector2(56, 0)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_theme_font_override("font", UiKit.DISPLAY)
	cost.add_theme_font_size_override("font_size", TypeScale.SMALL)
	cost.add_theme_color_override("font_color", GOLD)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cost)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_on_sell_material(id, held if click.shift_pressed else 1))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel",
			UiKit.frame(ROW_HOVER, Color(0, 0, 0, 0), 0, 0)))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel",
			UiKit.frame(ROW_FILL, Color(0, 0, 0, 0), 0, 0)))
	return panel


## A heading inside a column, for when one column holds two kinds of thing.
func _group(text: String) -> Control:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UiKit.DISPLAY)
	label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	label.add_theme_color_override("font_color", Color(0.52, 0.47, 0.40))
	return label


func _empty(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	label.add_theme_color_override("font_color", DIM)
	return label


static func _clear(box: Container) -> void:
	for child in box.get_children():
		child.queue_free()
		box.remove_child(child)


func _build() -> void:
	_root = Control.new()
	_root.name = "ShopMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	UiScale.register(self, _root)

	var scrim := ColorRect.new()
	scrim.color = BACK
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = MARGIN
	frame.offset_top = MARGIN
	frame.offset_right = -MARGIN
	frame.offset_bottom = -MARGIN
	frame.add_theme_stylebox_override("panel", UiKit.frame(PANEL_FILL, PANEL_EDGE, 18))
	_root.add_child(frame)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	frame.add_child(page)

	# Header: who this is, what she says, and what you have. The gold sits on
	# the same line as her name because it is the number every decision on this
	# screen is measured against.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)

	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", 2)
	header.add_child(who)

	_title = Label.new()
	_title.add_theme_font_override("font", UiKit.DISPLAY)
	_title.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_title.add_theme_color_override("font_color", UiKit.HEADING)
	who.add_child(_title)

	_greeting = Label.new()
	_greeting.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_greeting.add_theme_color_override("font_color", DIM)
	who.add_child(_greeting)

	_gold = Label.new()
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold.add_theme_font_override("font", UiKit.DISPLAY)
	_gold.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_gold.add_theme_color_override("font_color", GOLD)
	header.add_child(_gold)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	_buy_rows = _column(columns, "For sale", "What she has")
	# "Yours" rather than "Your pack": it holds the satchel as well, and the two
	# are labelled separately inside it.
	_sell_rows = _column(columns, "Yours", "What she'll take off you")

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_note.add_theme_color_override("font_color", DIM)
	page.add_child(_note)

	var leave := Label.new()
	leave.text = "Esc to leave"
	leave.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	leave.add_theme_font_size_override("font_size", TypeScale.SMALL)
	leave.add_theme_color_override("font_color", Color(0.44, 0.41, 0.37))
	page.add_child(leave)


## One titled, scrolling column. Scrolling because the pack has forty-two slots
## and a full one would otherwise push the footer off the bottom of the screen.
func _column(parent: Container, title: String, tip: String) -> VBoxContainer:
	var column := UiKit.framed(title, tip)
	var frame := UiKit.frame_of(column)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	return rows
