class_name SpriteAnimation
extends Resource
## One animation: a horizontal strip per facing direction.
##
## **Three, five, or eight strips — all three are valid sets.** Which one an
## actor uses is a property of its art, not of the code, and the fallback chain
## below is what lets a grey-box actor with a single strip and a finished actor
## with eight run through the same component.
##
## - **Three** (`down`, `up`, `side`): the classic. `side` is drawn facing east
##   and mirrored for west, and the diagonals resolve to the nearest cardinal.
##   Cheapest, and correct for anything symmetrical.
## - **Five** (adds `down_side`, `up_side`): true 8-way movement, still mirrored
##   for the western half.
## - **Eight** (adds `side_west`, `down_side_west`, `up_side_west`): nothing is
##   mirrored. **Required for any actor carrying something on one side** — a
##   scabbard, a strap, a wound — because mirroring puts it on the wrong hip and
##   the sword appears to swap hands when you turn around.
##
## Any strip left null falls back through the chain in `resolve()`, ending at
## `down`. So a single texture is still a complete (if direction-blind)
## animation, which is what matters during production: one strip is enough to
## see the thing move.

@export_group("Cardinals")
@export var down: Texture2D
@export var up: Texture2D
## Drawn facing east. Mirrored for west unless `side_west` is supplied.
@export var side: Texture2D

@export_group("Diagonals")
## South-east. Falls back to `down`.
@export var down_side: Texture2D
## North-east. Falls back to `up`.
@export var up_side: Texture2D

@export_group("Western half")
## Supply these only for an asymmetric actor. Null means "mirror the eastern
## strip", which is right for almost everything.
@export var side_west: Texture2D
@export var down_side_west: Texture2D
@export var up_side_west: Texture2D

@export_group("Playback")
## Frames in the strip. Frame width is texture width / frames.
@export var frames: int = 1

## Playback rate for free-running animations. Ignored when the animation is
## driven by frame data — see AnimationComponent.set_manual_frame().
@export var fps: float = 8.0

@export var loop: bool = true


## The strip to draw for `direction`, and whether to mirror it.
##
## Returns `{"texture": Texture2D, "flip": bool}`. Texture may be null only if
## the animation is invalid; every path ends at `down`.
##
## Mirroring is decided here rather than by the caller because it depends on
## *which* strip we landed on: falling back from west to the eastern strip means
## flipping, falling back from west all the way to `down` does not — a front view
## is symmetrical enough that mirroring it only jitters the character's face.
func resolve(direction: AnimationComponent.Facing) -> Dictionary:
	match direction:
		AnimationComponent.Facing.DOWN:
			return {"texture": down, "flip": false}
		AnimationComponent.Facing.UP:
			return {"texture": _first(up, down), "flip": false}
		AnimationComponent.Facing.RIGHT:
			return {"texture": _first(side, down), "flip": false}
		AnimationComponent.Facing.DOWN_RIGHT:
			return {"texture": _first(down_side, side, down), "flip": false}
		AnimationComponent.Facing.UP_RIGHT:
			return {"texture": _first(up_side, side, up, down), "flip": false}
		AnimationComponent.Facing.LEFT:
			if side_west != null:
				return {"texture": side_west, "flip": false}
			return {"texture": side, "flip": true} if side != null \
				else {"texture": down, "flip": false}
		AnimationComponent.Facing.DOWN_LEFT:
			if down_side_west != null:
				return {"texture": down_side_west, "flip": false}
			var east: Texture2D = _first(down_side, side)
			return {"texture": east, "flip": true} if east != null \
				else {"texture": down, "flip": false}
		AnimationComponent.Facing.UP_LEFT:
			if up_side_west != null:
				return {"texture": up_side_west, "flip": false}
			var east_up: Texture2D = _first(up_side, side)
			return {"texture": east_up, "flip": true} if east_up != null \
				else {"texture": _first(up, down), "flip": false}
	return {"texture": down, "flip": false}


func texture_for(direction: AnimationComponent.Facing) -> Texture2D:
	return resolve(direction)["texture"] as Texture2D


func is_valid() -> bool:
	return down != null and frames > 0


## How many distinct strips this animation actually carries. Reported by the
## tests so a set that was *meant* to be eight-way and quietly lost a file shows
## up as a number rather than as a character who moonwalks north-west.
func direction_count() -> int:
	var count := 0
	for strip in [down, up, side, down_side, up_side, side_west, down_side_west, up_side_west]:
		if strip != null:
			count += 1
	return count


func _first(a: Texture2D, b: Texture2D = null, c: Texture2D = null,
		d: Texture2D = null) -> Texture2D:
	if a != null:
		return a
	if b != null:
		return b
	if c != null:
		return c
	return d
