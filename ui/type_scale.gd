class_name TypeScale
extends RefCounted
## The only font sizes the interface is allowed to use.
##
## All three fonts in `art/fonts/` are pixel fonts drawn on a **16 units-per-em
## grid** — 99.9% of their outline points land on it, measured. A font like that
## rasterises cleanly only when one grid unit lands on a whole pixel, which
## happens when the size is a whole multiple of 16:
##
##     size 16 -> 1 pixel per grid unit   crisp
##     size 32 -> 2 pixels per grid unit  crisp
##     size 20 -> 1.25                    every fourth stem is a pixel wider
##     size 24 -> 1.5                     every other stem is a pixel wider
##
## The UI used to be at 18, 20, 21, 22, 24, 44 and 72. Turning antialiasing off
## made the edges hard; this is what makes the strokes even.
##
## **Three sizes, and hierarchy comes from somewhere else.** The grid leaves
## 16, 32, 48, 64 and nothing between, so there is no "slightly bigger" — a
## label and the body text are the same size and are told apart by colour,
## spacing and position. That is how pixel-font interfaces are built, and
## fighting it is how you end up with 21px text that looks subtly broken.

## The design grid. Any size the UI uses must be a whole multiple of this.
const STEP: int = 16

## Everything you read: labels, body copy, buttons, replies, numbers.
const SMALL: int = 16

## Screen titles — "Paused", the tab headers.
const HEADING: int = 32

## The game's name, and nothing else.
const DISPLAY: int = 64

## Every size in the scale, for the assertion in `m1_smoke_test` that checks
## them against the font actually shipped rather than against this comment.
const ALL: Array[int] = [SMALL, HEADING, DISPLAY]


## Round to the nearest usable size, never below one grid step. For anywhere a
## size is computed rather than chosen.
static func snap(size: float) -> int:
	return maxi(int(round(size / float(STEP))) * STEP, STEP)
