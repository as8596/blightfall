class_name SpriteAnimation
extends Resource
## One animation: a horizontal strip per facing direction.
##
## Directions are down / up / side, with left drawn as a flipped right — three
## strips instead of four, for a difference nobody notices top-down. Any strip
## left null falls back to `down`, so a single texture is a complete (if
## direction-blind) animation. That matters during production: one strip is
## enough to see the thing move.

@export var down: Texture2D
@export var up: Texture2D
## Drawn as-is facing right, horizontally flipped facing left.
@export var side: Texture2D

## Frames in the strip. Frame width is texture width / frames.
@export var frames: int = 1

## Playback rate for free-running animations. Ignored when the animation is
## driven by frame data — see AnimationComponent.set_manual_frame().
@export var fps: float = 8.0

@export var loop: bool = true


func texture_for(direction: AnimationComponent.Facing) -> Texture2D:
	var chosen: Texture2D = down
	match direction:
		AnimationComponent.Facing.UP:
			chosen = up
		AnimationComponent.Facing.SIDE:
			chosen = side
		_:
			chosen = down
	return chosen if chosen != null else down


func is_valid() -> bool:
	return down != null and frames > 0
