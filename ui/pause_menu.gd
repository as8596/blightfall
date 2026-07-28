extends CanvasLayer
## Escape. Resume, save, load, quit.
##
## An autoload, like `Hud` and `ScreenFade`, for the same two reasons: it has to
## exist in every scene without each one remembering to add it, and it has to
## survive the `change_scene_to_file` that loading a save performs — a menu
## parented to the outgoing scene is freed halfway through the thing it asked
## for.
##
## **It pauses the tree, and three things deliberately keep running.** `Music`
## and `ScreenFade` are `PROCESS_MODE_ALWAYS`, so the score does not cut out and
## a transition started before the pause can still finish; and this menu itself,
## or Escape would have no way to close it. Everything else — the player, the
## enemies, every timer — stops, which is what makes pausing worth having.

## Above the HUD (64) and the debug overlay (100), below the fade (128). A menu
## the fade cannot cover would flicker into view mid-transition.
const LAYER: int = 110

signal opened
signal closed

var _root: Control
var _buttons: Array[Button] = []
var _open: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	# Never over a transition: the scene is being torn down and a menu that
	# survives into the next one would be sitting on top of a level the player
	# has not seen yet.
	if _open or Transition.is_busy():
		return
	_open = true
	_refresh()
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	Hud.enabled = true
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ actions

func _on_save() -> void:
	if SaveGame.save_slot(SaveGame.current_slot):
		close()


func _on_load() -> void:
	var data := SaveGame.read_slot(SaveGame.current_slot)
	if data.is_empty():
		return
	var scene := String(data.get("scene", ""))
	if scene.is_empty() or not ResourceLoader.exists(scene):
		return
	# Unpause first: the transition's fade and its awaited frames need the tree
	# running, and `Transition` is not the thing that paused it.
	close()
	@warning_ignore("return_value_discarded")
	Transition.go(scene, "", data)


func _on_quit() -> void:
	get_tree().quit()


# ------------------------------------------------------------------ building

func _refresh() -> void:
	# Loading with nothing on disk would silently do nothing, which reads as a
	# broken button rather than as an empty slot.
	if _buttons.size() >= 3:
		_buttons[2].disabled = not SaveGame.has_save(SaveGame.current_slot)


func _build() -> void:
	_root = Control.new()
	_root.name = "PauseMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.04, 0.05, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	_root.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	column.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	column.add_child(spacer)

	for entry in [
		["Resume", close],
		["Save", _on_save],
		["Load", _on_load],
		["Quit", _on_quit],
	]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(280, 44)
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(entry[1])
		column.add_child(button)
		_buttons.append(button)
