#!/usr/bin/env python3
"""Bring the ornate steel UI set into Blightfall's palette.

    python3 tools/import_ui_borders.py

Reads `art/source/ui/dark_gothic/` and writes `art/ui/`. The source is kept in
the repo unmodified, so this can be re-run with different numbers rather than
being a one-way edit nobody can undo.

Two things happen to every file, and both were measured before they were chosen.

## The colour

The set arrives as cold steel: the body sits at hue 250-260 with saturation
0.22-0.36. Blightfall's UI border is `Color(0.42, 0.35, 0.26)` — hue 38. That is
214 degrees apart, which is not a clash you can style around; side by side they
read as two different games.

So every pixel is rotated onto one warm hue and its saturation is capped,
keeping value untouched. Value is what carries the metal — the bevels, the
bright top edge, the shadow under the rim — and rotating hue while leaving value
alone is why this reads as the same object in a different alloy rather than as a
tinted photograph.

The cap matters as much as the rotation. The gems come in at saturation 0.79-0.85
and would be the loudest thing on the screen; pulled to 0.62 they are gold studs.
Nothing here goes near the blight's reserved yellow-green — `tools/check_colour.py`
is the check that says so.

## The runes

Every edge of the big frame carries runic glyphs, which is a problem twice over.

**They cannot tile.** 357 of the frame's 424 top-band columns are distinct, so
there is no repeatable segment and a nine-slice would smear gibberish along any
panel wider than the source. The inventory is 1153px; the top edge would repeat
nearly three times.

**And they are the wrong story.** Ambry is a farming village that is losing.
Runes belong to a wizard's tower.

Stripping them by colour would take the gems too — the glyphs and the corner
studs are the same cyan. So they are separated by **size**: a connected-component
pass over the bright-accent mask finds eight blobs of 43-76px (the four corners
and four edge midpoints) and sixty-three of 35px or less (the glyphs). The gap
between 35 and 43 is wide and unambiguous, so the threshold is not a guess.

What a stripped rune leaves behind is filled with the most common steel tone
around it, which is right because a glyph sits on a flat band by construction.
"""

from __future__ import annotations

import colorsys
import os
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_colour import read_png  # noqa: E402
from pack_strips import write_png  # noqa: E402

SRC = os.path.join(ROOT, "art", "source", "ui", "dark_gothic")
OUT = os.path.join(ROOT, "art", "ui")

CLEAR = (0, 0, 0, 0)

## The one warm hue everything lands on, in degrees, and the ceiling on
## saturation. 35 is the game's own panel border; 0.62 is loud enough for a gem
## and quiet enough that a gem is not the subject.
WARM_HUE = 35.0
MAX_SATURATION = 0.62

## What counts as one of the set's bright accents — the glyphs and the gems.
## Everything else is steel and is left alone by the rune pass.
ACCENT_MIN_VALUE = 0.55
ACCENT_MIN_SATURATION = 0.35
ACCENT_HUES = ((150.0, 235.0), (260.0, 330.0))

## Accent blobs at least this big are gems and are kept. Measured: the gems are
## 43-76px and the largest glyph is 35, so anything in the low forties separates
## them and nothing sits near the line.
GEM_MIN_PIXELS = 40

## How far along the band to look for the steel that replaces a stripped glyph.
##
## **Along, not around.** A square sample was the first attempt and it fails on
## exactly the thing a border is: a band with a lit edge, a flat middle and a
## shaded edge. Sample a square and you average across all three, and the fill
## comes out as holes and wrong-coloured streaks.
##
## A band is uniform along its own length, so the right sample is a line. Both a
## row window and a column window are taken and the more decisive one wins — that
## picks rows for the top and bottom bands and columns for the sides, with no
## need to tell this function which edge it is working on.
LINE_WINDOW = 24

## How far past a glyph's own pixels the repair reaches.
##
## **Every glyph is drawn with a drop shadow**, and the shadow is dark steel
## rather than bright cyan, so the accent mask does not see it. Removing only
## what the mask found left the cores gone and the shadows behind — a band of
## grey smudges exactly where the runes had been, which looked worse than the
## runes did.
##
## Two is enough to take the shadow and small enough to leave the band's bevel
## alone: the glyphs sit in the middle of a band whose lit and shaded edges are
## at least three pixels away.
REPAIR_DILATE = 2

## What comes out, and what it is for. Renamed on the way through — `element_4`
## says nothing at the call site.
FILES = {
	"element_1.png": "frame.png",
	"element_2.png": "button.png",
	"element_5.png": "slot.png",
	"element_4.png": "trough.png",
	"E.png": "key_e.png",
}

## The frame is the only one with runes on it; the rest is plain steel.
STRIP_RUNES = {"element_1.png"}

## How much of each corner of the frame is ornament that must survive intact.
## The gem setting is about 34px with a tab hanging off it; 48 clears both.
FRAME_CORNER = 48

## The frame, again, with every edge flattened to a repeating cross-section —
## written alongside the ornate original rather than instead of it.
##
## **This is what makes a nine-patch possible.** The edges as drawn are a
## composition, not a pattern: a diagonal seam a third of the way along, a
## flourish leading into a gem at the exact centre of each side. Stretch that to
## fit a 1153px inventory and the seam smears and the gem turns into a stripe.
## Measured, only twelve of the frame's 424 top-band columns are identical to
## each other — there is no repeat to tile.
##
## So each edge is replaced, outside its corners, by the one cross-section that
## *does* repeat: the flat steel between the ornaments. The corner gems survive
## because the corners are never touched. The mid-edge gems do not, and that is
## the trade — a frame that fits every panel, against four studs that only ever
## sat correctly at one size.
FLATTEN_EDGES = {"element_1.png": "panel.png"}


def is_accent(pixel) -> bool:
	r, g, b, a = pixel
	if a == 0:
		return False
	h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
	if v < ACCENT_MIN_VALUE or s < ACCENT_MIN_SATURATION:
		return False
	degrees = h * 360.0
	return any(low <= degrees <= high for low, high in ACCENT_HUES)


def components(mask, width, height):
	"""Every 8-connected run of True in `mask`, as a list of pixel indices."""
	seen = [False] * len(mask)
	found = []
	for start in range(len(mask)):
		if not mask[start] or seen[start]:
			continue
		stack = [start]
		seen[start] = True
		cells = []
		while stack:
			at = stack.pop()
			cells.append(at)
			x, y = at % width, at // width
			for dx in (-1, 0, 1):
				for dy in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if 0 <= nx < width and 0 <= ny < height:
						near = ny * width + nx
						if mask[near] and not seen[near]:
							seen[near] = True
							stack.append(near)
		found.append(cells)
	return found


def strip_runes(pixels, width, height):
	"""Paint the glyphs out, keeping the gems. Returns (pixels, stripped, kept)."""
	mask = [is_accent(p) for p in pixels]
	blobs = components(mask, width, height)
	doomed = set()
	kept = 0
	for cells in blobs:
		if len(cells) >= GEM_MIN_PIXELS:
			kept += 1
			continue
		doomed.update(cells)

	# Take the drop shadows with the glyphs — see `REPAIR_DILATE`.
	repair = set(doomed)
	for at in doomed:
		x, y = at % width, at // width
		for dy in range(-REPAIR_DILATE, REPAIR_DILATE + 1):
			for dx in range(-REPAIR_DILATE, REPAIR_DILATE + 1):
				nx, ny = x + dx, y + dy
				if 0 <= nx < width and 0 <= ny < height and pixels[ny * width + nx][3] != 0:
					repair.add(ny * width + nx)

	out = list(pixels)
	for at in repair:
		x, y = at % width, at // width
		# Counted rather than averaged: this art has a small palette, and the mean
		# of two ramp steps is a colour that is in neither.
		across = Counter()
		down = Counter()
		for step in range(-LINE_WINDOW, LINE_WINDOW + 1):
			nx = x + step
			if 0 <= nx < width:
				near = y * width + nx
				if near not in repair and pixels[near][3] != 0 and not mask[near]:
					across[pixels[near]] += 1
			ny = y + step
			if 0 <= ny < height:
				near = ny * width + x
				if near not in repair and pixels[near][3] != 0 and not mask[near]:
					down[pixels[near]] += 1
		best = None
		for tally in (across, down):
			if not tally:
				continue
			colour, votes = tally.most_common(1)[0]
			if best is None or votes > best[1]:
				best = (colour, votes)
		if best is not None:
			out[at] = best[0]
	return out, len(repair), kept


def warm(pixels):
	"""One hue for everything, saturation capped, value untouched."""
	out = []
	for r, g, b, a in pixels:
		if a == 0:
			out.append(CLEAR)
			continue
		h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
		nr, ng, nb = colorsys.hsv_to_rgb(WARM_HUE / 360.0, min(s, MAX_SATURATION), v)
		out.append((int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)), a))
	return out


def _band_slice(pixels, width, height, edge):
	"""The most repeated cross-section of one edge, and how thick that edge is.

	Found rather than written down: the bands are 29-30px and are not all the
	same, and a number typed here would be wrong the first time somebody swaps
	the art for a different set.
	"""
	cx, cy = width // 2, height // 2
	if edge in ("top", "bottom"):
		y = cy
		while 0 < y < height and pixels[y * width + cx][3] == 0:
			y = y - 1 if edge == "top" else y + 1
		thickness = y + 1 if edge == "top" else height - y
		rows = range(thickness) if edge == "top" else range(height - thickness, height)
		slices = [tuple(pixels[r * width + x] for r in rows) for x in range(width)]
	else:
		x = cx
		while 0 < x < width and pixels[cy * width + x][3] == 0:
			x = x - 1 if edge == "left" else x + 1
		thickness = x + 1 if edge == "left" else width - x
		cols = range(thickness) if edge == "left" else range(width - thickness, width)
		slices = [tuple(pixels[y * width + c] for c in cols) for y in range(height)]
	# **Skip the empty ones.** A frame has a few columns of transparent padding
	# past each corner, and on two of the four edges no two steel slices are
	# byte-identical — so the padding won the vote and those edges were flattened
	# to nothing at all. Only a slice with something in it can be the band.
	drawn = [s for s in slices if any(p[3] != 0 for p in s)]
	return Counter(drawn or slices).most_common(1)[0][0], thickness


def flatten_edges(pixels, width, height):
	"""Replace each edge, outside its corners, with its own repeating slice."""
	out = list(pixels)
	for edge in ("top", "bottom", "left", "right"):
		slice_, thickness = _band_slice(pixels, width, height, edge)
		if edge in ("top", "bottom"):
			rows = list(range(thickness)) if edge == "top" \
				else list(range(height - thickness, height))
			for x in range(FRAME_CORNER, width - FRAME_CORNER):
				for i, row in enumerate(rows):
					out[row * width + x] = slice_[i]
		else:
			cols = list(range(thickness)) if edge == "left" \
				else list(range(width - thickness, width))
			for y in range(FRAME_CORNER, height - FRAME_CORNER):
				for i, col in enumerate(cols):
					out[y * width + col] = slice_[i]
	return out


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	for source, target in FILES.items():
		path = os.path.join(SRC, source)
		if not os.path.exists(path):
			print("  missing %s" % source)
			continue
		width, height, pixels = read_png(path)
		note = ""
		if source in STRIP_RUNES:
			pixels, stripped, gems = strip_runes(pixels, width, height)
			note = "  (%d rune px out, %d gems kept)" % (stripped, gems)
		write_png(os.path.join(OUT, target), width, height, warm(pixels))
		print("  %-12s %dx%d%s" % (target, width, height, note))
		if source in FLATTEN_EDGES:
			flat = flatten_edges(pixels, width, height)
			write_png(os.path.join(OUT, FLATTEN_EDGES[source]), width, height, warm(flat))
			print("  %-12s %dx%d  (edges flattened, %dpx corners kept)"
				% (FLATTEN_EDGES[source], width, height, FRAME_CORNER))


if __name__ == "__main__":
	main()
