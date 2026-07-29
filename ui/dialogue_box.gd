extends CanvasLayer
## Talking to people. The box, the typewriter, the voice, and the replies.
##
## An autoload for the same reasons `Hud` and `PauseMenu` are: it has to exist
## in every scene without each one remembering to add it, and a conversation is
## not something a level should own.
##
## **It pauses the tree.** A conversation is a thing you are doing, not a thing
## happening next to something else you are doing, and a player who can walk
## away mid-sentence will. `Music` and `ScreenFade` keep running (they are
## `PROCESS_MODE_ALWAYS`), and so does this.
##
## ## The voice
##
## Text reveals a character at a time and plays a short pitched blip every few
## characters — the Animal Crossing trick, which works because it is not
## *speech*: it is a mouth moving at the speed the words arrive. Three blips are
## cycled so a sentence is not one sound forty times, playback jitters the pitch
## a further few percent, and each speaker carries a fixed pitch offset so they
## sound like themselves from one line to the next.
##
## Blips are deliberately not played on spaces or punctuation. Speech has gaps
## in it, and a blip on every single glyph is a dial tone.
##
## ## Data
##
## `resources/dialogue/<id>.json`. A node is some lines and then some replies;
## a reply names the node it leads to, and an empty target ends the
## conversation. JSON rather than a `.tres` because the alternative is authoring
## a branching script in the inspector, and nobody has ever done that twice.

signal started(id: StringName)
signal finished(id: StringName)
## A reply was chosen. Everything that eventually hangs off a conversation — a
## quest starting, a project unlocking — listens here rather than reaching in.
signal chose(id: StringName, node: String, index: int)

## Above the HUD (64) and below the menus (108/110): a conversation should cover
## the health bar, and the pause menu should cover a conversation.
const LAYER: int = 106

const DIR := "res://resources/dialogue"

## Characters per second. Fast enough not to be a wait, slow enough to read as
## somebody speaking.
const SPEED: float = 44.0

## A blip every N revealed characters. Every character is a machine gun; every
## third is a mouth.
const BLIP_EVERY: int = 3

## Milliseconds after a conversation ends during which nobody will start
## another. The key that ended one is very often still down and the villager is
## still standing right there, so without this, letting go a fraction late
## restarts the conversation you just finished — which reads as the game
## refusing to let you leave.
const REOPEN_LOCK_MS: int = 250

const BOX_HEIGHT: float = 196.0
const MARGIN: float = 28.0
const PAD: Vector2 = Vector2(22.0, 16.0)
const BACK := Color(0.09, 0.08, 0.07, 0.95)
const EDGE := Color(0.42, 0.35, 0.26)
const TEXT := Color(0.95, 0.92, 0.85)
const DIM := Color(0.60, 0.56, 0.50)
const PICKED := Color(0.95, 0.88, 0.70)

## The spoken line leads and everything else supports it. There is no size
## between these two that the font rasterises cleanly — the grid gives 16 and 32
## and nothing in between (`ui/type_scale.gd`) — so the jump is large on purpose
## rather than a near-miss at 20 or 24, which is what it used to be.
##
## The name and the replies are the same size as each other and are told apart
## by colour and position: the name is the panel's border colour above the line,
## the replies are dim below it with a cursor on the chosen one.
const NAME_SIZE: int = TypeScale.SMALL
const LINE_SIZE: int = TypeScale.HEADING
const REPLY_SIZE: int = TypeScale.SMALL

var _open: bool = false
var _data: Dictionary = {}
var _id: StringName = &""
var _node: String = ""
var _lines: Array = []
var _line: int = 0
var _shown: float = 0.0
var _voice_pitch: float = 1.0
var _blips: int = 0
var _choice: int = 0
var _choices: Array = []

## Frames of input deadband. See `_read_input`.
var _lock: int = 0

## Last frame's held actions, for the rising edge.
var _held: Dictionary = {}

## When the last conversation ended. See `REOPEN_LOCK_MS`.
var _closed_at: int = -100000

var _root: Control
var _panel: Control
var _speaker: Label
var _body: Label
var _replies: VBoxContainer
var _prompt: Label

## Cached per id. A conversation restarted forty times should not re-parse forty
## times, and these files never change at runtime.
var _library: Dictionary = {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	set_process(false)


func is_open() -> bool:
	return _open


## True for a moment after a conversation ends. `Npc.can_interact` honours it.
func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_at < REOPEN_LOCK_MS


## Read-only state, so callers and tests do not have to reach into the box's
## internals to ask obvious questions about it.
func is_typing() -> bool:
	return _open and _typing()


func speaker() -> String:
	return _speaker.text if _speaker != null else ""


func line_text() -> String:
	return _body.text if _body != null else ""


func line_index() -> int:
	return _line


func node_name() -> String:
	return _node


func showing_replies() -> bool:
	return _open and _replies != null and _replies.visible


func choice_count() -> int:
	return _choices.size()


func choice_index() -> int:
	return _choice


# -------------------------------------------------------------------- flow

## Begin `id`'s conversation. Returns false if there is nothing to say, so a
## caller can fall back to a shrug rather than opening an empty box.
func start(id: StringName) -> bool:
	if _open or Transition.is_busy() or PauseMenu.is_open() or GameMenu.is_open():
		return false
	var data := load_dialogue(id)
	if data.is_empty():
		return false
	_data = data
	_id = id
	_voice_pitch = float(data.get("voice_pitch", 1.0))
	_speaker.text = String(data.get("name", String(id)))
	_open = true
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	set_process(true)
	_lock = 1
	_enter_node(String(data.get("start", "greeting")))
	started.emit(id)
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	_closed_at = Time.get_ticks_msec()
	_root.visible = false
	set_process(false)
	if not PauseMenu.is_open() and not GameMenu.is_open():
		get_tree().paused = false
		Hud.enabled = true
	finished.emit(_id)
	_id = &""


## Load and cache `res://resources/dialogue/<id>.json`. Empty on anything wrong,
## and loud about it — a missing conversation is a content bug, and content bugs
## that fail quietly ship.
func load_dialogue(id: StringName) -> Dictionary:
	if _library.has(id):
		return _library[id]
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		push_warning("Dialogue: nothing written for '%s' (%s)" % [id, path])
		_library[id] = {}
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text() if file != null else "")
	if file != null:
		file.close()
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("nodes"):
		push_error("Dialogue: %s is not a conversation" % path)
		_library[id] = {}
		return {}
	_library[id] = parsed
	return parsed


func _enter_node(name: String) -> void:
	var nodes: Dictionary = _data.get("nodes", {})
	if name == "" or not nodes.has(name):
		close()
		return
	_node = name
	var node: Dictionary = nodes[name]
	_lines = node.get("lines", [])
	_choices = node.get("choices", [])
	_line = 0
	_start_line()


func _start_line() -> void:
	_shown = 0.0
	_blips = 0
	_body.text = String(_lines[_line]) if _line < _lines.size() else ""
	_body.visible_characters = 0
	_replies.visible = false
	_prompt.visible = false


func _typing() -> bool:
	return _body.visible_characters < _body.text.length()


func _finish_line() -> void:
	_shown = float(_body.text.length())
	# The length, **not** -1. Godot reads -1 as "show everything", which draws
	# correctly and then makes `_typing()` — a numeric comparison — true forever:
	# every press re-finishes the line it already finished, and the conversation
	# can never reach its second line. It looked exactly like input not working.
	_body.visible_characters = _body.text.length()
	# Replies only on the last line of a node. Offering them mid-speech would
	# mean the player answers a sentence the character has not finished.
	if _line >= _lines.size() - 1 and not _choices.is_empty():
		_show_replies()
	else:
		_prompt.visible = true


func _advance() -> void:
	_lock = 1
	if _typing():
		_finish_line()
		return
	if not _choices.is_empty() and _line >= _lines.size() - 1:
		_pick()
		return
	_line += 1
	if _line >= _lines.size():
		close()
		return
	_start_line()


func _pick() -> void:
	if _choice < 0 or _choice >= _choices.size():
		close()
		return
	var choice: Dictionary = _choices[_choice]
	Sfx.play(&"ui_select", -8.0)
	chose.emit(_id, _node, _choice)
	_enter_node(String(choice.get("goto", "")))


# ------------------------------------------------------------------- input

func _process(delta: float) -> void:
	_read_input()
	if not _typing():
		return
	# Unscaled: the tree is paused, so `delta` is already real time, but hitstop
	# sets Engine.time_scale and a conversation must not stutter because
	# somebody was mid-swing when they pressed talk.
	_shown += SPEED * delta / maxf(Engine.time_scale, 0.001)
	var want: int = mini(int(_shown), _body.text.length())
	if want == _body.visible_characters:
		return
	for i in range(_body.visible_characters, want):
		if _speaks(_body.text[i]):
			_blips += 1
			if _blips % BLIP_EVERY == 0:
				Sfx.play_at(Sfx.VOICES[(_blips / BLIP_EVERY) % Sfx.VOICES.size()],
					_voice_pitch, -10.0, 0.08)
	_body.visible_characters = want
	if not _typing():
		_finish_line()


## Whether a character gets a blip. Speech has gaps in it — spaces and full
## stops are where a mouth is *not* moving, and blipping them turns a sentence
## into a tone.
static func _speaks(character: String) -> bool:
	return not (character in [" ", ".", ",", "!", "?", ";", ":", "'", "-", "\n"])


## Polled, with the edge detection done here rather than by the engine.
##
## Two reasons, and the second is the load-bearing one.
##
## **Polled rather than event-driven**, because everything else in the project
## polls — `InputComponent` does, the interactor does — and a box that listened
## for events could only be driven in a test by `Input.parse_input_event` while
## every other test drives `Input.action_press`. One mechanism, one harness.
##
## **And the rising edge is computed here rather than with
## `is_action_just_pressed`**, because that only reports true during the frame
## the input was *received*. A scripted `Input.action_press` is received inside
## whatever frame the caller was already in, so by the next frame the window has
## closed and nothing downstream ever sees the press — which is exactly how this
## failed the first time, silently, with the text sitting there.
##
## The lock is the other half. The **same** press that opened this box is still
## held on the frame it opens, so without a frame of deadband every conversation
## would skip its own first line the instant it started.
func _read_input() -> void:
	var confirm := Input.is_action_pressed(&"interact") or Input.is_action_pressed(&"ui_accept")
	var down := Input.is_action_pressed(&"move_down") or Input.is_action_pressed(&"ui_down")
	var up := Input.is_action_pressed(&"move_up") or Input.is_action_pressed(&"ui_up")
	var was := _held
	_held = {&"confirm": confirm, &"down": down, &"up": up}

	if _lock > 0:
		_lock -= 1
		return
	if confirm and not was.get(&"confirm", false):
		_advance()
		return
	if not _replies.visible:
		return
	var step := 0
	if down and not was.get(&"down", false):
		step = 1
	elif up and not was.get(&"up", false):
		step = -1
	if step == 0:
		return
	_choice = posmod(_choice + step, _choices.size())
	Sfx.play(&"ui_move", -14.0)
	_paint_replies()


# ---------------------------------------------------------------- building

func _show_replies() -> void:
	_choice = 0
	_replies.visible = true
	_paint_replies()


func _paint_replies() -> void:
	for child in _replies.get_children():
		child.queue_free()
	for i in _choices.size():
		var row := Label.new()
		var chosen := i == _choice
		# A cursor, not just a colour. Colour alone is a bad way to say "this
		# one" — it disappears on a bad monitor and for a colourblind player.
		row.text = "%s %s" % ["▸" if chosen else " ", String(_choices[i].get("text", "..."))]
		row.add_theme_font_size_override("font_size", REPLY_SIZE)
		row.add_theme_color_override("font_color", PICKED if chosen else DIM)
		_replies.add_child(row)


func _build() -> void:
	_root = Control.new()
	_root.name = "DialogueBox"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiScale.register(self, _root)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = -(BOX_HEIGHT + MARGIN)
	_panel.offset_bottom = -MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = BACK
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = PAD.x
	column.offset_right = -PAD.x
	column.offset_top = PAD.y
	column.offset_bottom = -PAD.y
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", NAME_SIZE)
	_speaker.add_theme_color_override("font_color", EDGE)
	column.add_child(_speaker)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(0, 76)
	_body.add_theme_font_size_override("font_size", LINE_SIZE)
	_body.add_theme_color_override("font_color", TEXT)
	column.add_child(_body)

	_replies = VBoxContainer.new()
	_replies.add_theme_constant_override("separation", 2)
	column.add_child(_replies)

	_prompt = Label.new()
	_prompt.text = "E"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.add_theme_font_size_override("font_size", REPLY_SIZE)
	_prompt.add_theme_color_override("font_color", DIM)
	column.add_child(_prompt)
