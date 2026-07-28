extends Control
## The title screen. The first thing anybody sees, and until now the game did
## not have one — it booted into the middle of Ambry with no explanation and no
## way back out.
##
## A `Control`, not a `Level`. There is no world here, so there is no
## SubViewport and no `WorldView`: this is laid out at the window's real
## resolution like every other piece of UI, and `UiScale` sizes it.
##
## **Continue is first, and it is only enabled when there is something to
## continue.** A disabled button that explains itself is better than an enabled
## one that does nothing, which is what "load" used to be with an empty slot.

const AMBRY := "res://levels/ambry/ambry_level.tscn"

## GDD §4's opening is not built (it is M6 work), so New Game starts where the
## game currently starts: inside Ambry's south gate. When the intro exists this
## is the one line that changes.
const NEW_GAME_SPAWN := "PlayerSpawn"

const TEXT := Color(0.95, 0.92, 0.85)
const DIM := Color(0.62, 0.58, 0.52)

var _buttons: Array[Button] = []
var _continue: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Music.play(&"main_menu")
	# Whatever the last scene did to the tree, a title screen is not paused and
	# has no HUD over it.
	get_tree().paused = false
	Hud.enabled = false
	if _continue != null:
		(_continue if not _continue.disabled else _buttons[1]).grab_focus()


func _exit_tree() -> void:
	Hud.enabled = true


# ------------------------------------------------------------------ actions

func _on_continue() -> void:
	if not SaveGame.has_save(SaveGame.current_slot):
		return
	var data := SaveGame.read_slot(SaveGame.current_slot)
	var scene := String(data.get("scene", AMBRY))
	if scene.is_empty() or not ResourceLoader.exists(scene):
		scene = AMBRY
	@warning_ignore("return_value_discarded")
	Transition.go(scene, "", data)


func _on_new_game() -> void:
	# Deliberately does **not** delete the save. Overwriting somebody's run
	# because they pressed the top button by mistake is not a thing to do
	# silently, and a confirmation dialog is worth building when there is more
	# than one slot to lose.
	@warning_ignore("return_value_discarded")
	Transition.go(AMBRY, NEW_GAME_SPAWN)


func _on_quit() -> void:
	get_tree().quit()


# ----------------------------------------------------------------- building

func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.06, 0.06, 0.07)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "BLIGHTFALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TEXT)
	column.add_child(title)

	var tagline := Label.new()
	tagline.text = "the valley remembers what the town decided"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", DIM)
	column.add_child(tagline)

	_gap(column, 34)

	_continue = _button(column, "Continue", _on_continue)
	_continue.disabled = not SaveGame.has_save(SaveGame.current_slot)
	_button(column, "New Game", _on_new_game)

	_gap(column, 18)

	var scale_row := HBoxContainer.new()
	scale_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scale_row.add_theme_constant_override("separation", 12)
	column.add_child(scale_row)

	var smaller := Button.new()
	smaller.text = "-"
	smaller.custom_minimum_size = Vector2(48, 40)
	smaller.add_theme_font_size_override("font_size", 22)
	scale_row.add_child(smaller)

	var scale_label := Label.new()
	scale_label.custom_minimum_size = Vector2(176, 40)
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scale_label.add_theme_font_size_override("font_size", 20)
	scale_label.add_theme_color_override("font_color", DIM)
	scale_label.text = "UI scale   %.1f x" % UiScale.factor
	scale_row.add_child(scale_label)

	var bigger := Button.new()
	bigger.text = "+"
	bigger.custom_minimum_size = Vector2(48, 40)
	bigger.add_theme_font_size_override("font_size", 22)
	scale_row.add_child(bigger)

	# Adjustable from the title screen on purpose: it is the setting somebody
	# needs *before* they can comfortably read anything else, and burying it
	# behind a menu you reach by starting the game is the wrong way round.
	smaller.pressed.connect(func() -> void: UiScale.factor -= UiScale.STEP)
	bigger.pressed.connect(func() -> void: UiScale.factor += UiScale.STEP)
	UiScale.changed.connect(func(f: float) -> void:
		scale_label.text = "UI scale   %.1f x" % f)

	_gap(column, 18)
	_button(column, "Quit", _on_quit)


func _button(column: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(288, 46)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	column.add_child(button)
	_buttons.append(button)
	return button


func _gap(column: VBoxContainer, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	column.add_child(spacer)
