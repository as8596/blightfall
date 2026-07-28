class_name StaminaWheel
extends Node2D
## A ring around the character's feet that drains as they dash, and is not there
## the rest of the time.
##
## On the actor rather than in the HUD, which is both the faithful reading of
## the *Breath of the Wild* wheel and the only version that obeys GDD §12 rule 1:
## a screen-corner gauge would have to find the player, and nothing is allowed to
## look the player up. As a child it simply asks its sibling.
##
## **Only visible while spent.** GDD §6 calls stamina "a rhythm limiter that
## stops panic-rolling, not a resource to manage" — a gauge sitting permanently
## full is one the eye stops seeing, which is the opposite of a limiter. It
## appears when you spend and fades once you are whole again.
##
## **Deliberately not green.** The obvious colour for a stamina wheel is the one
## the blight owns (GDD §15 A5 reserves hue 60–100° above 55% saturation, and
## `tools/check_colour.py` enforces it on art). Nothing else in this game gets to
## be that colour, including UI drawn in code where no tool would catch it.

## The component to read. Left empty, it finds one on the parent.
@export var stamina_path: NodePath

@export var radius: float = 30.0
@export var thickness: float = 5.0

## Centred just above the feet, so the ring reads as being around the character
## rather than as a hat.
@export var offset: Vector2 = Vector2(0.0, -10.0)

## Seconds to fade out once stamina is full again, and to fade in when it is not.
@export var fade_time: float = 0.35

@export var track_color: Color = Color(0.10, 0.10, 0.12, 0.65)
@export var fill_color: Color = Color(0.62, 0.80, 0.86)
## Flashed when a dash is refused for want of stamina — the one moment the
## limiter actually bites, and the only time it should raise its voice.
@export var empty_color: Color = Color(0.86, 0.45, 0.30)

var _stamina: StaminaComponent
var _alpha: float = 0.0
var _complain: float = 0.0


func _ready() -> void:
	# Above the world, like the interact prompt. A gauge a fence can hide is a
	# gauge that vanishes exactly when you are somewhere interesting.
	z_index = 100
	z_as_relative = false
	_stamina = get_node_or_null(stamina_path) as StaminaComponent
	if _stamina == null:
		_stamina = _find_on_parent()
	if _stamina == null:
		set_process(false)
		return
	_stamina.refused.connect(_on_refused)


func _process(delta: float) -> void:
	var spent := _stamina.current < _stamina.max_stamina - 0.001
	var target: float = 1.0 if spent else 0.0
	_alpha = move_toward(_alpha, target, delta / maxf(fade_time, 0.001))
	_complain = maxf(_complain - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.001 or _stamina == null or _stamina.max_stamina <= 0.0:
		return

	var ratio: float = clampf(_stamina.current / _stamina.max_stamina, 0.0, 1.0)
	var track := track_color
	track.a *= _alpha
	draw_arc(offset, radius, 0.0, TAU, 48, track, thickness, false)

	if ratio <= 0.0:
		return
	var colour := empty_color if _complain > 0.0 else fill_color
	colour.a *= _alpha
	# Clockwise from the top, so it empties the way a clock face would.
	var start := -PI * 0.5
	draw_arc(offset, radius, start, start + TAU * ratio, 48, colour, thickness, false)


func _on_refused(_amount: float) -> void:
	_complain = 0.5
	_alpha = 1.0


func _find_on_parent() -> StaminaComponent:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		var component := child as StaminaComponent
		if component != null:
			return component
	return null
