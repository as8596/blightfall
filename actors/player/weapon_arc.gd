class_name WeaponArc
extends Node2D
## The blade, and the smear it leaves behind it.
##
## Drawn rather than animated, and for a specific reason: the character sprite
## is four-directional (down, up, side, side flipped) but the swing aims at the
## cursor through a full 360°. Baking 360° of swing frames into a sprite sheet
## is not a thing anyone should do, so the *body* keeps its four directions and
## the *weapon* is a separate thing that can point anywhere.
##
## The trail is what makes a 0.10s active window legible. GDD §5 gives hit 1
## eight hundredths of a second of windup and a tenth of active frames — far too
## fast to read as a pose, and about right to read as a streak.

## Where the blade starts and ends, measured out from the character's centre.
@export var inner_radius: float = 26.0
@export var outer_radius: float = 78.0

## How far the swing travels, in degrees. Wider reads as heavier.
@export var arc_degrees: float = 110.0

## How far behind the blade the smear reaches, as a fraction of the arc.
@export_range(0.0, 1.0, 0.05) var trail_fraction: float = 0.55

## Segments in the smear. More is smoother and costs a polygon each.
@export_range(3, 24) var trail_samples: int = 12

@export var blade_color: Color = Color(0.94, 0.95, 0.98, 0.95)
@export var trail_color: Color = Color(0.80, 0.86, 0.95, 0.42)

var _from: float = 0.0
var _to: float = 0.0
var _t: float = 0.0
var _duration: float = 0.0
var _reach: float = 1.0


func _ready() -> void:
	# Above the body, and not sorted with it — a slash that disappears behind
	# the shoulder it came from is worse than no slash.
	z_index = 20
	z_as_relative = true
	set_process(false)
	visible = false


## Sweep from `centre_angle` through `arc_degrees`, over `duration` seconds.
## `clockwise` alternates per combo hit, so a three-hit string reads as three
## different motions rather than the same one three times.
func swing(centre_angle: float, duration: float, clockwise: bool = true,
		reach_scale: float = 1.0) -> void:
	var half := deg_to_rad(arc_degrees) * 0.5
	var direction := 1.0 if clockwise else -1.0
	_from = centre_angle - half * direction
	_to = centre_angle + half * direction
	_duration = maxf(duration, 0.001)
	_reach = reach_scale
	_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


## The middle of the sweep — what the swing is pointed at, whichever way round
## this particular hit travels.
func centre_angle() -> float:
	return _from + angle_difference(_from, _to) * 0.5


func stop() -> void:
	set_process(false)
	visible = false
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		stop()
		return
	queue_redraw()


func _draw() -> void:
	if _duration <= 0.0:
		return
	var progress: float = clampf(_t / _duration, 0.0, 1.0)
	var angle := lerp_angle(_from, _to, progress)
	var span := angle_difference(_from, _to) * trail_fraction

	# Fades out across the swing as well as along the trail, so the smear thins
	# rather than vanishing on the last frame.
	var life := 1.0 - progress * 0.35
	var inner := inner_radius * _reach
	var outer := outer_radius * _reach

	for i in trail_samples:
		var a0: float = angle - span * (float(i) / float(trail_samples))
		var a1: float = angle - span * (float(i + 1) / float(trail_samples))
		var fade: float = (1.0 - float(i) / float(trail_samples)) * life
		var colour := trail_color
		colour.a *= fade * fade
		draw_colored_polygon(PackedVector2Array([
			Vector2(cos(a0), sin(a0)) * inner,
			Vector2(cos(a0), sin(a0)) * outer,
			Vector2(cos(a1), sin(a1)) * outer,
			Vector2(cos(a1), sin(a1)) * inner,
		]), colour)

	var edge := blade_color
	edge.a *= life
	draw_line(Vector2(cos(angle), sin(angle)) * inner,
		Vector2(cos(angle), sin(angle)) * outer, edge, 3.0)
