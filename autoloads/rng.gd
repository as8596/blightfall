extends Node
## The one seeded RNG (GDD §12, rule 5).
##
## Every piece of combat randomness — screen shake offsets, SFX pitch variance,
## telegraph jitter — goes through here. One seed reproduces a whole session,
## which is what makes "it felt unfair that time" a debuggable claim rather than
## an argument.

const DEFAULT_SEED: int = 0x1B0

var rng := RandomNumberGenerator.new()

var current_seed: int = DEFAULT_SEED


func _ready() -> void:
	reseed(DEFAULT_SEED)


## Reset the stream. Pass -1 for a genuinely random seed.
func reseed(new_seed: int) -> void:
	current_seed = new_seed
	if new_seed < 0:
		rng.randomize()
		current_seed = rng.seed
	else:
		rng.seed = new_seed


func randf() -> float:
	return rng.randf()


func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)


## A multiplier in [1 - variance, 1 + variance]. Used for SFX pitch —
## "one footstep becomes infinite footsteps" (GDD §9).
func pitch(variance: float) -> float:
	return 1.0 + rng.randf_range(-variance, variance)


## A random unit vector, for shake offsets and scatter.
func direction() -> Vector2:
	return Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
