class_name ActorAnimationSet
extends Resource
## Every animation an actor has, in one tunable file.
##
## Named slots rather than a dictionary: the set is fixed and small, and naming
## them means a missing walk cycle is visible in the inspector instead of being
## a string typo that fails silently at runtime.
##
## Any slot may be left empty. The AnimationComponent falls back to `idle`, and
## to a flat placeholder if even that is missing — so an actor with no art at
## all still runs, which is what keeps the grey-box prototype working while the
## real sprites are drawn one at a time.

@export var idle: SpriteAnimation
@export var walk: SpriteAnimation

@export_group("Attack")
## One per combo hit. Each is 3 frames — windup, strike, recovery — and is
## advanced by the attack state's own clock, not by fps.
@export var attack_1: SpriteAnimation
@export var attack_2: SpriteAnimation
@export var attack_3: SpriteAnimation

@export_group("Reactions")
@export var dodge: SpriteAnimation
@export var hurt: SpriteAnimation
@export var death: SpriteAnimation


func attack(index: int) -> SpriteAnimation:
	match index:
		0:
			return attack_1
		1:
			return attack_2
		2:
			return attack_3
	return null


## Slot lookup by state name, for the states that need no special handling.
func for_state(state: StringName) -> SpriteAnimation:
	match state:
		&"Idle":
			return idle
		&"Move", &"Chase":
			return walk
		&"Dodge":
			return dodge
		&"Hurt":
			return hurt
		&"Dead":
			return death
		&"Telegraph", &"Lunge", &"Recover":
			# Enemy attack states have no bespoke clips yet; the telegraph reads
			# through modulate and scale instead.
			return idle
	return null
