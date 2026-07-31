extends CanvasLayer
## Buying and selling. Her shelf, your things, and the cart between them.
##
## An autoload for the same reason `GameMenu` and `Dialogue` are: it has to
## exist in every scene without each one remembering to add it, and a shop is
## not something a level should own.
##
## **It decides nothing.** Every rule about whether a trade can happen lives in
## `Shops`, and this window's entire job is to show three lists and forward a
## click. That split is why the trade rules can be tested without a viewport,
## and why a refusal here is always a sentence somebody wrote rather than a
## button that mysteriously does nothing.
##
## ## Why a cart
##
## Buying one thing at a time made every purchase a commitment, so the only
## question worth asking in a shop — *can I afford the stew if I sell the
## timber?* — could only be answered by doing it and hoping. Now the whole trade
## is assembled first, the running total is on screen the entire time, and one
## button makes it real.
##
## **Anything in the cart has already left your side of the window.** Adding
## four timber to the cart takes them out of the "yours" column immediately;
## otherwise the same four could be sold twice and the total would be a lie.
## Nothing has actually moved until Confirm — the column is showing
## `ShopCart.left_of`, not a modified pack.
##
## ## Why lists and not a grid
##
## The pack is already a grid behind Tab, and copying it here would mean reading
## forty-two slots to find the loaf you meant to sell. A shop is a list of
## *prices*, and a price needs a row: name left, number right, aligned down the
## column so two of them can be compared without moving your eyes sideways.

const LAYER: int = 107

## Above `Dialogue` (106), because a shop is opened *from* a conversation and
## has to cover it. Below `GameMenu` (108) and `PauseMenu` (110), because both
## of those are ways out and a way out that draws underneath is a trap.
const ROW := 40
const ICON := 28
## The window is authored against a 1280-wide interface, so this leaves a margin
## either side at the design size and simply centres on anything larger.
const WIDTH := 1120.0
const COLUMNS_TALL := 400.0

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
const CREDIT := Color(0.58, 0.78, 0.52)

var _open: bool = false
var _shop: ShopData
var _cart := ShopCart.new()

var _root: Control
var _title: Label
var _greeting: Label
var _gold: Label
var _buy_rows: VBoxContainer
var _sell_rows: VBoxContainer
var _cart_rows: VBoxContainer
var _detail: RichTextLabel
var _total: Label
var _confirm: Button
var _note: Label
var _note_colour: Color = DIM

## Cleared on the next successful trade, so a refusal does not sit on screen
## looking like it applies to the thing you just did.
var _said: String = ""
## What the pointer is over, so the detail pane has something to describe.
var _hovered: StringName = &""


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
	_hovered = &""
	_cart.clear()
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
	# An abandoned cart is discarded rather than kept. Nothing in it was paid
	# for, so there is nothing to lose, and a shop that remembered a half-made
	# decision from an hour ago would be a shop you had to check.
	_cart.clear()
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


## What the player holds of `id`, read from `Hud`'s cache of the last
## `Events.player_materials_changed` / `player_items_changed` rather than off
## the player. Display reads the bus; only actions fetch.
func _held(id: StringName) -> int:
	if Materials.known(id):
		return int(Hud.materials.get(id, 0))
	var total := 0
	for slot in Hud.slot_items.size():
		var item: ItemData = Hud.slot_items[slot] if Hud.slot_items[slot] is ItemData else null
		if item != null and item.id == id:
			total += int(Hud.slot_counts[slot]) if slot < Hud.slot_counts.size() else 1
	return total


func _player() -> Player:
	var scene := get_tree().current_scene
	return scene.get("player") as Player if scene != null else null


# ------------------------------------------------------------------ the cart

func _on_add_buy(id: StringName, amount: int) -> void:
	_cart.add_buy(id, amount)
	_said = ""
	_refresh()


func _on_add_sell(id: StringName, amount: int, is_material: bool) -> void:
	# Never more than is left. Clicking a line five times when you hold three
	# should stop at three rather than build a cart that cannot settle.
	var spare := _cart.left_of(id, _held(id))
	var taking := mini(amount, spare)
	if taking <= 0:
		return
	if is_material:
		_cart.add_sell_material(id, taking)
	else:
		_cart.add_sell_item(id, taking)
	_said = ""
	_refresh()


## Take a line back out. The cart is the only place a trade can be undone, which
## is most of why it exists.
func _on_unpick(id: StringName, where: String, amount: int) -> void:
	match where:
		"buy": _cart.add_buy(id, -amount)
		"material": _cart.add_sell_material(id, -amount)
		_: _cart.add_sell_item(id, -amount)
	_said = ""
	_refresh()


func _on_confirm() -> void:
	var net := _cart.net(_shop)
	var refusal := Shops.settle(_shop, _cart, _pack(), _sack())
	if refusal != "":
		_say(refusal, REFUSED)
	elif net > 0:
		_say("Paid %d gold." % net, DIM)
	elif net < 0:
		_say("She paid you %d gold." % -net, CREDIT)
	else:
		_say("An even trade.", DIM)
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
	_fill_buy()
	_fill_sell()
	_fill_cart()
	_refresh_total()
	_detail.text = _detail_text()
	_note.text = _said if _said != "" else \
		"Click to add. Shift-click for five. Click a cart line to take it back."
	_note.add_theme_color_override("font_color", _note_colour if _said != "" else DIM)


func _refresh_total() -> void:
	var net := _cart.net(_shop)
	var after := Purse.amount() - net
	if _cart.is_empty():
		_total.text = ""
		_confirm.disabled = true
		_confirm.text = "Nothing to settle"
		return
	var refusal := Shops.why_not_settle(_shop, _cart, _pack(), _sack())
	_confirm.disabled = refusal != ""
	_confirm.text = "Settle up" if refusal == "" else refusal
	if net > 0:
		_total.text = "You pay %d   ·   %d left" % [net, after]
		_total.add_theme_color_override("font_color", GOLD if refusal == "" else REFUSED)
	elif net < 0:
		_total.text = "She pays %d   ·   %d after" % [-net, after]
		_total.add_theme_color_override("font_color", CREDIT)
	else:
		_total.text = "An even trade"
		_total.add_theme_color_override("font_color", DIM)


func _fill_buy() -> void:
	_clear(_buy_rows)
	for item in _shop.stock:
		if item == null:
			continue
		var price := _shop.price_of(item)
		var in_cart := _cart.count_buying(item.id)
		# Affordability is judged against the *whole cart*, not this row alone —
		# a stew you cannot buy on its own is fine if the timber pays for it.
		var live := Purse.amount() + _cart.credit(_shop) >= _cart.cost(_shop) + price
		_buy_rows.add_child(_row(item.icon, item.display_name, price, live,
			item.id, in_cart,
			func(n: int) -> void: _on_add_buy(item.id, n)))
	if _buy_rows.get_child_count() == 0:
		_buy_rows.add_child(_empty("Shelves are bare."))


## Your side. **Counts are what is left after the cart**, so a stack moved
## wholly into it disappears from here — see the class docstring.
func _fill_sell() -> void:
	_clear(_sell_rows)
	var haul: Array[StringName] = []
	if _shop.buys_materials:
		for id in Materials.sorted(Hud.materials):
			if _cart.left_of(id, _held(id)) > 0:
				haul.append(id)
	if not haul.is_empty():
		# Satchel first: it is the bulk of what comes home from a run and worth
		# far more than anything in the pack.
		_sell_rows.add_child(_group("Satchel"))
		for id in haul:
			var left := _cart.left_of(id, _held(id))
			_sell_rows.add_child(_row(Materials.icon_of(id), Materials.name_of(id),
				_shop.offer_for_material(id), true, id, 0,
				func(n: int) -> void: _on_add_sell(id, n, true), left))

	var carried: Array[Control] = []
	var seen := {}
	for slot in Hud.slot_items.size():
		var item: ItemData = Hud.slot_items[slot] if Hud.slot_items[slot] is ItemData else null
		if item == null or seen.has(item.id):
			continue
		seen[item.id] = true
		var left := _cart.left_of(item.id, _held(item.id))
		if left <= 0:
			continue
		var wanted := Shops.why_not_sell(_shop, item) == ""
		carried.append(_row(item.icon, item.display_name, _shop.offer_for(item),
			wanted, item.id, 0,
			func(n: int) -> void: _on_add_sell(item.id, n, false), left))
	if not carried.is_empty():
		if _sell_rows.get_child_count() > 0:
			_sell_rows.add_child(_group("Pack"))
		for row in carried:
			_sell_rows.add_child(row)

	if _sell_rows.get_child_count() == 0:
		_sell_rows.add_child(_empty("Nothing of yours she wants."))


func _fill_cart() -> void:
	_clear(_cart_rows)
	if _cart.is_empty():
		_cart_rows.add_child(_empty("Empty. Click something."))
		return

	if not _cart.buys.is_empty():
		_cart_rows.add_child(_group("Buying"))
		for id in _cart.buys:
			var item := Items.get_item(id)
			var each := _shop.price_of(item)
			var n := int(_cart.buys[id])
			_cart_rows.add_child(_row(item.icon, item.display_name, each * n, true,
				id, 0, func(taking: int) -> void: _on_unpick(id, "buy", taking), n))

	var selling := not _cart.sell_materials.is_empty() or not _cart.sell_items.is_empty()
	if selling:
		_cart_rows.add_child(_group("Selling"))
	for id in _cart.sell_materials:
		var n := int(_cart.sell_materials[id])
		_cart_rows.add_child(_row(Materials.icon_of(id), Materials.name_of(id),
			_shop.offer_for_material(id) * n, true, id, 0,
			func(taking: int) -> void: _on_unpick(id, "material", taking), n, CREDIT))
	for id in _cart.sell_items:
		var item := Items.get_item(id)
		var n := int(_cart.sell_items[id])
		_cart_rows.add_child(_row(item.icon, item.display_name,
			_shop.offer_for(item) * n, true, id, 0,
			func(taking: int) -> void: _on_unpick(id, "item", taking), n, CREDIT))


func _detail_text() -> String:
	if _hovered == &"":
		return "\n  " + UiKit.aside("Point at something to read it.")
	if Materials.known(_hovered):
		return "\n  %s    %s\n  %s" % [
			UiKit.named(Materials.name_of(_hovered)), UiKit.kind("Material"),
			UiKit.aside("What the town is rebuilt out of. She pays %d each."
				% _shop.offer_for_material(_hovered))]
	var item := Items.get_item(_hovered)
	if item == null:
		return "\n  " + UiKit.aside("Point at something to read it.")
	# The price line goes first, because in a shop it is the fact the other
	# facts are being weighed against.
	var money := "She sells it for %d." % _shop.price_of(item) if _shop.sells(_hovered) \
		else "She pays %d for it." % _shop.offer_for(item)
	return UiKit.item_detail(item, money)


## One line of the ledger: icon, name, price. `live` is whether the click will
## do anything — a dead row is dimmed and still shows its price, because "this
## costs more than you have" is information and a hidden row is not.
##
## `held` appends "x3" to the name; `in_cart` appends "(2 in cart)". They are
## separate because a buy row has no holding and a sell row has both.
func _row(icon_texture: Texture2D, label: String, price: int, live: bool,
		id: StringName, in_cart: int, on_click: Callable, held: int = 0,
		price_colour: Color = GOLD) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, ROW)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UiKit.frame(ROW_FILL if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0))

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8.0
	line.offset_right = -10.0
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.texture = icon_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color.WHITE if live else Color(0.5, 0.48, 0.45)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)

	var text := label
	if held > 1:
		text += "  x%d" % held
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	name_label.add_theme_color_override("font_color", TEXT if live else DIM)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	if in_cart > 0:
		var pending := Label.new()
		pending.text = "%d in cart" % in_cart
		pending.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pending.add_theme_font_size_override("font_size", TypeScale.SMALL)
		pending.add_theme_color_override("font_color", Color(0.60, 0.55, 0.40))
		pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(pending)

	var cost := Label.new()
	cost.text = "%d" % price if price > 0 else "—"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.custom_minimum_size = Vector2(52, 0)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_theme_font_override("font", UiKit.DISPLAY)
	cost.add_theme_font_size_override("font_size", TypeScale.SMALL)
	cost.add_theme_color_override("font_color", price_colour if live else DIM)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cost)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(5 if click.shift_pressed else 1))
	panel.mouse_entered.connect(func() -> void:
		_hovered = id
		panel.add_theme_stylebox_override("panel", UiKit.frame(
			ROW_HOVER if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0))
		_detail.text = _detail_text())
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", UiKit.frame(
			ROW_FILL if live else ROW_DEAD, Color(0, 0, 0, 0), 0, 0)))
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

	# Sized to its content and centred, rather than stretched to the window.
	# Full-rect left a shop with nine lines in it drawing three columns of empty
	# panel down to the bottom of a 1440p screen, which reads as a layout fault
	# rather than as a small shop.
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

	# A fixed height rather than expand-to-fill: three columns that grow with the
	# window are three columns that are mostly empty on a big one. This is deep
	# enough for nine lines, and each column scrolls past that.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.custom_minimum_size = Vector2(0, COLUMNS_TALL)
	page.add_child(columns)

	_buy_rows = _column(columns, "For sale", "What she has")
	_sell_rows = _column(columns, "Yours", "What she'll take off you")
	_cart_rows = _column(columns, "Cart", "Nothing here is paid for yet")

	# The detail pane spans the full width under the columns rather than sitting
	# in one of them: it describes whichever list the pointer is in, and a pane
	# that lived in a column would look like it belonged to that column.
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.custom_minimum_size = Vector2(0, 96)
	_detail.add_theme_font_size_override("normal_font_size", TypeScale.SMALL)
	_detail.add_theme_color_override("default_color", TEXT)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_detail)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	page.add_child(footer)

	_note = Label.new()
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_note.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_note.add_theme_color_override("font_color", DIM)
	footer.add_child(_note)

	_total = Label.new()
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_total.add_theme_font_override("font", UiKit.DISPLAY)
	_total.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_total.add_theme_color_override("font_color", GOLD)
	footer.add_child(_total)

	_confirm = Button.new()
	_confirm.custom_minimum_size = Vector2(190, 34)
	_confirm.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_confirm.pressed.connect(_on_confirm)
	footer.add_child(_confirm)

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
