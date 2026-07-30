class_name TelegraphMarker
extends Node2D
## The ground the enemy is about to be standing on.
##
## GDD §5's enemy rule 1 already demanded a distinct colour and pose, and the
## telegraph state has both. What neither of them says is **where** — a wolf
## flashing yellow tells you something is coming; it does not tell you that
## stepping left is safe and stepping back is not. Against one enemy you can
## infer it from the facing. Against three, arriving from three directions, you
## cannot, and the fight becomes about panic-dodging on a timer.
##
## So this draws the lunge itself: a band from the enemy out to where the lunge
## ends, filling from the near end as the wind-up runs out. The fill *is* the
## clock — the player reads distance and timing off one shape instead of
## watching a colour and counting.
##
## Drawn under the actors (`z_index` below zero) so it never covers the thing it
## is warning about, and cleared the instant the state exits.

## Widened slightly past the hitbox so the band is not a promise the attack
## fails to keep at the edges — better to over-warn than to clip somebody who
## trusted it.
@export var width_margin: float = 8.0

const EDGE := Color(0.88, 0.74, 0.28, 0.85)
const FILL := Color(0.86, 0.68, 0.22, 0.20)
const SWEPT := Color(0.90, 0.55, 0.18, 0.45)

var _length: float = 0.0
var _width: float = 0.0
var _progress: float = 0.0
var _showing: bool = false


func _ready() -> void:
	# Under the actors. A warning that hides the enemy is not a warning.
	z_index = -1
	visible = false


## Show the band for an attack of this reach and width, pointing along `facing`.
func begin(facing: Vector2, length: float, width: float) -> void:
	_length = maxf(length, 1.0)
	_width = maxf(width, 1.0) + width_margin * 2.0
	_progress = 0.0
	_showing = true
	visible = true
	rotation = facing.angle()
	queue_redraw()


## How far through the wind-up we are, 0 to 1. Called every frame by the
## telegraph state rather than run off a timer here, so the bar and the state
## cannot disagree about how long is left.
func advance(fraction: float) -> void:
	if not _showing:
		return
	_progress = clampf(fraction, 0.0, 1.0)
	queue_redraw()


func finish() -> void:
	_showing = false
	visible = false
	queue_redraw()


func is_showing() -> bool:
	return _showing


func _draw() -> void:
	if not _showing:
		return
	var half := _width * 0.5
	var band := Rect2(0.0, -half, _length, _width)
	draw_rect(band, FILL, true)
	# The part already "swept" by the wind-up, which is the timer.
	if _progress > 0.0:
		draw_rect(Rect2(0.0, -half, _length * _progress, _width), SWEPT, true)
	draw_rect(band, EDGE, false, 2.0)
