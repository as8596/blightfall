class_name RangedWeaponData
extends Resource
## What a bow does, as opposed to what a bow is.
##
## The item is an `ItemData` like everything else — it has an icon, a price and a
## slot, and the shop and the pack know nothing about bows. This is the half that
## only the draw state cares about, hung off the item by one field, the same way
## `EnemyData.animations` hangs a sprite set off an enemy without every enemy
## needing one.
##
## **A separate resource rather than fields on `ItemData`** because there are
## fifty items and two of them are bows. Nine more exports on `ItemData` would be
## nine more rows of nothing in the inspector for a loaf of bread, and the first
## crossbow would want a tenth.
##
## ## The draw is the weapon
##
## Everything here is really about one question: what does holding the button
## longer buy you? A bow that fires the same arrow whether you tapped or held is
## a slow gun. So a short draw looses a weak, slow arrow and a full draw looses a
## fast, hard one, and the interesting range is the middle — a snapshot at a wolf
## already on top of you, against a considered shot at one that has not seen you.
##
## The sword's charge is a different animal and deliberately so: it is a beat of
## commitment on top of a swing that already happened. This one *is* the shot.

## Seconds from the press to a full draw.
##
## Long enough to be a decision and short enough not to be a channel. Compare
## `Player.CHARGE_TIME` at 0.45 for the heavy swing — the bow is slower, because
## the bow's whole proposition is that you are spending time to buy distance.
@export var draw_time: float = 0.62

## Damage at a full draw, before the damage stat.
@export var damage: int = 7

## Fraction of that a snapshot does. The floor, at zero draw.
##
## Not zero: an arrow loosed off a twitch should be worth something, or the only
## correct play is always to hold, and the tap stops being a choice. Not close to
## one either, for the same reason in reverse.
@export_range(0.05, 1.0, 0.05) var snap_damage_scale: float = 0.35

## Pixels per second at a full draw, and the same fraction of it at none. Speed
## and damage move together on purpose — a weak arrow is also a slow arrow, so
## the shot you rushed is the shot the wolf walks out of.
@export var arrow_speed: float = 880.0
@export_range(0.05, 1.0, 0.05) var snap_speed_scale: float = 0.45

## How far an arrow flies before it drops. Measured, not felt: 1280x720 is the
## world viewport, so 640 is exactly half the screen and anything beyond about
## 900 is a shot at something the player cannot see.
@export var range_px: float = 760.0

## Radians of scatter at no draw, falling to zero at a full one.
##
## This is what stops spamming taps from being the optimal play, and it does it
## without a cooldown — a rushed arrow goes roughly where you pointed, and a
## drawn one goes exactly there.
@export var max_spread: float = 0.13

## Seconds of recovery after the loose, before you can move or shoot freely.
## Short; the commitment in a bow is the draw, not the follow-through.
@export var recovery: float = 0.18

## Fraction of walk speed kept while drawing. A drawn bow should slow you without
## rooting you — rooted, every fight becomes "back up, stop, shoot", and the
## stopping is what makes that boring.
@export_range(0.0, 1.0, 0.05) var draw_move_scale: float = 0.45

## What it fires, by item id. A bow with no ammo in the pack cannot be drawn.
@export var ammo_id: StringName = &"arrow"

## Knockback on hit, in pixels. Lower than the sword's finisher: an arrow does
## not shove a wolf, it sticks in one.
@export var knockback_distance: float = 6.0

@export_group("Feel")
@export var hitstop: float = 0.04
@export var draw_sfx: StringName = &"ui_select"
@export var loose_sfx: StringName = &"swing_light"
@export var impact_sfx: StringName = &"impact_light"


## How far along the draw `held` seconds gets you, 0 to 1.
func draw_fraction(held: float) -> float:
	if draw_time <= 0.0:
		return 1.0
	return clampf(held / draw_time, 0.0, 1.0)


## Damage for a draw of `fraction`, before the damage stat is added.
func damage_at(fraction: float) -> int:
	var scale := lerpf(snap_damage_scale, 1.0, clampf(fraction, 0.0, 1.0))
	return maxi(int(round(float(damage) * scale)), 1)


func speed_at(fraction: float) -> float:
	return arrow_speed * lerpf(snap_speed_scale, 1.0, clampf(fraction, 0.0, 1.0))


## Scatter for a draw of `fraction`, in radians either side of true.
func spread_at(fraction: float) -> float:
	return max_spread * (1.0 - clampf(fraction, 0.0, 1.0))
