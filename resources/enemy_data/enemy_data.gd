class_name EnemyData
extends Resource
## Per-enemy stats as a Custom Resource (GDD §10, pattern 3).
##
## Each enemy becomes a `.tres` you tune without touching code. The shared
## behaviour lives in base_enemy.gd and the states next to it, so enemy #7 is
## an afternoon.

@export_group("Identity")
## Stable id, the same idea as `ItemData.id`. Saves and quest objectives name
## an enemy by this rather than by `display_name`, so renaming "Rot Hound" to
## "Blighted Hound" does not silently retire somebody's half-finished quest.
@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Loot")
## What this leaves behind, as `{id: [chance, min, max]}` — ids may be items
## (`ItemData`) or haul materials, and `LootPile` sorts out which bag each goes
## in so a table author does not have to care.
##
## **A pile you search, not a pickup you walk over.** Materials are the routine
## currency of a run and walking over them is right; a kill is a *moment*, and
## something worth stopping for is worth a keypress. It also means loot cannot
## be hoovered up by accident mid-fight while you are dodging the next one.
@export var loot: Dictionary = {}

## Chance of coins on the body at all, and how many. Deliberately rare: gold
## comes from selling a haul, and an enemy that reliably pays cash is a reason
## to farm one instead of going anywhere.
@export_range(0.0, 1.0, 0.01) var gold_chance: float = 0.0
@export var gold_min: int = 0
@export var gold_max: int = 0

@export_group("Stats")
@export var max_health: int = 10
@export var move_speed: float = 40.0
## Damage dealt by this enemy's telegraphed attack. Nothing in Blightfall deals
## untelegraphed contact damage — enemy rule 1 (GDD §5).
@export var contact_damage: int = 1
## Unused in M1 (no XP until M3) but part of the schema the GDD specifies.
@export var xp_value: int = 5

@export_group("Telegraph")
## GDD §5, enemy rule 1: minimum 0.4s, distinct colour and pose.
@export var telegraph_time: float = 0.4
@export var telegraph_color: Color = Color(0.85, 0.85, 0.35)
## How much the enemy grows while winding up — the "pose" half of the rule.
@export var telegraph_scale: float = 1.25
@export var telegraph_sfx: StringName = &"enemy_telegraph"

@export_group("Behaviour")
## Distance at which the enemy notices a target.
@export var aggro_range: float = 120.0
## Distance at which it commits to an attack.
@export var attack_range: float = 26.0
## Distance it covers during the lunge.
@export var lunge_distance: float = 44.0
@export var lunge_time: float = 0.18
## Vulnerable window after the attack. This is where the player gets their turn.
@export var recover_time: float = 0.5
## Minimum gap between attacks.
@export var attack_cooldown: float = 0.35

## After an attack, back off and move around the target for this long before
## committing again. Set both to zero for an enemy that simply re-engages —
## a Thornmass does not circle.
##
## This is what stops a pack arriving in single file: separation pushes the
## second and third enemy apart, chase pulls them straight back onto the same
## line, and the fight becomes one enemy three times. Circling gives them
## somewhere to be that is not behind the first one.
@export var circle_time_min: float = 0.5
@export var circle_time_max: float = 1.2
## Held at this multiple of `attack_range`, which must stay above 1.0 or the
## circle happens inside the range it is supposed to be waiting outside of.
@export var circle_radius_scale: float = 1.35
## Circling is a lope, not a sprint.
@export var circle_speed_scale: float = 0.8
## Control loss when hit.
@export var stagger_time: float = 0.14
## Push-apart radius so a pack doesn't stack into one rectangle.
@export var separation_radius: float = 14.0
@export var separation_strength: float = 0.6

@export_group("Reactions")
@export var knockback_resistance: float = 1.0
@export var death_time: float = 0.35

@export_group("Presentation")
## The sprites. Left null, the enemy runs on a flat `base_color` box — which is
## what keeps a new enemy playable on the day its stats are written and its art
## is not drawn (GDD §8 puts the player's sheet first and everything else after
## the zone 1 tileset).
@export var animations: ActorAnimationSet

## The drawn body, in pixels. Sets the sprite offset that puts the feet on the
## node origin, and the collider is derived from it — so this has to match the
## art, not approximate it. `tools/import_pixellab.py` prints the measurement.
@export var body_size: Vector2 = Vector2(16, 16)
@export var base_color: Color = Color(0.45, 0.42, 0.38)
@export var hitbox_size: Vector2 = Vector2(20, 18)
@export var hitbox_offset: float = 12.0


## Peak lunge speed for a linear dash of `lunge_distance` over `lunge_time`.
func lunge_speed() -> float:
	return lunge_distance / maxf(lunge_time, 0.0001)
