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

var _detail: RichTextLabel
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

	_detail.text = _detail_text()

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

	var kinds := ["Consumable", "Tool", "Key"]
	var kind: String = kinds[item.kind] if item.kind < kinds.size() else "?"
	var lines := [
		"",
		"  %s    %s" % [_key(item.display_name), _aside(kind)],
	]
	if item.heals > 0:
		lines.append("  Restores %d health." % item.heals)
	if item.kind == ItemData.Kind.TOOL:
		lines.append("  Used with the tool key.")
	if item.kind == ItemData.Kind.KEY:
		lines.append("  Not something you use. It opens something.")
	if item.stack_size > 1:
		lines.append("  Stacks to %d." % item.stack_size)
	if not item.description.is_empty():
		lines.append("")
		lines.append("  " + _aside(item.description))
	return "\n".join(lines)


func _on_slot_hover(slot: int, entered: bool) -> void:
	if entered:
		_hovered = slot
	elif _hovered == slot:
		_hovered = -1
	if _open:
		_detail.text = _detail_text()


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
	_tabs.offset_left = 120.0
	_tabs.offset_top = 70.0
	_tabs.offset_right = -120.0
	_tabs.offset_bottom = -70.0
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
func _build_inventory_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Inventory"
	page.add_theme_constant_override("separation", 14)

	var grid := GridContainer.new()
	grid.columns = ItemsComponent.HOTBAR_SLOTS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)

	for i in SLOT_COUNT:
		if i == ItemsComponent.HOTBAR_SLOTS:
			# A gap under the first row. That row is the hotbar — the same ten
			# slots, in the same order, with the same numbers — and the three
			# below are the pack. Running them together would make forty
			# identical boxes and hide the only distinction that matters.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 14)
			page.add_child(gap)
			page.move_child(gap, 1)
			var pack := GridContainer.new()
			pack.columns = 10
			pack.add_theme_constant_override("h_separation", 6)
			pack.add_theme_constant_override("v_separation", 6)
			page.add_child(pack)
			page.move_child(pack, 2)
			grid = pack
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(62, 62)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.13, 0.11, 0.10)
		box.border_color = Color(0.42, 0.35, 0.26)
		box.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", box)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 8.0
		icon.offset_top = 8.0
		icon.offset_right = -8.0
		icon.offset_bottom = -8.0
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

		grid.add_child(slot)
		_slot_panels.append(slot)
		_slot_icons.append(icon)
		_slot_counts.append(count)

	_detail = _text_page("Detail")
	_detail.custom_minimum_size = Vector2(0, 150)
	page.add_child(_detail)

	_satchel = Label.new()
	_satchel.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_satchel.add_theme_color_override("font_color", Color(0.86, 0.80, 0.68))
	page.add_child(_satchel)
	return page
