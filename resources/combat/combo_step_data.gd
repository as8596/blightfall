class_name ComboStepData
extends Resource
## One hit of the player's three-hit combo (GDD §5, frame data).
##
## All timings in seconds, measured from the moment the hit starts. Recovery
## begins at `windup + active`; the combo window closes
## `PlayerComboData.combo_window_after_recovery` after that.

@export_group("Frame data")
## Time before the hitbox turns on.
@export var windup: float = 0.08
## Time the hitbox stays on.
@export var active: float = 0.10
## Time after the hitbox turns off before the state ends.
@export var recovery: float = 0.16

@export_group("Damage")
@export var damage: int = 4
## Pixels of knockback. GDD §5: 12–20px, final hit only.
@export var knockback_distance: float = 0.0

@export_group("Cancels")
## Earliest time (from hit start) this hit can be cancelled into the next one.
## Negative = this hit commits and cannot chain — the third hit's whole point.
@export var cancel_into_next_at: float = 0.12
## Fraction of walk speed retained. GDD §5: 25% on hits 1–2, 0% on hit 3.
@export_range(0.0, 1.0, 0.05) var move_speed_scale: float = 0.25

@export_group("Feel")
## GDD §5: 0.05s on hits 1–2, 0.10s on hit 3.
@export var hitstop: float = 0.05
## GDD §5: 2px on heavy hits only.
@export var screen_shake: float = 0.0
@export var swing_sfx: StringName = &"swing_light"
@export var impact_sfx: StringName = &"impact_light"

@export_group("Hitbox")
@export var hitbox_size: Vector2 = Vector2(22, 20)
## Distance from the actor's origin to the hitbox centre, along facing.
@export var hitbox_offset: float = 15.0


func can_chain() -> bool:
	return cancel_into_next_at >= 0.0


## When recovery begins, measured from the start of this hit.
func recovery_start() -> float:
	return windup + active


## Total length of the hit.
func duration() -> float:
	return windup + active + recovery
