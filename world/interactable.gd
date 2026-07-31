class_name Interactable
extends Area2D
## Something the player can stop and act on: a door, a plot, a person.
##
## The counterpart to `world/pickup.gd`. Materials are the routine currency of
## an expedition and are walked over, because a button press forty times a run
## is a tax rather than a decision. This is the other half of that rule — the
## things worth stopping for.
##
## **Detected, not detecting.** An Interactable sits on the Interactable physics
## layer and monitors nothing; the player's `InteractorComponent` does the
## looking. That is also why `Pickup` and `HaulCache` never show a prompt
## despite sharing the layer: both set `monitorable = false`, so nothing can
## find them by looking, only by touching.

## Emitted when the player acts on this. Connect rather than subclass for
## one-off behaviour.
signal interacted(actor: Node)

## Physics layer 8, named "Interactable" in project.godot.
const LAYER: int = 128

## What the prompt says. A verb, because the player is choosing to do a thing.
@export var prompt: String = "Examine"

## Off means no prompt and no response — a door that is locked, a plot whose
## prerequisite is not built. Still present, still visible in the world.
@export var enabled: bool = true

## Where the prompt floats, relative to this node. Default clears a 96px tall
## character standing on the same tile.
@export var prompt_offset: Vector2 = Vector2(0, -84)

var _label: Label
var _key: Sprite2D


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build_label()


## Override for conditions — a project that needs the wall repaired first, an
## NPC with nothing left to say.
func can_interact(_actor: Node) -> bool:
	return enabled


## Override to do the thing. Call `super()` to keep the signal.
func interact(actor: Node) -> void:
	if not can_interact(actor):
		return
	interacted.emit(actor)


## Shown when this is the thing the player would act on. Driven by
## `InteractorComponent`; nothing else should call it.
func set_highlighted(on: bool) -> void:
	var lit := on and enabled
	if _label != null:
		_label.visible = lit
	if _key != null:
		_key.visible = lit


## The prompt: a keycap and a verb.
##
## **The verb alone was never enough.** It said "Talk" and "Enter" and "Search"
## and never once said which button — while every other affordance in the game
## labels its binding, the hotbar with its numbers and the weapon plate with its
## Q. The prompt is the one place a player is actively asking "how do I do this"
## and it was the one place that did not answer.
##
## The keycap is art rather than a drawn box, so it reads as a key at a glance
## instead of as another word. It is drawn at a third of its own size: 72px is a
## key you could press with your thumb, and this sits above a 96px character.
const KEY_SIZE: float = 26.0
const KEY_GAP: float = 6.0


func _build_label() -> void:
	_label = Label.new()
	_label.name = "Prompt"
	_label.text = prompt
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Fixed box centred on this node, so the text grows in both directions
	# instead of shunting sideways as the verb changes. Nudged right by half the
	# keycap plus its gap, so the pair is centred rather than the words alone.
	_label.size = Vector2(192, 24)
	_label.position = prompt_offset - Vector2(96, 12) \
		+ Vector2((KEY_SIZE + KEY_GAP) * 0.5, 0.0)
	_label.visible = false
	# Drawn above the world regardless of where it sits in the y-sort. A prompt
	# that a wall can occlude is a prompt that vanishes exactly when the player
	# is close enough to use it.
	_label.z_index = 100
	_label.z_as_relative = false

	var settings := LabelSettings.new()
	settings.font = ThemeDB.fallback_font
	settings.font_size = 16
	settings.font_color = Color(0.97, 0.94, 0.86)
	settings.outline_size = 5
	settings.outline_color = Color(0.06, 0.05, 0.05, 0.9)
	_label.label_settings = settings

	add_child(_label)

	# Left of the words, on the same baseline. Placed off the *measured* width of
	# the text rather than off the label's fixed 192px box, which is deliberately
	# far wider than any verb.
	var words := settings.font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, settings.font_size).x if settings.font != null else 40.0
	_key = Sprite2D.new()
	_key.name = "PromptKey"
	_key.texture = UiKit.KEY_E
	_key.centered = true
	var native := _key.texture.get_size().x if _key.texture != null else KEY_SIZE
	_key.scale = Vector2.ONE * (KEY_SIZE / maxf(native, 1.0))
	_key.position = prompt_offset + Vector2(
		-(words + KEY_GAP) * 0.5, 0.0)
	_key.visible = false
	_key.z_index = 100
	_key.z_as_relative = false
	add_child(_key)
