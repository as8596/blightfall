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
var _scale_label: Label
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
	if _open or Transition.is_busy() or GameMenu.is_open() or Dialogue.is_open() \
			or LootMenu.is_open():
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
	if not GameMenu.is_open():
		get_tree().paused = false
		Hud.enabled = true
	closed.emit()


## `_input` for the same reason the character menu uses it: a focused Button
## swallows `ui_cancel`, and a pause menu you cannot close with Escape is worse
## than no pause menu.
## **Escape backs out of the innermost thing that is open.**
##
## Every menu in the game claims `ui_cancel`, and `_input` reaches autoloads in
## reverse registration order — so this one, listed last, was getting Escape
## first and opening the pause menu *on top of* whatever the player was actually
## trying to close. The character menu's own Escape handler never ran.
##
## Standing aside is the fix rather than reordering the autoloads: the ordering
## in `project.godot` is load-bearing for other reasons (data before UI), and a
## menu that knows to wait its turn is easier to reason about than a list whose
## order encodes input priority.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if not _open and _something_else_is_open():
		return
	toggle()
	get_viewport().set_input_as_handled()


## Anything the player would expect Escape to shut before it reaches the pause
## menu. Not `Hud`, which is never modal, and not this menu itself — once it is
## up, Escape closes it and nothing else gets a say.
func _something_else_is_open() -> bool:
	return GameMenu.is_open() or ShopMenu.is_open() or LootMenu.is_open() \
		or Dialogue.is_open()


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
	if _scale_label != null:
		_scale_label.text = "UI scale   %.1f x" % UiScale.factor


func _on_ui_scale_changed(_to: float) -> void:
	_refresh()


## One labelled slider, wired straight at the bus.
##
## No apply button and no confirmation: audio is the one setting where the
## feedback *is* the change, so hearing it move is the whole interface.
func _volume_row(bus: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = bus
	label.custom_minimum_size = Vector2(96, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = AudioMix.volume(bus)
	slider.custom_minimum_size = Vector2(180, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(56, 32)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", TypeScale.SMALL)
	readout.text = "%d%%" % roundi(slider.value * 100.0)
	row.add_child(readout)

	slider.value_changed.connect(func(level: float) -> void:
		AudioMix.set_volume(bus, level)
		readout.text = "%d%%" % roundi(level * 100.0))
	return row


func _build() -> void:
	_root = Control.new()
	_root.name = "PauseMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	UiScale.register(self, _root, true)

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
	title.add_theme_font_size_override("font_size", TypeScale.HEADING)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	column.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	column.add_child(spacer)

	var scale_row := HBoxContainer.new()
	scale_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scale_row.add_theme_constant_override("separation", 12)
	column.add_child(scale_row)

	var smaller := Button.new()
	smaller.text = "-"
	smaller.custom_minimum_size = Vector2(48, 40)
	smaller.add_theme_font_size_override("font_size", TypeScale.SMALL)
	smaller.pressed.connect(func() -> void: UiScale.factor -= UiScale.STEP)
	scale_row.add_child(smaller)

	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(176, 40)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scale_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scale_label.add_theme_font_size_override("font_size", TypeScale.SMALL)
	scale_row.add_child(_scale_label)

	var bigger := Button.new()
	bigger.text = "+"
	bigger.custom_minimum_size = Vector2(48, 40)
	bigger.add_theme_font_size_override("font_size", TypeScale.SMALL)
	bigger.pressed.connect(func() -> void: UiScale.factor += UiScale.STEP)
	scale_row.add_child(bigger)

	# A method rather than a lambda, for the reason in `ui/main_menu.gd`. This
	# one is an autoload and never dies, so it was safe — but the pattern is not,
	# and one of the two places it appeared was a real crash.
	UiScale.changed.connect(_on_ui_scale_changed)

	# Volumes. Sliders rather than a pair of buttons like the scale, because a
	# level is a position on a range and the scale is a short list of steps —
	# and because nobody wants to press "-" eleven times to mute the music.
	for bus in AudioMix.BUSES:
		column.add_child(_volume_row(bus))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	column.add_child(gap)

	for entry in [
		["Resume", close],
		["Save", _on_save],
		["Load", _on_load],
		["Quit", _on_quit],
	]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(280, 44)
		button.add_theme_font_size_override("font_size", TypeScale.SMALL)
		UiKit.dress_button(button)
		button.pressed.connect(entry[1])
		column.add_child(button)
		_buttons.append(button)
