class_name TypeScale
extends RefCounted
## The font sizes the interface uses.
##
## **This used to be a lock and is now a scale.** The old rule was that only
## whole multiples of 16 were allowed, because the body face was drawn on a
## 16-unit grid and anything else made every fourth stem a pixel wider. That is
## a real property of pixel fonts, and it had a real cost: it left exactly three
## usable sizes, so a label and the sentence under it were *the same size* and
## could only be told apart by colour. Every attempt at hierarchy was a 2x jump
## or nothing.
##
## The interface is not part of the pixel grid. The world renders into a fixed
## 1280x720 SubViewport with nearest filtering; the UI is a separate layer laid
## out at the window's real resolution, and that split was made deliberately.
## Nothing about the sprites depends on what size this file says.
##
## So the sizes are chosen to read well rather than to divide cleanly. Perfect
## DOS VGA 437 measures linearly between them — a string at 20 is exactly 20/16
## of its width at 16 — which is what makes an in-between size viable at all,
## and is a property the previous face did not have.
##
## **What is still true:** the icons, the tiles and the sprites are pixel art and
## are still drawn at whole scales. This is about type, and only type.

## A minor step, for things that sit beside something else and should not
## compete with it: units, counts, the "x3" on a stack.
const TINY: int = 13

## Everything you read a sentence of: labels, body copy, buttons, replies.
const SMALL: int = 16

## A step up without a jump — sub-headings, the name on a shop row, the line the
## eye should land on first inside a panel. This is the size the old scale could
## not express, and most of the reason for changing it.
const MEDIUM: int = 20

## Panel and screen titles — "Paused", the tab headers.
const HEADING: int = 28

## The game's name, and nothing else.
const DISPLAY: int = 64

## Every size in the scale, smallest first. `m1_smoke_test` walks this to check
## the shipped font renders each one distinctly, which is the invariant that
## replaced the grid assertion: the old one policed a divisor, this one asks the
## question that actually matters — can you tell these apart on screen?
const ALL: Array[int] = [TINY, SMALL, MEDIUM, HEADING, DISPLAY]


## Clamp a computed size into the scale. For anywhere a size is derived rather
## than chosen — nothing should invent a size outside `ALL`, or the hierarchy
## stops being a hierarchy and becomes a spread.
static func snap(size: float) -> int:
	var best: int = ALL[0]
	for step in ALL:
		if absf(float(step) - size) < absf(float(best) - size):
			best = step
	return best
