extends CanvasLayer
## Tab. Character, inventory, map.
##
## An autoload for the reasons `Hud` and `PauseMenu` are, and it pauses the same
## way — a menu you can be hit while reading is a menu nobody opens.
##
## **It holds no reference to the player.** Every number on these pages arrives
## on the event bus, exactly as the HUD's do (GDD §12 rule 1: nothing looks the
## player up). That is also why `Events.player_stats_changed` exists rather than
## the menu reaching for `move_speed` — the moment a UI panel knows how to find
## the player, so does everything else.

## Below the pause menu (110), above the HUD (64) and the debug overlay (100).
## Escape over Tab should reach the pause menu, not the other way round.
const LAYER: int = 108

## Twelve on the bar, thirty in the pack.
const SLOT_COUNT: int = 42

signal opened
signal closed

var stats: Dictionary = {}

## What the player is wearing, pushed here rather than fetched. This menu is an
## autoload and outlives every scene it opens over, so anything it *holds* is a
## freed reference waiting to happen — and reaching into `current_scene` for a
## player is the singleton habit GDD §12 rule 1 exists to stop. Actions still
## need the real player; the display does not.
var worn: Dictionary = {}
var materials: Dictionary = {}

var _root: Control
var _tabs: TabContainer

## Grid slot panels, and the pane that describes whichever one you are pointing
## at. Kept as references rather than looked up by name every refresh.
var _slot_panels: Array[Panel] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []
## Emphasis, for a font with one weight.
##
## `[b]` and `[i]` are dead here — `art/fonts/ui_theme.tres` points bold and
## italic at the same face, because Godot's synthetic versions smear and shear a
## pixel font into mush. So a heading is warmer and brighter than body copy, and
## an aside is dimmer. Colour is the only axis a single-weight pixel font has,
## and it is a perfectly good one.
const KEY := "b79a63"     ## labels and item names — warm, a step up from body
const ASIDE := "8a8378"   ## flavour text, parentheticals, "nothing here"
const BODY := "ebe3d2"

const PORTRAIT: Texture2D = preload("res://art/sprites/player/player_portrait.png")

## Inventory metrics, in one place because they are a budget rather than a
## preference: the window is 1280 wide, the hotbar is twelve slots across, and a
## column either side of it has to fit in what is left. At 62px — the size before
## the character and detail columns arrived — twelve slots plus two columns came
## to 1354 and the right-hand pane fell off the screen.
##
##     12 * 50 + 11 * 5 + 24  =  679   the grid
##     200 + 12 + 679 + 12 + 250 = 1153   the row
##     1153 + 2 * 40 = 1233 < 1280        with the page margins
const SLOT := 50
const GAP := 5
const COLUMN_LEFT := 200
const COLUMN_RIGHT := 250
const PAGE_MARGIN := 40.0

var _detail: RichTextLabel
var _detail_icon: TextureRect
var _who: Label
var _vitals: RichTextLabel
var _gear_panels: Array[Panel] = []
var _gear_icons: Array[TextureRect] = []
var _gear_labels: Array[Label] = []
var _gear_slots: Array[int] = []
var _satchel: Label
var _hovered: int = -1
var _pages: Dictionary = {}
var _open: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false

	Events.player_stats_changed.connect(func(values: Dictionary) -> void:
		stats = values
		if _open:
			_refresh())
	Events.player_items_changed.connect(func(_i: Array, _c: Array) -> void:
		if _open:
			_refresh())
	Events.player_equipment_changed.connect(func(gear: Dictionary) -> void:
		worn = gear.duplicate()
		if _open:
			_refresh())
	Events.material_collected.connect(func(id: StringName, amount: int) -> void:
		materials[id] = int(materials.get(id, 0)) + amount
		if _open:
			_refresh())


func is_open() -> bool:
	return _open


## Open on a given page, or close if that page is already showing — so I is a
## toggle for the inventory rather than a key that only ever opens.
func show_page(page: int) -> void:
	if _open and _tabs.current_tab == page:
		close()
		return
	if not _open:
		open()
	if _open:
		_tabs.current_tab = page


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or Transition.is_busy() or PauseMenu.is_open() or Dialogue.is_open():
		return
	_open = true
	_refresh()
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	# Only give time back if nothing else wants it stopped. Two menus that each
	# unpause on close would let the world run under whichever is still up.
	if not PauseMenu.is_open():
		get_tree().paused = false
		Hud.enabled = true
	closed.emit()


## `_input`, not `_unhandled_input`. Tab is also `ui_focus_next` and Escape is
## also `ui_cancel`, so once a Control inside the menu has focus the UI system
## consumes both before unhandled input is ever reached — and the menu becomes a
## room with no door. Taking them first is the only reliable fix.
## Which page each direct key opens. Tab is the general toggle and reopens
## whatever you were last looking at; these jump.
const PAGE_KEYS := {
	&"open_character": 0,
	&"open_inventory": 1,
	&"open_map": 2,
}


func _input(event: InputEvent) -> void:
	for action in PAGE_KEYS:
		if event.is_action_pressed(action):
			show_page(PAGE_KEYS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"open_menu"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed(&"ui_cancel"):
		# Escape backs out of the menu rather than stacking the pause menu on
		# top of it.
		close()
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- pages

func _refresh() -> void:
	_pages["Character"].text = _character_text()
	_refresh_inventory()
	_pages["Map"].text = _map_text()
	_refresh_equipment()


func _character_text() -> String:
	if stats.is_empty():
		return "\n  No one is being carried by this menu yet."
	var lines := [
		"",
		_row("Health", "%d / %d" % [stats.get("health", 0), stats.get("max_health", 0)]),
		_row("Stamina", "%.0f    %s" % [stats.get("max_stamina", 0.0),
			_aside("back in %.1fs after %.1fs" % [stats.get("regen_time", 0.0),
				stats.get("regen_delay", 0.0)])]),
		_row("Carry", "%d units" % stats.get("capacity", 0)),
		"",
		_row("Move", "%d px/s" % int(stats.get("move_speed", 0.0))),
		_row("Strike", "%s" % stats.get("damage", "-")),
		_row("Dash", "%d px" % int(stats.get("dodge_distance", 0.0))),
		"",
	]
	var granted: Array = stats.get("granted_by", [])
	if granted.is_empty():
		lines.append("  " + _aside("Nothing in Ambry is standing that was not standing when you"))
		lines.append("  " + _aside("arrived. Every one of these numbers moves when that changes,"))
		lines.append("  " + _aside("and nothing else moves them."))
	else:
		lines.append("  " + _key("Granted by"))
		for source in granted:
			lines.append("    %s" % String(source).capitalize())
	return "\n".join(lines)


## A label and its value, on one line. The label is warmer than the value rather
## than heavier, because there is no heavier — see `KEY`.
func _row(label: String, value: String) -> String:
	return "  %s%s%s" % [_key(label), " ".repeat(maxi(14 - label.length(), 1)), value]


func _key(text: String) -> String:
	return "[color=%s]%s[/color]" % [KEY, text]


func _aside(text: String) -> String:
	return "[color=%s]%s[/color]" % [ASIDE, text]


## The item's category, set apart from its name.
##
## **`[i]` is not available and would do nothing.** `art/fonts/ui_theme.tres`
## points italics at the regular face on purpose: Godot has no italic to use, so
## it shears the glyphs, and a sheared pixel font stops having whole-pixel
## strokes — the one thing the whole font depends on. Asking for italic here
## renders identically to not asking.
##
## So the two axes that do exist carry it: an asterisk to mark it as an aside
## rather than part of the name, and a dimmer colour than even body flavour text.
const KIND := "6e695f"

func _kind(text: String) -> String:
	return "[color=%s]*%s[/color]" % [KIND, text]


## The grid is the inventory; the pane underneath is what it is for. Hovering is
## the read and the hotbar number is the write — a slot you can point at but not
## identify is a slot the player has to remember, which is what a menu exists to
## remove.
func _refresh_inventory() -> void:
	for i in _slot_panels.size():
		var item := _item_in(i)
		_slot_icons[i].texture = item.icon if item != null else null
		var held: int = int(Hud.slot_counts[i]) if i < Hud.slot_counts.size() else 0
		_slot_counts[i].text = str(held) if item != null and held > 1 else ""
		_slot_panels[i].modulate = Color.WHITE if item != null else Color(1, 1, 1, 0.45)

	_refresh_detail()
	_refresh_vitals()

	var line := "  Satchel   %d / %d" % [Hud.carried, Hud.capacity]
	if materials.is_empty():
		line += "      (empty — materials are what the town is rebuilt out of)"
	else:
		for id in materials:
			line += "      %s x%d" % [String(id).capitalize(), int(materials[id])]
	_satchel.text = line


func _item_in(slot: int) -> ItemData:
	if slot < 0 or slot >= Hud.slot_items.size():
		return null
	return Hud.slot_items[slot] if Hud.slot_items[slot] is ItemData else null


## Falls back to the selected slot when nothing is hovered, so the pane is never
## blank for someone playing on a pad or the number keys.
func _detail_text() -> String:
	var slot: int = _hovered if _hovered >= 0 else Hud.selected
	var item := _item_in(slot)
	if item == null:
		return "\n  " + _aside("Nothing in that slot.")

	var kinds := ["Consumable", "Tool", "Key", "Gear"]
	var kind: String = kinds[item.kind] if item.kind < kinds.size() else "?"
	var lines := [
		"",
		"  %s    %s" % [_key(item.display_name), _kind(kind)],
	]
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
		lines.append("  " + _aside(item.description))
	return "\n".join(lines)


## Name, picture and prose all come from the same slot, so they can never
## describe two different items — which is the failure the old single-label pane
## could not have, and the new one could.
func _refresh_detail() -> void:
	var slot: int = _hovered if _hovered >= 0 else Hud.selected
	var item := _item_in(slot)
	_detail_icon.texture = item.icon if item != null else null
	_detail.text = _detail_text()


## The left column. Bars as text rather than as ProgressBars: at this size a
## 4px-tall bar is a smear, and "4 / 6" is both smaller and exact.
func _refresh_vitals() -> void:
	if _who == null:
		return
	_who.text = "The Condemned"
	if stats.is_empty():
		_vitals.text = "\n  " + _aside("No player.")
		return
	var lines := [
		"",
		_row("Health", "%d / %d" % [stats.get("health", 0), stats.get("max_health", 0)]),
		_row("Stamina", "%.0f" % stats.get("max_stamina", 0.0)),
		_row("Carry", "%d" % stats.get("capacity", 0)),
		"",
		_row("Move", "%d px/s" % int(stats.get("move_speed", 0.0))),
		_row("Strike", "%s" % stats.get("damage", "-")),
		_row("Reach", "%s" % stats.get("reach", "-")),
	]
	_vitals.text = "\n".join(lines)


func _on_slot_hover(slot: int, entered: bool) -> void:
	if entered:
		_hovered = slot
	elif _hovered == slot:
		_hovered = -1
	if _open:
		_refresh_detail()


func _map_text() -> String:
	# Diegetic rather than "coming soon": the archive is the building that tracks
	# the blight (docs/AMBRY.md, rebuild project 6), and it is a ruin. The map
	# being unavailable is the design, not a gap in it.
	return """
  [color=8a8378]You have no map.[/color]

  The archive kept them — every holding in the valley, and what the blight
  had taken of it. It is a ruin on the far side of the wall, and the wall
  is a breach packed with rubble.

  Rebuild it and this page fills in."""


# ------------------------------------------------------------------ building

func _build() -> void:
	_root = Control.new()
	_root.name = "GameMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	UiScale.register(self, _root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.04, 0.04, 0.86)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	_tabs = TabContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.offset_left = PAGE_MARGIN
	_tabs.offset_top = 56.0
	_tabs.offset_right = -PAGE_MARGIN
	_tabs.offset_bottom = -56.0
	_tabs.add_theme_font_size_override("font_size", TypeScale.SMALL)
	# Opaque, not translucent. The default panel lets the debug overlay show
	# straight through the page you are trying to read.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.08, 0.08)
	panel.border_color = Color(0.32, 0.27, 0.20)
	panel.set_border_width_all(2)
	panel.set_content_margin_all(18)
	_tabs.add_theme_stylebox_override("panel", panel)
	_root.add_child(_tabs)

	_tabs.add_child(_build_inventory_page())

	for page_name in ["Character", "Map"]:
		var text := _text_page(page_name)
		_tabs.add_child(text)
		_pages[page_name] = text
	# Character first, then the grid, then the map.
	_tabs.move_child(_tabs.get_node("Character"), 0)


## Four worn slots: what you swing, what you wear, what is on your feet, and
## which of the four keys is in your hand (GDD §6). New to the design — GDD §15
## A9 is the record of it — and the count is deliberately small. A full wardrobe
## is a §2 conversation, not a code change. The list is ItemData.EQUIP_SLOTS, so
## this loop never needs editing to gain or lose one.
##
## Drag gear here, or right-click it. Clicking a worn slot takes it off.
## A bordered box with a heading, the way the reference lays out every region of
## its inventory. One helper rather than four copies of eleven lines, and it is
## what makes the page read as regions instead of as a wall of boxes: the frames
## do the grouping that a second font weight would normally do, and this project
## has one weight (see KEY).
func _framed(title: String, tip: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.11, 0.10, 0.09)
	box.border_color = Color(0.30, 0.25, 0.19)
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	if not title.is_empty():
		var heading := Label.new()
		heading.text = title.to_upper()
		heading.tooltip_text = tip
		heading.add_theme_font_size_override("font_size", TypeScale.SMALL)
		heading.add_theme_color_override("font_color", Color(0.72, 0.61, 0.39))
		column.add_child(heading)

	# The caller wants the inside; the frame is plumbing. Stash it so the layout
	# can add the panel rather than the column.
	column.set_meta(&"frame", panel)
	return column


static func _frame_of(column: Control) -> Control:
	return column.get_meta(&"frame", column)


func _build_equipment() -> Control:
	var column := _framed("Equipped", "Drag gear here, or right-click it")
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	column.add_child(strip)

	for slot in ItemData.EQUIP_SLOTS:
		# One column per slot: the box, and its name under it. Under rather than
		# beside, because four names beside four boxes is a table, and a table
		# reads as data you are meant to compare rather than as a paper doll.
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		strip.add_child(row)

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT, SLOT)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.13, 0.11, 0.10)
		box.border_color = Color(0.42, 0.35, 0.26)
		box.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", box)
		row.add_child(panel)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6.0
		icon.offset_top = 6.0
		icon.offset_right = -6.0
		icon.offset_bottom = -6.0
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(88, 0)
		label.clip_text = true
		label.add_theme_font_size_override("font_size", TypeScale.SMALL)
		label.add_theme_color_override("font_color", Color(0.86, 0.80, 0.68))
		row.add_child(label)

		var index := _gear_panels.size()
		panel.gui_input.connect(_on_gear_click.bind(index))
		panel.set_drag_forwarding(_drag_from_gear.bind(panel, index), _can_drop_on_gear.bind(index),
			_drop_on_gear.bind(index))
		_gear_panels.append(panel)
		_gear_icons.append(icon)
		_gear_labels.append(label)
		_gear_slots.append(slot)
	return column


func _refresh_equipment() -> void:
	for i in _gear_panels.size():
		var item: ItemData = worn.get(_gear_slots[i])
		_gear_icons[i].texture = item.icon if item != null else null
		_gear_labels[i].text = item.display_name if item != null \
			else ItemData.slot_name(_gear_slots[i])
		_gear_labels[i].add_theme_color_override("font_color",
			Color(0.86, 0.80, 0.68) if item != null else Color(0.52, 0.48, 0.43))


## The player, if this menu is over a level that has one. Found rather than
## held: the menu is an autoload and outlives every scene it opens over, so a
## stored reference would be a freed one (GDD §12 rule 1 — nothing looks the
## player up globally, and this asks the current scene).
func _player() -> Player:
	var scene := get_tree().current_scene
	return scene.get("player") as Player if scene != null else null


## Dragging, and a right-click shortcut for people who would rather not.
##
## The drag payload is {where, slot}: `where` is "pack" or "gear" so a drop
## target can tell a hotbar slot from a worn one without inspecting the item,
## and `slot` is the pack index or the `ItemData.Slot` respectively.
##
## Left-drag moves; **right-click** equips or unequips in one action. Both,
## because dragging is discoverable and clicking is faster, and the fast path is
## the one you use on the fortieth loaf of bread.
## `from` is the panel being dragged, because `set_drag_preview` belongs to the
## Control that started the drag and this menu is a CanvasLayer.
func _drag_from_pack(_at: Vector2, from: Control, slot: int) -> Variant:
	var item := _item_in(slot)
	if item == null:
		return null
	from.set_drag_preview(_drag_preview(item))
	return {"where": "pack", "slot": slot}


func _drag_from_gear(_at: Vector2, from: Control, index: int) -> Variant:
	var item: ItemData = worn.get(_gear_slots[index])
	if item == null:
		return null
	from.set_drag_preview(_drag_preview(item))
	return {"where": "gear", "slot": _gear_slots[index]}


static func _drag_preview(item: ItemData) -> Control:
	var ghost := TextureRect.new()
	ghost.texture = item.icon
	ghost.custom_minimum_size = Vector2(52, 52)
	ghost.size = Vector2(52, 52)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.modulate = Color(1, 1, 1, 0.85)
	return ghost


func _can_drop_on_pack(_at: Vector2, data: Variant, _slot: int) -> bool:
	return data is Dictionary and (data as Dictionary).has("where")


## A worn slot only takes what belongs in it. Refusing here rather than
## accepting and silently doing nothing is the difference between a rule and a
## bug: the cursor says no while you are still holding the thing.
func _can_drop_on_gear(_at: Vector2, data: Variant, index: int) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if String(payload.get("where", "")) != "pack":
		return false
	var item := _item_in(int(payload.get("slot", -1)))
	return item != null and item.slot == _gear_slots[index]


func _drop_on_pack(_at: Vector2, data: Variant, slot: int) -> void:
	var player := _player()
	var payload: Dictionary = data
	if player == null:
		return
	if String(payload.get("where", "")) == "gear":
		var removed := player.equipment.unequip(int(payload.get("slot", 0)))
		if removed != null:
			@warning_ignore("return_value_discarded")
			player.items.add(removed)
	else:
		player.items.swap(int(payload.get("slot", -1)), slot)
	_refresh()


func _drop_on_gear(_at: Vector2, data: Variant, index: int) -> void:
	var payload: Dictionary = data
	_equip_from(int(payload.get("slot", -1)))


## Right-click: straight to the slot the item names, and back to the pack from
## a worn slot. No target to choose, because the item already knows.
func _on_gear_click(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	var player := _player()
	if player == null:
		return
	var removed := player.equipment.unequip(_gear_slots[index])
	if removed != null:
		@warning_ignore("return_value_discarded")
		player.items.add(removed)
	_refresh()


func _on_slot_click(event: InputEvent, slot: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	_equip_from(slot)


func _equip_from(slot: int) -> void:
	var player := _player()
	var item := _item_in(slot)
	if player == null or item == null or not item.is_equippable():
		return
	var displaced := player.equipment.equip(item)
	@warning_ignore("return_value_discarded")
	player.items.remove(slot, 1)
	if displaced != null:
		@warning_ignore("return_value_discarded")
		player.items.add(displaced)
	_refresh()


func _text_page(page_name: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = page_name
	text.bbcode_enabled = true
	text.scroll_active = true
	text.add_theme_font_size_override("normal_font_size", TypeScale.SMALL)
	text.add_theme_font_size_override("bold_font_size", TypeScale.SMALL)
	text.add_theme_font_size_override("italics_font_size", TypeScale.SMALL)
	text.add_theme_color_override("default_color", Color(0.92, 0.89, 0.82))
	return text


## Forty slots: the hotbar across the top, then three rows of pack, then the
## description. The top row is the same ten slots in the same order with the
## same numbers as the bar on screen — a menu that rearranges the bar it
## describes teaches the player two layouts for one thing.
## Three columns and a footer: who you are, what you are carrying, and what the
## thing you are pointing at actually does.
##
## The previous version stacked everything vertically, which meant the detail
## pane sat below the grid — so reading an item moved your eye off the item. The
## reference this follows puts the character on the left, the grid in the middle
## and the description on the right, and the reason it works is that all three
## are visible at once: hovering a slot changes the right-hand column while your
## cursor stays where it was.
##
## Worn gear moves to the footer for the same reason it is a row and not a
## column — it is a paper doll, not a table, and it belongs under the pack rather
## than beside it now that the middle is the pack's.
func _build_inventory_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Inventory"
	page.add_theme_constant_override("separation", 12)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	columns.add_child(_frame_of(_build_character_column()))

	var centre := _framed("Carried")
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_of(centre).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_frame_of(centre))

	var grid := GridContainer.new()
	grid.columns = ItemsComponent.HOTBAR_SLOTS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	centre.add_child(grid)

	for i in SLOT_COUNT:
		if i == ItemsComponent.HOTBAR_SLOTS:
			# A gap under the first row. That row is the hotbar — the same ten
			# slots, in the same order, with the same numbers — and the three
			# below are the pack. Running them together would make forty
			# identical boxes and hide the only distinction that matters.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 12)
			centre.add_child(gap)

			var pack := GridContainer.new()
			pack.columns = 10
			pack.add_theme_constant_override("h_separation", GAP)
			pack.add_theme_constant_override("v_separation", GAP)
			centre.add_child(pack)
			grid = pack
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(SLOT, SLOT)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.13, 0.11, 0.10)
		box.border_color = Color(0.42, 0.35, 0.26)
		box.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", box)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6.0
		icon.offset_top = 6.0
		icon.offset_right = -6.0
		icon.offset_bottom = -6.0
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		var number := Label.new()
		# Only the hotbar row is numbered; the pack has no keys to advertise.
		number.text = Hud._slot_key(i) if i < ItemsComponent.HOTBAR_SLOTS else ""
		number.position = Vector2(5, 1)
		number.add_theme_font_size_override("font_size", TypeScale.SMALL)
		number.add_theme_color_override("font_color", Color(0.75, 0.70, 0.62, 0.85))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(number)

		var count := Label.new()
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -34.0
		count.offset_top = -30.0
		count.offset_right = -6.0
		count.offset_bottom = -4.0
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override("font_size", TypeScale.SMALL)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count)

		slot.mouse_entered.connect(_on_slot_hover.bind(i, true))
		slot.mouse_exited.connect(_on_slot_hover.bind(i, false))
		slot.gui_input.connect(_on_slot_click.bind(i))
		slot.set_drag_forwarding(_drag_from_pack.bind(slot, i), _can_drop_on_pack.bind(i),
			_drop_on_pack.bind(i))

		grid.add_child(slot)
		_slot_panels.append(slot)
		_slot_icons.append(icon)
		_slot_counts.append(count)

	_satchel = Label.new()
	_satchel.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_satchel.add_theme_color_override("font_color", Color(0.86, 0.80, 0.68))
	centre.add_child(_satchel)

	columns.add_child(_frame_of(_build_detail_column()))

	# The footer: what you are wearing, and what the buttons do.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)
	footer.add_child(_frame_of(_build_equipment()))

	var hints := Label.new()
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hints.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hints.text = "Drag to move    Right-click to equip    Tab to close"
	hints.add_theme_font_size_override("font_size", TypeScale.SMALL)
	hints.add_theme_color_override("font_color", Color(0.54, 0.50, 0.45))
	footer.add_child(hints)
	return page


## Left column: the paper doll's other half — who this is, and the numbers that
## describe them. Pushed from `Events.player_stats_changed` like everything else
## here; nothing on this page reaches for a player (GDD §12 rule 1).
func _build_character_column() -> VBoxContainer:
	var column := _framed("")
	_frame_of(column).custom_minimum_size = Vector2(COLUMN_LEFT, 0)

	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(COLUMN_LEFT - 28, 150)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.06, 0.06)
	box.border_color = Color(0.30, 0.25, 0.19)
	box.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", box)
	column.add_child(frame)

	var face := TextureRect.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 4.0
	face.offset_top = 4.0
	face.offset_right = -4.0
	face.offset_bottom = -4.0
	face.texture = PORTRAIT
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(face)

	_who = Label.new()
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_who.add_theme_color_override("font_color", Color(0.72, 0.61, 0.39))
	column.add_child(_who)

	_vitals = _text_page("Vitals")
	_vitals.custom_minimum_size = Vector2(0, 250)
	_vitals.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_vitals)
	return column


## Right column: the item. Name, a large picture of it, and what it does.
##
## The picture is the reason this is a column rather than a strip of text. An
## inventory icon is 64px in a 62px box; at that size a bottle and a vial are the
## same object, and the player learns their inventory by position rather than by
## sight. Shown large, once, next to its own name, they are different things.
func _build_detail_column() -> VBoxContainer:
	var column := _framed("")
	_frame_of(column).custom_minimum_size = Vector2(COLUMN_RIGHT, 0)

	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(0, 128)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_detail_icon)

	_detail = _text_page("Detail")
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_detail)
	return column
