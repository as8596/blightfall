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

## The box is sized to what is in it rather than fixed. A pane with a one-line
## greeting and no replies used to draw the same 196px slab as one with three
## replies in it, and the empty two-thirds read as a layout bug.
##
## The floor is the portrait: the box can never be shorter than the frame on its
## left, plus its padding.
const MARGIN: float = 28.0
const PAD: Vector2 = Vector2(22.0, 16.0)

## The portrait frame, and the gap between it and the words.
const PORTRAIT: float = 96.0
const PORTRAIT_GAP: float = 16.0

## Where a villager's face is in the placeholder body strip — head and
## shoulders out of the 128x128 first frame. Real portraits, when they exist,
## come from the conversation file and are drawn whole.
const BUST := Rect2(32, 14, 64, 62)
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
## **One size for the whole box.**
##
## The font's grid gives 16 and 32 and nothing between (`ui/type_scale.gd`), so
## every attempt at hierarchy here is a 2x jump. 32 for the line made the
## replies at 16 read as a footnote; 32 for both made the box shout. There is no
## third option in the type, so the type stops trying.
##
## The hierarchy comes from the frames instead: the spoken line sits on the
## panel, the replies sit in boxes of their own, and the name is dimmer than
## either. That reads at a glance and costs nothing in legibility.
const NAME_SIZE: int = TypeScale.SMALL
const LINE_SIZE: int = TypeScale.SMALL
const REPLY_SIZE: int = TypeScale.SMALL

## A reply's own box, so the choice you are about to make has an edge round it.
const REPLY_PAD := Vector2(12.0, 4.0)
const REPLY_BACK := Color(0.14, 0.13, 0.11)
const REPLY_BACK_PICKED := Color(0.22, 0.19, 0.14)

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

## How many conversations each villager has had with the player, and which
## nodes they have already been through.
##
## **This is the difference between a village and a diorama.** Without it every
## NPC greets you as a stranger forever, which is the single loudest way a town
## admits it is a set — GDD §7 wants the same handful of people under increasing
## pressure, and people under pressure do not repeat their opening line.
##
## Two mechanisms, deliberately small:
##
## - a `revisit` node, used instead of `start` once you have spoken before, so a
##   villager can have a greeting and an afterwards;
## - `"once": true` on a node, which hides every reply leading to it after it has
##   been seen. That is the fox's rule from GDD §7 — *never repeats* — and it is
##   what stops a menu of questions you have already asked.
##
## Saved, because a conversation the player remembers and the game does not is
## worse than no memory at all.
var _visits: Dictionary = {}
var _seen: Dictionary = {}

var _root: Control
var _panel: Control
var _speaker: Label
var _body: Label
var _replies: VBoxContainer
var _prompt: Label
var _portrait: TextureRect
var _portrait_frame: Panel
var _column: VBoxContainer

## Cached per id. A conversation restarted forty times should not re-parse forty
## times, and these files never change at runtime.
var _library: Dictionary = {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(SaveGame.GROUP)
	_build()
	_root.visible = false
	set_process(false)


func save_id() -> StringName:
	return &"conversations"


func save_data() -> Dictionary:
	# String keys, because JSON has no other kind and a StringName round-tripping
	# through a save file comes back as a String regardless.
	var visits := {}
	for id in _visits:
		visits[String(id)] = int(_visits[id])
	var seen := {}
	for id in _seen:
		seen[String(id)] = (_seen[id] as Dictionary).keys()
	return {"visits": visits, "seen": seen}


func load_data(data: Dictionary) -> void:
	forget_conversations()
	for id in data.get("visits", {}):
		_visits[StringName(id)] = int((data["visits"] as Dictionary)[id])
	for id in data.get("seen", {}):
		var nodes := {}
		for node in (data["seen"] as Dictionary)[id]:
			nodes[String(node)] = true
		_seen[StringName(id)] = nodes


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
## `portrait` is {texture, region, tint}, as `Npc.portrait()` returns it. A
## conversation file may override it with a `"portrait"` path, which is drawn
## whole rather than cropped — that is the door real portrait art comes in by.
func start(id: StringName, portrait: Dictionary = {}) -> bool:
	if _open or Transition.is_busy() or PauseMenu.is_open() or GameMenu.is_open():
		return false
	var data := load_dialogue(id)
	if data.is_empty():
		return false
	_data = data
	_id = id
	# Clamped, because a speaker offset multiplies the sample's fundamental and
	# the deep voices were being pushed below what a laptop speaker reproduces.
	_voice_pitch = clampf(float(data.get("voice_pitch", 1.0)), 0.82, 1.45)
	_speaker.text = String(data.get("name", String(id)))
	_set_portrait(data, portrait)
	_open = true
	_root.visible = true
	get_tree().paused = true
	Hud.enabled = false
	set_process(true)
	_lock = 1
	# Somebody you have met opens differently, when the writing provides for it.
	var opening := String(data.get("start", "greeting"))
	var again := String(data.get("revisit", ""))
	if visits(id) > 0 and again != "" and (data.get("nodes", {}) as Dictionary).has(again):
		opening = again
	_visits[id] = visits(id) + 1
	_enter_node(opening)
	started.emit(id)
	return true


## How many times this conversation has been opened, ever.
func visits(id: StringName) -> int:
	return int(_visits.get(id, 0))


## Whether a node has been reached before. Replies into a `"once"` node are
## hidden once this is true.
func has_seen(id: StringName, node: String) -> bool:
	return (_seen.get(id, {}) as Dictionary).has(node)


## Wipe the memory. For tests, and for a new game — a fresh save must not start
## with the whole village already acquainted.
func forget_conversations() -> void:
	_visits.clear()
	_seen.clear()


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
	# Replies into a node already seen and marked `once` are dropped before the
	# player ever sees them, rather than greyed out. A greyed-out option is still
	# a thing to read past every single time.
	_choices = []
	for choice in node.get("choices", []):
		var target := String((choice as Dictionary).get("goto", ""))
		var destination: Dictionary = nodes.get(target, {})
		if bool(destination.get("once", false)) and has_seen(_id, target):
			continue
		_choices.append(choice)
	_line = 0
	if not _seen.has(_id):
		_seen[_id] = {}
	(_seen[_id] as Dictionary)[name] = true
	_start_line()


func _start_line() -> void:
	_shown = 0.0
	_blips = 0
	_body.text = String(_lines[_line]) if _line < _lines.size() else ""
	_body.visible_characters = 0
	_replies.visible = false
	_prompt.visible = false
	_fit_box()


## Fill the frame from the speaker, or leave it empty and say nothing about it.
func _set_portrait(data: Dictionary, portrait: Dictionary) -> void:
	var drawn := String(data.get("portrait", ""))
	if drawn != "" and ResourceLoader.exists(drawn):
		_portrait.texture = load(drawn)
		_portrait.modulate = Color.WHITE
		return
	var texture: Texture2D = portrait.get("texture")
	if texture == null:
		_portrait.texture = null
		return
	# Cropped to the bust. The placeholder body is a whole standing figure and a
	# whole standing figure in a 112px frame is a thumbnail of a person, not a
	# face.
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = portrait.get("region", BUST)
	_portrait.texture = atlas
	_portrait.modulate = portrait.get("tint", Color.WHITE)


## Height is content, not a constant.
##
## Measured rather than guessed: `get_multiline_string_size` gives the exact
## wrapped height of the line at the width it will actually be drawn at, so a
## one-line greeting gets a short box and a wrapped one gets a taller box, and
## neither gets the empty two-thirds the fixed height used to leave.
func _fit_box() -> void:
	if _panel == null or _root == null:
		return
	var text_width: float = maxf(_root.size.x - MARGIN * 2.0 - PAD.x * 2.0
		- PORTRAIT - PORTRAIT_GAP, 64.0)
	var font: Font = _body.get_theme_font(&"font")
	var line: float = float(LINE_SIZE) + 8.0
	if font != null and not _body.text.is_empty():
		line = font.get_multiline_string_size(_body.text, HORIZONTAL_ALIGNMENT_LEFT,
			text_width, LINE_SIZE).y + 8.0

	var content := PAD.y * 2.0 + float(NAME_SIZE) + 8.0 + line
	if _replies.visible and not _choices.is_empty():
		content += 6.0 + _choices.size() * (_reply_height() + 4.0)
	else:
		content += 10.0

	# Never shorter than the portrait it is standing next to.
	var height: float = maxf(content, PORTRAIT + PAD.y * 2.0)
	_panel.offset_top = -(height + MARGIN)


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
	_fit_box()


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


## Click anywhere on the box to do what the key does: finish the line if it is
## still typing, otherwise move on.
##
## The exception is while replies are up. There, a click on the box *behind* the
## replies is not an answer — the reply frames own their own clicks, and
## choosing the highlighted one on the player's behalf is a conversation they
## did not have. Finishing a still-typing line is still allowed, because that is
## not a choice.
func _on_box_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	# No `_lock` check here on purpose. The lock is a frame of deadband against
	# *polled* key state — the key that opened the box is still down on the frame
	# it opens — and a mouse button arrives as one discrete event that cannot
	# repeat itself. Honouring the lock here only ate clicks that landed on the
	# same frame as the press before them, which is most of the fast ones.
	if _replies.visible and not _typing():
		return
	_panel.accept_event()
	_advance()


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
					_voice_pitch, -3.0, 0.08)
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


## Each reply in its own frame, because a reply is a button whether or not it
## looks like one — a list of bare lines does not say "these are the things you
## can do", it says "more text".
##
## The chosen one gets a brighter edge, a lighter fill **and** a cursor. Three
## signals for one state is not redundancy: colour alone disappears on a bad
## monitor and for a colourblind player, and fill alone is invisible on a dark
## panel at a glance.
func _paint_replies() -> void:
	for child in _replies.get_children():
		child.queue_free()
	for i in _choices.size():
		var chosen := i == _choice
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(0, _reply_height())
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.add_theme_stylebox_override("panel",
			_frame(REPLY_BACK_PICKED if chosen else REPLY_BACK, PICKED if chosen else EDGE))

		var row := Label.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = REPLY_PAD.x
		row.offset_right = -REPLY_PAD.x
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.text = "%s %s" % ["\u25b8" if chosen else " ", String(_choices[i].get("text", "..."))]
		row.add_theme_font_size_override("font_size", REPLY_SIZE)
		row.add_theme_color_override("font_color", PICKED if chosen else TEXT)
		frame.add_child(row)
		# Pointable as well as keyable. A list of boxes that highlights one and
		# refuses to be clicked is a list that looks broken to anyone holding a
		# mouse, and the mouse is already how the hotbar is skimmed.
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.mouse_entered.connect(_point_at.bind(i))
		frame.gui_input.connect(_on_reply_input.bind(i))
		_replies.add_child(frame)
	_fit_box()


## Move the cursor without choosing. Hovering is the read; clicking is the write.
func _point_at(index: int) -> void:
	if not _replies.visible or index == _choice:
		return
	_choice = index
	Sfx.play(&"ui_move", -14.0)
	_paint_replies()


func _on_reply_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_choice = index
	_pick()


static func _reply_height() -> float:
	return float(REPLY_SIZE) + REPLY_PAD.y * 2.0 + 10.0


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
	_panel.offset_bottom = -MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _frame(BACK, EDGE))
	_panel.gui_input.connect(_on_box_input)
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = PAD.x
	row.offset_right = -PAD.x
	row.offset_top = PAD.y
	row.offset_bottom = -PAD.y
	row.add_theme_constant_override("separation", int(PORTRAIT_GAP))
	# PASS, not STOP: a click on the layout should reach the box behind it, or
	# click-to-advance would only work on the few pixels of visible padding.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(row)

	# The face, in its own frame on the left. Empty when nobody has one — a
	# frame with nothing in it still tells you where to look next time, and it
	# stops the text reflowing the day portraits arrive.
	_portrait_frame = Panel.new()
	_portrait_frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait_frame.add_theme_stylebox_override("panel", _frame(REPLY_BACK, EDGE))
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_portrait_frame)

	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 4.0
	_portrait.offset_top = 4.0
	_portrait.offset_right = -4.0
	_portrait.offset_bottom = -4.0
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_column)

	_speaker = Label.new()
	# The one word on screen you read as a name rather than as text.
	_speaker.add_theme_font_override("font",
		load("res://art/fonts/ui_display.tres") as Font)
	_speaker.add_theme_font_size_override("font_size", NAME_SIZE)
	_speaker.add_theme_color_override("font_color", EDGE)
	_column.add_child(_speaker)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", LINE_SIZE)
	_body.add_theme_color_override("font_color", TEXT)
	_column.add_child(_body)

	_replies = VBoxContainer.new()
	_replies.add_theme_constant_override("separation", 4)
	# The reply frames themselves STOP, so they still own their own clicks.
	_replies.mouse_filter = Control.MOUSE_FILTER_PASS
	_column.add_child(_replies)

	# Absolutely positioned rather than in the column, so a hint does not change
	# how tall the box is.
	_prompt = Label.new()
	_prompt.text = "E"
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_prompt.offset_left = -40.0
	_prompt.offset_top = -30.0
	_prompt.offset_right = -12.0
	_prompt.offset_bottom = -6.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.add_theme_font_size_override("font_size", TypeScale.SMALL)
	_prompt.add_theme_color_override("font_color", DIM)
	_panel.add_child(_prompt)


static func _frame(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(0)
	return box
