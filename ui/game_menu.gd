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

signal opened
signal closed

var stats: Dictionary = {}
var materials: Dictionary = {}

var _root: Control
var _tabs: TabContainer
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


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or Transition.is_busy() or PauseMenu.is_open():
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


func _unhandled_input(event: InputEvent) -> void:
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
	_pages["Inventory"].text = _inventory_text()
	_pages["Map"].text = _map_text()


func _character_text() -> String:
	if stats.is_empty():
		return "\n  No one is being carried by this menu yet."
	var lines := [
		"",
		"  [b]Health[/b]        %d / %d" % [stats.get("health", 0), stats.get("max_health", 0)],
		"  [b]Stamina[/b]       %.0f" % stats.get("max_stamina", 0.0),
		"  [b]Carry[/b]         %d units" % stats.get("capacity", 0),
		"",
		"  [b]Move[/b]          %d px/s" % int(stats.get("move_speed", 0.0)),
		"  [b]Strike[/b]        %s" % stats.get("damage", "-"),
		"  [b]Dash[/b]          %d px" % int(stats.get("dodge_distance", 0.0)),
		"",
		"  [i]Every one of these moves when Ambry does. Rebuild the forge and",
		"  Strike changes; the apothecary and Health does.[/i]",
	]
	return "\n".join(lines)


func _inventory_text() -> String:
	var lines := ["", "  [b]Carried[/b]"]
	var any := false
	for i in Hud.slot_items.size():
		var item: ItemData = Hud.slot_items[i] if Hud.slot_items[i] is ItemData else null
		if item == null:
			continue
		any = true
		var held: int = int(Hud.slot_counts[i]) if i < Hud.slot_counts.size() else 1
		var count := " ×%d" % held if held > 1 else ""
		lines.append("    %d.  %s%s" % [(i + 1) % 10, item.display_name, count])
		if not item.description.is_empty():
			lines.append("        [i]%s[/i]" % item.description)
	if not any:
		lines.append("    [i]Nothing.[/i]")

	lines.append("")
	lines.append("  [b]Satchel[/b]   %d / %d" % [Hud.carried, Hud.capacity])
	if materials.is_empty():
		lines.append("    [i]Empty. Materials go here — they are what the town is")
		lines.append("    rebuilt out of.[/i]")
	else:
		for id in materials:
			lines.append("    %s  ×%d" % [String(id).capitalize(), int(materials[id])])
	return "\n".join(lines)


func _map_text() -> String:
	# Diegetic rather than "coming soon": the archive is the building that tracks
	# the blight (docs/AMBRY.md, rebuild project 6), and it is a ruin. The map
	# being unavailable is the design, not a gap in it.
	return """
  [i]You have no map.[/i]

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
	_tabs.add_theme_font_size_override("font_size", 22)
	# Opaque, not translucent. The default panel lets the debug overlay show
	# straight through the page you are trying to read.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.08, 0.08)
	panel.border_color = Color(0.32, 0.27, 0.20)
	panel.set_border_width_all(2)
	panel.set_content_margin_all(18)
	_tabs.add_theme_stylebox_override("panel", panel)
	_root.add_child(_tabs)

	for page_name in ["Character", "Inventory", "Map"]:
		var text := RichTextLabel.new()
		text.name = page_name
		text.bbcode_enabled = true
		text.scroll_active = true
		text.add_theme_font_size_override("normal_font_size", 20)
		text.add_theme_font_size_override("bold_font_size", 20)
		text.add_theme_font_size_override("italics_font_size", 20)
		text.add_theme_color_override("default_color", Color(0.92, 0.89, 0.82))
		_tabs.add_child(text)
		_pages[page_name] = text
