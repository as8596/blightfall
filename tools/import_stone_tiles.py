#!/usr/bin/env python3
"""Cut the wall and floor tiles out of the stone sheet.

    python3 tools/import_stone_tiles.py

Reads `art/source/tiles/stone_and_plank.png` and writes 64x64 tiles into
`art/tiles/`, where `tools/gen_greybox_tileset.py` picks them up.

## The sheet is elevations, not a tileset

It arrives as twenty pieces scattered on a 411x1144 canvas: 64x152 and 64x127
and 64x95 wall runs, some 26px slivers, a couple of L-shapes and a stepped
diagonal. None of the heights is a multiple of the tile size, and that is not a
mistake — they are **wall elevations**, whole walls drawn at once for a
three-quarter view, with the fine light brick as the surface you see looking
down and the large dark brick as the face you see from in front.

Blightfall does not need elevations. Ambry's buildings are already laid out as
rectangles with doors in `tools/build_greybox.gd`, and the builder composes the
runs itself from single tiles — so seventeen of the twenty pieces are
compositions of something this game already knows how to make.

What it needs is three squares, and all three are in there:

- the **floor**, the only wooden piece, already exactly 64x64
- the **wall top**, the fine light brick, also already 64x64
- the **wall face**, the large dark brick, cut out of the tall run at (122, 19)
  below where the light brick stops

All three tile seamlessly at 64 in both directions, which was checked before any
of this was written and is the reason the cut points below are what they are.

## Colour

Left alone. The greys measure at saturation 0.004 and 0.001 — neutral, not the
cold blue the UI set arrived in, so there is nothing to correct. The planks come
in at hue 29 with saturation 0.50, which is already the warm end this game's
palette lives at.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_colour import read_png  # noqa: E402
from pack_strips import write_png  # noqa: E402

SRC = os.path.join(ROOT, "art", "source", "tiles", "stone_and_plank.png")
OUT = os.path.join(ROOT, "art", "tiles")

TILE = 64

## Where each tile is cut from, by its top-left corner on the source sheet.
##
## The names are the greybox tile names they override — that is the whole
## contract with `gen_greybox_tileset.py`, which looks for `<name>.png` and uses
## it in place of the flat colour it would otherwise draw.
CUTS = {
	# The only wooden piece on the sheet, and already tile-sized.
	"floorboards": (19, 145),
	# Fine light brick: a wall seen from above, which is how this game sees them.
	"wall": (328, 832),
	# Large dark brick, cut out of the tall run once the light course has ended.
	# Used for the inner face, so a wall reads as having a near side.
	"wall_inner": (122, 107),
}


def main() -> None:
	if not os.path.exists(SRC):
		print("  no sheet at %s" % os.path.relpath(SRC, ROOT))
		return
	width, height, pixels = read_png(SRC)
	os.makedirs(OUT, exist_ok=True)
	for name, (x0, y0) in CUTS.items():
		if x0 + TILE > width or y0 + TILE > height:
			print("  %s: cut runs off the sheet" % name)
			continue
		tile = [pixels[(y0 + y) * width + x0 + x] for y in range(TILE) for x in range(TILE)]
		holes = sum(1 for p in tile if p[3] == 0)
		if holes:
			# A cut that catches the sheet's background is a tile with see-through
			# patches in it, which reads as a hole in a wall rather than as art.
			print("  %s: %d transparent pixels — cut is off the piece" % (name, holes))
			continue
		write_png(os.path.join(OUT, "%s.png" % name), TILE, TILE, tile)
		print("  %-12s from (%d, %d)" % (name + ".png", x0, y0))


if __name__ == "__main__":
	main()
