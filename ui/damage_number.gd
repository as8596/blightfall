class_name DamageNumber
extends Node2D
## The number that jumps off something you just hit.
##
## **The one piece of feedback that answers "is this working".** Hitstop, the
## flash and the knockback all say *something happened*; none of them say how
## much. Without a number the player cannot tell a hit from a good hit, cannot
## feel a weapon upgrade land, and cannot tell whether the wolf is taking four a
## swing or one.
##
## In world space, inside the SubViewport, rather than on a UI layer. It has to
## sit on the thing it describes and move with the camera; a number drawn at
## window resolution over a 1280x720 world would drift off its target the moment
## the camera panned.
##
## Lives for well under a second. A number that lingers is a number still on
## screen during the next three hits, and a combo that leaves six of them
## stacked is worse than none.

## How high it drifts and how long it lasts.
@export var rise: float = 26.0
@export var life: float = 0.55

## The sideways scatter, so two hits in the same place do not print one number on
## top of another.
@export var spread: float = 14.0

## Damage the player dealt, and damage they took. Two colours because they are
## two different pieces of news and the player reads them at a glance, in the
## middle of something else.
const DEALT := Color(0.96, 0.93, 0.84)
const TAKEN := Color(0.86, 0.32, 0.26)

const FONT: Font = preload("res://art/fonts/ui_display.tres")
const SIZE: int = TypeScale.SMALL

var _text: String = ""
var _colour: Color = DEALT
var _t: float = 0.0
var _drift: float = 0.0


## Spawn one into `parent` at `where`. Static because every caller wants the
## whole ceremony — make it, place it, start it — and none of them wants three
## lines of it.
static func pop(parent: Node, where: Vector2, amount: int, dealt: bool = true) -> DamageNumber:
	var number := DamageNumber.new()
	number._text = str(amount)
	number._colour = DEALT if dealt else TAKEN
	# Through `Rng`, like everything else that rolls (GDD §12 rule 5).
	number._drift = Rng.randf_range(-number.spread, number.spread)
	parent.add_child(number)
	number.global_position = where
	return number


func _ready() -> void:
	# Above the actors, but still inside the world so it moves with the camera.
	z_index = 2
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_t / maxf(life, 0.001), 0.0, 1.0)
	# Fast at first, then slowing — it is thrown off the impact rather than
	# floated up from it.
	var eased := 1.0 - pow(1.0 - progress, 2.0)
	var offset := Vector2(_drift * eased, -rise * eased)
	# Fades only in the last third. Fading from the moment it appears makes the
	# number hardest to read exactly when it is newest.
	var alpha := 1.0 - clampf((progress - 0.66) / 0.34, 0.0, 1.0)

	var width := FONT.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var at := offset - Vector2(width * 0.5, 0.0)
	# A dark copy one pixel down and right, so a pale number stays legible over
	# pale ground. Cheaper and crisper than an outline on a pixel font.
	draw_string(FONT, at + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE,
		Color(0.05, 0.04, 0.04, alpha * 0.85))
	draw_string(FONT, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE,
		Color(_colour.r, _colour.g, _colour.b, alpha))
