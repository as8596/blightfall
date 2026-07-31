#!/usr/bin/env python3
"""Draw the arrow as it looks in flight.

    python3 tools/gen_arrow_sprite.py

The icon in `art/icons/items/` is the arrow as it looks in a slot: three
quarters on, big enough to recognise in a grid, and pointing up and to the
right. None of that survives being a projectile.

**A projectile is drawn along +X and rotated by its heading**, because that is
what `Arrow.launch` does with `direction.angle()`. Reusing the icon would mean
rotating art that was drawn at 45 degrees by an arbitrary angle — a non-integer
rotation of pixel art, which shears the grid and makes every arrow in the air
look like a different arrow. So the flight sprite is its own small file, drawn
level, and rotation is the only thing that ever moves it.

24x8, which is a third of a tile long. Big enough to read against grass at 1:1
and small enough that a volley does not look like a fence.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

WIDTH, HEIGHT = 24, 8
OUT = os.path.join(ROOT, "art", "sprites", "props", "arrow_flight.png")

CLEAR = (0, 0, 0, 0)

# Lifted off the arrow icon so the thing in the air is the thing in the quiver:
# an iron head, an ash shaft, a dark binding at the nock.
HEAD = (150, 152, 158, 255)
HEAD_DARK = (96, 98, 106, 255)
SHAFT = (140, 110, 72, 255)
SHAFT_DARK = (96, 72, 46, 255)
FLETCH = (188, 180, 162, 255)
FLETCH_DARK = (128, 120, 104, 255)


def blank():
	return [CLEAR] * (WIDTH * HEIGHT)


def put(px, x, y, colour):
	if 0 <= x < WIDTH and 0 <= y < HEIGHT:
		px[y * WIDTH + x] = colour


def rect(px, x0, y0, x1, y1, colour):
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			put(px, x, y, colour)


def arrow():
	px = blank()
	# **Top row light, bottom row dark, all the way along.** That is the same
	# overhead light the shrubs are drawn under, and here it is not a style
	# choice: an arrow lit from one side would disagree with itself every time it
	# turned a corner, and this sprite turns through a full circle.

	# The shaft, nock to neck.
	rect(px, 5, 3, 17, 3, SHAFT)
	rect(px, 5, 4, 17, 4, SHAFT_DARK)

	# The head: a spine to the point with two barbs swept back off it. Six pixels
	# of it, which is a quarter of the sprite — a head any smaller dissolves into
	# the shaft at 1:1 and the arrow reads as a stick.
	rect(px, 18, 3, 23, 3, HEAD)
	rect(px, 18, 4, 23, 4, HEAD_DARK)
	rect(px, 18, 2, 20, 2, HEAD)
	rect(px, 18, 5, 20, 5, HEAD_DARK)

	# Fletching, swept back off the nock, and pale. This is the end that says
	# which way the thing is pointing when it is halfway across the screen —
	# the head is four pixels of grey and the fletching is a shape.
	rect(px, 1, 2, 5, 2, FLETCH)
	rect(px, 2, 1, 4, 1, FLETCH)
	rect(px, 1, 5, 5, 5, FLETCH_DARK)
	rect(px, 2, 6, 4, 6, FLETCH_DARK)
	rect(px, 0, 3, 4, 3, FLETCH)
	rect(px, 0, 4, 4, 4, FLETCH_DARK)
	return px


def main() -> None:
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	write_png(OUT, WIDTH, HEIGHT, arrow())
	print("  arrow_flight.png %dx%d" % (WIDTH, HEIGHT))


if __name__ == "__main__":
	main()
