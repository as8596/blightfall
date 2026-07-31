class_name PlayerDrawState
extends PlayerState
## Drawing and loosing a bow.
##
## Timeline, `t` from the press:
##
##   0 ────────────── draw_time ──────────╮
##   │ spread wide, damage low            │ full draw, cue plays
##   │ ← release anywhere along here ─────┘
##   ▼
##   loose ──── recovery ──── end
##
## ## Why this is not the Attack state with a flag on it
##
## `PlayerAttackState` runs a fixed timeline: the swing takes as long as the
## frame data says and the player is a passenger from the moment they press. A
## bow inverts that — **the player decides when it ends**, and the state has to
## be willing to sit in the draw indefinitely. Bolting that onto a state whose
## every branch is `_t >= some_number` would have meant a second set of branches
## that ignore all the first ones.
##
## ## The arrow is spent on the loose, not on the draw
##
## So a draw you thought better of costs nothing. That matters because the other
## way round teaches the player not to draw speculatively, and drawing
## speculatively — nocking one while you back away from something — is the good
## part of having a bow.
##
## Dodge cancels the draw at any point, for the same reason: the bow must never
## be the reason you could not get out of the way.

var _weapon: RangedWeaponData
var _bow: ItemData
var _held: float = 0.0
var _loosed: bool = false
var _recovery: float = 0.0
## Cue played once, at the moment the draw comes good.
var _announced: bool = false


func enter(_msg: Dictionary = {}) -> void:
	_bow = player.drawn_bow()
	_weapon = _bow.ranged if _bow != null else null
	_held = 0.0
	_loosed = false
	_recovery = 0.0
	_announced = false
	if _weapon == null or player.arrow_scene == null or player.arrows_left() <= 0:
		# Nothing to fire, or nothing to fire it from. Refuse audibly and step
		# straight back out — an empty quiver that fails silently reads as the
		# game having dropped the click.
		Sfx.play(&"ui_deny", -6.0)
		Events.player_item_refused.emit(-1)
		return_to_locomotion()
		return
	player.face_aim()
	player.animation.set_manual_frame(0)


func exit() -> void:
	player.animation.set_manual_frame(0)


func physics_update(delta: float) -> void:
	if _weapon == null:
		return_to_locomotion()
		return

	# Recovery: the shot is gone and the only thing left is the beat afterwards.
	if _loosed:
		_recovery -= delta
		player.apply_motion(delta, player.desired_walk_velocity(_weapon.draw_move_scale))
		if player.can_dodge() and player.input.consume_dodge():
			state_machine.transition_to(&"Dodge")
			return
		if _recovery <= 0.0:
			return_to_locomotion()
		return

	_held += delta
	var drawn := _weapon.draw_fraction(_held)

	# **Aim tracks the cursor for the whole draw**, unlike a swing, which commits
	# its direction at the wind-up. A drawn bow you cannot re-point is a bow that
	# only ever hits things that stand still.
	player.face_aim()
	player.apply_motion(delta, player.desired_walk_velocity(_weapon.draw_move_scale))

	if not _announced and drawn >= 1.0:
		_announced = true
		Sfx.play(&"bow_draw", -3.0)
		if player.flash != null:
			player.flash.flash(0.14)

	player.animation.set_manual_frame(1 if drawn >= 1.0 else 0)

	# Dodge out. Costs nothing — the arrow has not been spent yet.
	if player.can_dodge() and player.input.consume_dodge():
		state_machine.transition_to(&"Dodge")
		return

	# The release is the shot. Read off the held flag rather than a buffered
	# press: this is the one verb in the game driven by letting go.
	if not player.input.intent.attack_held:
		_loose(drawn)


func _loose(drawn: float) -> void:
	_loosed = true
	_recovery = _weapon.recovery
	# Take the arrow first. If the pack somehow cannot pay — a save loaded
	# mid-draw, a script that emptied it — nothing is fired and the state ends
	# rather than producing a free shot.
	if not player.spend_arrow():
		Sfx.play(&"ui_deny", -6.0)
		return_to_locomotion()
		return

	var heading := player.aim_direction()
	var spread := _weapon.spread_at(drawn)
	if spread > 0.0:
		heading = heading.rotated(Rng.randf_range(-spread, spread))

	# Out at the bow, and **at chest height**.
	#
	# The forward offset is the obvious half: without it the arrow spawns inside
	# the player's own body, and since a hitbox cannot hit its own source it
	# silently passes through anything standing on top of them.
	#
	# The vertical offset is the half that was missing, and it made every single
	# shot miss. A player's `global_position` is at their *feet* — that is the
	# y-sort convention the whole game is built on — while an enemy's hurtbox
	# sits well above its own feet. Launched from the origin, an arrow flies
	# along the ground and passes under every hurtbox in the game by a couple of
	# pixels. It looked exactly like an arrow going through a wolf.
	#
	# Read off the player's own melee hitbox rather than written down again, so
	# the bow shoots along the same line the sword swings on and the two cannot
	# drift apart: anything the sword can reach, the bow can hit.
	var height := player.hitbox.position.y if player.hitbox != null else DEFAULT_HEIGHT
	var muzzle := player.global_position + Vector2(0.0, height) + heading * MUZZLE_OFFSET
	@warning_ignore("return_value_discarded")
	Arrow.launch(player.arrow_scene, player.get_parent(), muzzle, heading,
		_weapon, drawn, player, player.stats.bonus(StatsComponent.DAMAGE))
	if _weapon.loose_sfx != &"":
		Sfx.play(_weapon.loose_sfx)


## How far in front of the player an arrow appears, in pixels. Just outside the
## body collider, so a shot at point-blank range still starts in the open.
const MUZZLE_OFFSET: float = 26.0

## Fallback launch height, for a player with no hitbox to measure. Negative is
## up: this is chest height, not ground level.
const DEFAULT_HEIGHT: float = -48.0


## For the debug overlay: how far into the draw, 0 to 1.
func drawn_fraction() -> float:
	if _weapon == null:
		return 0.0
	return _weapon.draw_fraction(_held)
