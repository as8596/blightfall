class_name Arrow
extends Hitbox
## A loosed arrow: the first hit in this game that is not attached to whoever
## threw it.
##
## **It is a `Hitbox` rather than a thing that owns one.** Everything a hit needs
## already lives on that class — damage, knockback, hitstop, shake, one-hit-per-
## target, the impact SFX layer, the debug draw, and the rule that you cannot hit
## your own source. An arrow is a hitbox that moves and then stops existing, so
## it inherits rather than growing a second, subtly different version of all of
## that.
##
## ## Three ways it ends, and none of them is "forever"
##
## It hits something, it hits a wall, or it runs out of range. That last one is
## the one worth having a number for: an arrow with no limit is a projectile that
## leaves the level, keeps ticking, and turns up in a room the player walked away
## from two minutes ago.
##
## ## What it can touch
##
## The mask does the filtering, so there is no layer test in here. `Arrow.tscn`
## masks World and EnemyHurtbox and nothing else, which means every `body_entered`
## is a wall by construction and every `area_entered` is something it may hurt.
## An enemy archer would flip EnemyHurtbox to PlayerHurtbox on its own scene and
## change nothing in this file.
##
## `source` is whoever loosed it, exactly as for a swing, so XP, damage numbers
## and `Events.hit_landed` all still name the right actor.

## Pixels travelled so far, against the range it was given.
var travelled: float = 0.0
var range_px: float = 760.0

## Pixels per second along `direction`. Both set by `launch`.
var speed: float = 880.0
var direction: Vector2 = Vector2.RIGHT

## Cleared the moment it lands or expires, so a tick that both hits something and
## reaches its range does not do two endings.
var _flying: bool = false


## Put one in the world, pointed and moving.
##
## A static rather than something each caller assembles: an arrow with no
## `source` hits the person who fired it, and one whose rotation was never
## applied is drawn sideways for its whole flight. Both have exactly one right
## answer, so it is given here once.
static func launch(scene: PackedScene, parent: Node, from: Vector2,
		heading: Vector2, weapon: RangedWeaponData, drawn: float,
		shooter: Node, damage_bonus: int = 0) -> Arrow:
	if scene == null or parent == null or weapon == null:
		return null
	var arrow := scene.instantiate() as Arrow
	if arrow == null:
		return null
	arrow.source = shooter
	arrow.direction = heading.normalized()
	arrow.speed = weapon.speed_at(drawn)
	arrow.range_px = weapon.range_px
	arrow.damage = maxi(weapon.damage_at(drawn) + damage_bonus, 1)
	arrow.knockback_distance = weapon.knockback_distance
	arrow.hitstop = weapon.hitstop
	arrow.impact_sfx = weapon.impact_sfx
	arrow.global_position = from
	arrow.rotation = arrow.direction.angle()
	parent.add_child(arrow)
	return arrow


func _ready() -> void:
	super()
	# Live from the first frame. Unlike a swing, nothing is going to come along
	# and switch this on for a window of active frames — the flight *is* the
	# window.
	activate()
	_flying = true
	set_physics_process(true)
	hit_landed.connect(_on_hit_landed)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# The base class owns a one-tick overlap sweep on activation and switches its
	# own processing off again afterwards. Calling it first keeps that sweep — an
	# arrow that spawns already inside a wolf still hits it — and re-arming below
	# is what stops its shutdown from ending the flight on tick one.
	super(delta)
	if not _flying:
		return
	set_physics_process(true)
	var step := speed * delta
	global_position += direction * step
	travelled += step
	if travelled >= range_px:
		_stop()


## Hit something that can be hurt. Arrows do not pierce: the first thing it
## reaches is the thing it is now stuck in.
func _on_hit_landed(_hurtbox: Hurtbox) -> void:
	_stop()


## Hit the world. The mask only admits World bodies, so there is nothing to test.
##
## This one gets a sound and running out of range does not, and the difference is
## distance: a shot that clatters off a wall is a shot the player took from close
## enough to hear it, and one that expired mid-air is 760px away by definition.
## `Sfx` is not positional, so anything played here is played at full volume in
## the player's ear whether they could plausibly hear it or not.
func _on_body_entered(_body: Node2D) -> void:
	if _flying:
		Sfx.play(&"arrow_miss", -4.0)
	_stop()


func _stop() -> void:
	if not _flying:
		return
	_flying = false
	deactivate()
	set_physics_process(false)
	queue_free()


func is_flying() -> bool:
	return _flying
