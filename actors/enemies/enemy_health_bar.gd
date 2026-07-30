class_name EnemyHealthBar
extends Node2D
## How hurt the thing in front of you is.
##
## **Without this the player cannot make the only decision a fight offers.**
## Every choice in combat — press or back off, spend the stamina on a third hit
## or keep it for the dodge — depends on knowing whether the wolf is one swing
## from dead or five. The debug overlay showed it; the game did not.
##
## **Hidden until damaged, then fades.** A bar over every enemy at all times is
## a HUD stapled to the world: it turns a wood full of animals into a wood full
## of health bars, and it tells you nothing you did not already know about an
## enemy at full health. Appearing on the first hit makes the bar *information
## the player earned*, and fading afterwards means a pack you have disengaged
## from stops shouting at you.
##
## Drawn rather than a TextureProgressBar for the same reason `WeaponArc` is
## drawn: it is nine pixels tall, it has no art, and a Control in world space
## would need its own transform plumbing to sit above a moving actor.

## Bar size in pixels, and how far above the actor's origin it floats.
@export var size: Vector2 = Vector2(40.0, 5.0)
@export var lift: float = 16.0

## Seconds the bar stays up after the last hit, and how long it takes to fade.
##
## Long enough to still be there when you look back after a dodge; short enough
## that a fight you walked away from does not follow you across the screen.
@export var linger: float = 2.5
@export var fade: float = 0.4

const BACK := Color(0.08, 0.07, 0.06, 0.85)
const EDGE := Color(0.02, 0.02, 0.02, 0.9)
const FILL := Color(0.72, 0.24, 0.20)
## The last sliver reads differently, so "nearly dead" is a colour and not an
## exercise in measuring a bar against its own width.
const FILL_LOW := Color(0.86, 0.44, 0.16)
const LOW_FRACTION := 0.34

var _health: HealthComponent
var _shown: float = 0.0
var _fraction: float = 1.0


func _ready() -> void:
	visible = false
	set_process(false)
	# Above the body it belongs to, but still sorted with it — a bar that
	# ignored y-sorting would draw through the tree the wolf is standing behind.
	z_index = 1
	top_level = false


## Attach to a health component and start listening. Called by `BaseEnemy` once
## its data has been applied, because `lift` depends on how tall the thing is.
func watch(health: HealthComponent, body_height: float) -> void:
	_health = health
	position = Vector2(0.0, -body_height - lift)
	if health == null:
		return
	health.changed.connect(_on_changed)
	health.died.connect(_on_died)
	_fraction = health.fraction()


func _on_changed(current: int, max_health: int) -> void:
	var was := _fraction
	_fraction = clampf(float(current) / maxf(float(max_health), 1.0), 0.0, 1.0)
	# Only surface on a *loss*. Healing an enemy — or the initial push when its
	# data is applied — is not something the player did and not something they
	# need told about.
	if _fraction >= was:
		queue_redraw()
		return
	_shown = linger + fade
	visible = true
	set_process(true)
	queue_redraw()


func _on_died() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_shown = maxf(_shown - delta, 0.0)
	modulate.a = clampf(_shown / maxf(fade, 0.001), 0.0, 1.0)
	if _shown <= 0.0:
		visible = false
		set_process(false)


func _draw() -> void:
	var half := size.x * 0.5
	var frame := Rect2(Vector2(-half - 1.0, -1.0), size + Vector2(2.0, 2.0))
	draw_rect(frame, EDGE, true)
	draw_rect(Rect2(Vector2(-half, 0.0), size), BACK, true)
	if _fraction <= 0.0:
		return
	var fill := FILL_LOW if _fraction <= LOW_FRACTION else FILL
	draw_rect(Rect2(Vector2(-half, 0.0), Vector2(size.x * _fraction, size.y)), fill, true)


## Whether the bar is currently on screen. For the tests, which otherwise have to
## reach into `visible` and a timer to ask one question.
func is_showing() -> bool:
	return visible and _shown > 0.0
