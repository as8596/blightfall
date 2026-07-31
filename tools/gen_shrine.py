#!/usr/bin/env python3
"""Draw the waystone, dormant and kindled.

    python3 tools/gen_shrine.py

`world/shrine.gd` has been finished and untested-in-place since M1: it lights,
it stays lit across a save, and it has eleven passing assertions. It has never
appeared in a level, and the reason is this file not existing — the node takes
two textures and there were none, so wiring one up would have put an invisible
save point in the world.

## What it has to say without words

**Dormant it must read as a thing worth walking to**, from across a clearing, at
1:1, before the player knows what it is. So it is tall — 96px, the player's own
height — and it is the only stone in the game with a straight edge. Everything
else the valley is made of is a bush, a tree or a rock.

**Kindled it must read as done.** The change is deliberately not subtle: the
basin fills with fire and the bottom third of the slab takes the light off it.
A save point whose "you have used this" state is a two-pixel difference is a
save point players re-light because they cannot remember.

The pair is drawn from one silhouette so the two frames sit on the same pixels
and the change is the light, never the shape — a stone that grew when you rested
at it would read as a different stone.

## Colour

The fire borrows the greybox `hearth` tile's orange (0xc27a3a), which is
already the town's warmth colour, so the thing that means *safe* is one colour
everywhere it appears. It is nowhere near the blight's reserved yellow-green;
`tools/check_colour.py` is the check.
"""

from __future__ import annotations

import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

WIDTH, HEIGHT = 64, 96
OUT = os.path.join(ROOT, "art", "sprites", "props")

CLEAR = (0, 0, 0, 0)

EDGE = (0x1e, 0x1d, 0x1a, 255)
STONE_DARK = (0x42, 0x41, 0x3c, 255)
STONE = (0x60, 0x5e, 0x56, 255)
STONE_LIT = (0x7c, 0x79, 0x6f, 255)
MOSS = (0x4a, 0x55, 0x3a, 255)
MOSS_LIT = (0x5c, 0x68, 0x46, 255)

BASIN_DARK = (0x24, 0x20, 0x1b, 255)
BASIN = (0x3a, 0x35, 0x2d, 255)
BASIN_LIT = (0x50, 0x4a, 0x3f, 255)

# The town's warmth, and the same orange as the greybox hearth.
FIRE_DEEP = (0xa8, 0x53, 0x22, 255)
FIRE = (0xc2, 0x7a, 0x3a, 255)
FIRE_BRIGHT = (0xe2, 0xa8, 0x54, 255)
FIRE_CORE = (0xf4, 0xdd, 0x9a, 255)

# What the fire throws onto the stone beside it. Not a glow — a tint on pixels
# that are already there, so the lit frame cannot grow past the dormant one.
GLOW_STONE = (0x8a, 0x74, 0x54, 255)
GLOW_STONE_DARK = (0x60, 0x4e, 0x38, 255)


def blank():
	return [CLEAR] * (WIDTH * HEIGHT)


def put(px, x, y, colour):
	if 0 <= x < WIDTH and 0 <= y < HEIGHT:
		px[y * WIDTH + x] = colour


def get(px, x, y):
	if 0 <= x < WIDTH and 0 <= y < HEIGHT:
		return px[y * WIDTH + x]
	return CLEAR


def rect(px, x0, y0, x1, y1, colour):
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			put(px, x, y, colour)


def ellipse(px, cx, cy, rx, ry, colour):
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			u = (x - cx) / max(rx, 0.001)
			v = (y - cy) / max(ry, 0.001)
			if u * u + v * v <= 1.0:
				put(px, x, y, colour)


# The slab, as a half-width per row. Straight-edged and slightly irregular:
# quarried, not grown, and old enough to have lost a corner.
TOP, FOOT = 14, 78

## How far up the stone the firelight reaches. Not to the top: a stone lit all
## the way up is a stone on fire, and the point is that something small is
## burning at its foot.
GLOW_TOP = 50

## A 4x4 ordered dither, normalised. Thresholds for the falloff above.
BAYER = [[v / 16.0 for v in row] for row in (
	(0, 8, 2, 10),
	(12, 4, 14, 6),
	(3, 11, 1, 9),
	(15, 7, 13, 5),
)]


def half_at(y):
	if y < TOP or y > FOOT:
		return -1
	f = (y - TOP) / float(FOOT - TOP)
	# Widens toward the foot, and the top is chipped off on one side.
	base = 9.0 + 5.0 * f
	if y < TOP + 6:
		base -= (TOP + 6 - y) * 0.55
	return base


def slab(px):
	for y in range(TOP, FOOT + 1):
		half = half_at(y)
		if half < 0:
			continue
		left = int(round(32 - half))
		right = int(round(32 + half))
		# Lit down the left, shaded down the right: one light, straight down and
		# a little to the left, matching everything else drawn for this project.
		rect(px, left, y, right, y, STONE)
		rect(px, left, y, left + 2, y, STONE_LIT)
		rect(px, right - 2, y, right, y, STONE_DARK)

	# A carved groove down the middle, which is what makes it a marker rather
	# than a rock. Two pixels wide so it survives being looked at from a screen
	# away.
	rect(px, 31, TOP + 10, 32, FOOT - 12, STONE_DARK)
	rect(px, 31, TOP + 10, 31, FOOT - 12, EDGE)

	# Moss on the shaded foot. Only ever on the lower third: moss grows where
	# the damp is, and a stone mossy at the top reads as a stone lying down.
	for y in range(FOOT - 22, FOOT + 1):
		half = half_at(y)
		if half < 0:
			continue
		right = int(round(32 + half))
		width = 3 + int(2.5 * math.sin((y - FOOT + 22) * 0.4))
		rect(px, right - width, y, right, y, MOSS)


def basin(px):
	"""The bowl at its foot, which is the thing that lights."""
	ellipse(px, 32, 84, 17, 6, BASIN)
	ellipse(px, 32, 83, 17, 6, BASIN_LIT)
	ellipse(px, 32, 84, 13, 4, BASIN_DARK)


def outline(px):
	edged = list(px)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if px[y * WIDTH + x][3] != 0:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				if get(px, x + dx, y + dy)[3] != 0:
					edged[y * WIDTH + x] = EDGE
					break
	return edged


def flame(px):
	"""Fire in the basin, and the light it throws on the stone above it.

	Drawn strictly inside the dormant silhouette plus the basin's own mouth, so
	lighting a shrine changes its colours and never its outline.
	"""
	# The body of the fire: a teardrop sitting in the bowl.
	for i, (cy, rx, ry, colour) in enumerate((
		(80.0, 12.0, 6.0, FIRE_DEEP),
		(77.0, 9.5, 7.0, FIRE),
		(74.0, 6.5, 6.5, FIRE_BRIGHT),
		(72.0, 3.5, 4.5, FIRE_CORE),
	)):
		ellipse(px, 32, cy, rx, ry, colour)
		del i
	# A tongue licking up the face of the stone, which is what stops it reading
	# as a glowing puddle.
	for y in range(64, 72):
		f = (72 - y) / 8.0
		w = int(round(1 + 2.0 * f))
		rect(px, 32 - w, y, 32 + w, y, FIRE if f < 0.6 else FIRE_BRIGHT)
		if f > 0.5:
			put(px, 32, y, FIRE_CORE)

	# Firelight on the slab: recolour stone that is already there, brightest at
	# the basin and falling off upward. Nothing new is drawn.
	#
	# **Dithered, not thresholded.** A straight cutoff put a hard horizontal seam
	# across the stone where the lit half met the unlit one, which reads as a
	# rectangle of different rock rather than as light. An ordered dither spreads
	# the boundary over a few rows, which is how pixel art has always done a
	# gradient, and it stays deterministic — the same file every run.
	warm = {STONE: GLOW_STONE, STONE_LIT: GLOW_STONE,
		STONE_DARK: GLOW_STONE_DARK, MOSS: MOSS_LIT}
	# Solid warm at the bottom, solid cool at the top, and the dither confined to
	# the band between. Dithering the whole reach turned the stone into a
	# checkerboard — the pattern has to be the *edge* of the light, not the light.
	for y in range(GLOW_TOP, FOOT + 1):
		# 1 at the basin, 0 at the top of the reach.
		lit = (y - GLOW_TOP) / float(FOOT - GLOW_TOP)
		for x in range(WIDTH):
			current = get(px, x, y)
			if current not in warm:
				continue
			if lit < 0.28:
				continue
			if lit < 0.62 and lit - 0.28 < BAYER[y % 4][x % 4] * 0.34:
				continue
			put(px, x, y, warm[current])


def main() -> None:
	os.makedirs(OUT, exist_ok=True)

	dormant = blank()
	slab(dormant)
	basin(dormant)
	write_png(os.path.join(OUT, "shrine_dormant.png"), WIDTH, HEIGHT, outline(dormant))

	kindled = blank()
	slab(kindled)
	basin(kindled)
	flame(kindled)
	write_png(os.path.join(OUT, "shrine_lit.png"), WIDTH, HEIGHT, outline(kindled))

	print("  shrine_dormant.png %dx%d" % (WIDTH, HEIGHT))
	print("  shrine_lit.png     %dx%d" % (WIDTH, HEIGHT))


if __name__ == "__main__":
	main()
