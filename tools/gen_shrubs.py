#!/usr/bin/env python3
"""Draw the undergrowth at 64px, the size it is actually seen at.

    python3 tools/gen_shrubs.py

The four bushes scattered through Orchardfall arrived as 96x96 art. A tile is
64, so at `art_scale` 1 a bush stood a tile and a half tall — the same height as
the player — which flattens the size hierarchy the valley depends on: ground
cover, then the man, then the canopy at four tiles.

**They cannot simply be drawn smaller.** `Prop.art_scale` snaps to whole numbers
on purpose (see its docstring): at 96/64 = 1.5 some source pixels would land as
two screen pixels and some as one, and the eye reads that unevenness as a broken
sprite long before it reads it as a smaller bush. 96px art has exactly three
sizes available to it — 96, 192, 288 — and none of them is one tile.

So the art is authored at 64 instead. That is not the same picture with fewer
pixels in it: at two thirds the canvas each leaf has to get *bigger* relative to
the bush, or the same silhouette comes back carrying detail too fine to survive
being looked at from across a room. A 96px bush shrunk down is a smudge; a 64px
bush is drawn in leaves you could count if you wanted to.

## How they are drawn

Three of the four are the same three passes, and the difference between a round
hedge and a sage bush is entirely in their arguments:

1. **The envelope**, filled with the darkest body tone. This is never seen
   directly — it is the shadow inside the bush, showing through the gaps.
2. **Leaves**, a couple of hundred small rotated ellipses stamped over it. Each
   one first casts a dark crescent off the side away from the light, so the leaf
   in front of it cannot merge with it. That crescent is the whole trick:
   without it, foliage is a green lump; with it, the same green is a mass of
   separate leaves sitting on top of one another.
3. **Light**, applied per leaf from a single direction against the bush's own
   volume, so it has a lit shoulder and a shaded belly rather than being evenly
   bright.

Leaves radiate away from a growth point, which is what stops the stamping from
reading as a texture swatch: a leaf near the left edge leans left, one at the
crown points up. They also sit slightly outside the envelope at falling odds,
which is what keeps the silhouette from being visibly the ellipse it came from.

**The cypress is not one of the three.** Stamped like a broadleaf it comes out a
lumpy pillar, because what says cypress is a clean flame outline and stamping
ravels it. So it fills its envelope with the light already on it and breaks that
up with short strokes leaning off the trunk — texture inside an edge nothing
touches. See `cypress_shrub`.

Positions come from a seeded generator per bush, so re-running this is a no-op
and re-tuning one bush cannot reshuffle the other three.

## Colour

Every ramp is lifted from the 96px original it replaces, sampled at its five
most common tones. The valley's colour identity is something
`tools/check_colour.py` watches — each zone has to keep reading as its own place
— and reusing the exact tones means swapping the art cannot drift the zone's hue
profile. It also keeps the round hedge on the right side of the blight's
reserved yellow-green, which it already had to be desaturated once to clear.

`thorn_bush` is not in here: it was authored at 64 already.
"""

from __future__ import annotations

import math
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

SIZE = 64
OUT = os.path.join(ROOT, "art", "sprites", "props")

CLEAR = (0, 0, 0, 0)

# Light comes from the upper left, as it does everywhere else in this project's
# art. Normalised, pointing at the light.
LIGHT = (-0.55, -0.83)

# Ramp indices, darkest first: the silhouette edge and the gaps between leaves,
# then shadow, body, sunlit, highlight.
EDGE, DARK, MID, LIT, HOT = 0, 1, 2, 3, 4

# The five tones of each bush, sampled from the 96px art being replaced.
RAMPS = {
	"cypress_shrub": [
		(0x17, 0x19, 0x04), (0x3a, 0x3d, 0x1b), (0x4d, 0x4f, 0x21),
		(0x5f, 0x63, 0x33), (0x74, 0x79, 0x3e),
	],
	"round_hedge": [
		(0x04, 0x25, 0x0d), (0x13, 0x43, 0x19), (0x30, 0x67, 0x31),
		(0x49, 0x88, 0x39), (0x6e, 0xa9, 0x50),
	],
	"hedge_shrub": [
		(0x15, 0x2e, 0x0f), (0x23, 0x45, 0x13), (0x61, 0x90, 0x47),
		(0x8e, 0xbb, 0x5f), (0x9b, 0xc6, 0x6a),
	],
	"sage_bush": [
		(0x28, 0x32, 0x1b), (0x4f, 0x5b, 0x39), (0x68, 0x73, 0x44),
		(0x8b, 0x93, 0x4f), (0xa7, 0xa7, 0x55),
	],
}


# ------------------------------------------------------------------- the sheet

class Sheet:
	"""A 64x64 canvas holding ramp indices rather than colours.

	Working in indices means shading is arithmetic on a small integer — a leaf
	can be pushed one step darker for sitting deep in the bush without anyone
	having to name a sixth colour that only exists to be the back of a bush.
	"""

	def __init__(self) -> None:
		self.cells = [None] * (SIZE * SIZE)

	def get(self, x: int, y: int):
		if 0 <= x < SIZE and 0 <= y < SIZE:
			return self.cells[y * SIZE + x]
		return None

	def put(self, x: int, y: int, tone: int) -> None:
		if 0 <= x < SIZE and 0 <= y < SIZE:
			self.cells[y * SIZE + x] = tone

	def opaque(self, x: int, y: int) -> bool:
		return self.get(x, y) is not None

	def pixels(self, ramp):
		out = []
		for cell in self.cells:
			if cell is None:
				out.append(CLEAR)
			else:
				r, g, b = ramp[max(0, min(4, cell))]
				out.append((r, g, b, 255))
		return out


# ------------------------------------------------------------------ the leaves

def leaf(sheet: Sheet, cx: float, cy: float, rx: float, ry: float,
		angle: float, tone: int) -> None:
	"""One leaf: a small rotated ellipse with a shadow cast off its dark side.

	**The shadow is a crescent, not a halo.** Ringing every leaf in dark makes a
	grid of beads; shading only the side away from the light makes a leaf that
	is sitting on top of another leaf. Drawn first and drawn over whatever is
	already there, so a near leaf darkens the one behind it.

	Within the leaf, the side facing the light is a step brighter and the far
	side a step darker. Three tones across six pixels is enough — the leaf is
	not the subject, the mass of them is.
	"""
	ca, sa = math.cos(angle), math.sin(angle)
	span = int(max(rx, ry)) + 3
	scale = max(rx, ry)
	for y in range(int(cy) - span, int(cy) + span + 1):
		for x in range(int(cx) - span, int(cx) + span + 1):
			dx, dy = x - cx, y - cy
			u = (dx * ca + dy * sa) / rx
			v = (-dx * sa + dy * ca) / ry
			d2 = u * u + v * v
			t = (dx * LIGHT[0] + dy * LIGHT[1]) / scale
			if d2 > 1.0:
				if d2 <= 1.0 + 4.2 / scale and t < -0.05 and sheet.opaque(x, y):
					sheet.put(x, y, min(sheet.get(x, y), DARK))
				continue
			shade = tone + (1 if t > 0.30 else (-1 if t < -0.34 else 0))
			sheet.put(x, y, max(DARK, min(HOT, shade)))


def scatter(sheet: Sheet, rng: random.Random, inside, normal, growth,
		count: int, rx: float, ry: float, lean: float = 1.0,
		fringe: float = 2.5, bias: int = 0) -> None:
	"""Stamp `count` leaves over whatever `inside(x, y)` says is bush.

	`normal` maps a point to where it sits inside the bush's own volume, as a
	pair in roughly [-1, 1]. That is what the light is applied to, and it is the
	difference between a bush and a green disc: the upper-left shoulder catches
	the sun and the lower-right belly does not, before a single leaf is drawn.

	`growth` is the point leaves grow away from: a leaf's angle is the direction
	from there to the leaf, which makes the crown point up and the flanks point
	out. `lean` scales how strictly that is obeyed — a hedge is nearly radial, a
	sage bush much less so.

	`bias` moves the whole bush along its ramp. A cypress is a dark plant and a
	sage bush is a pale one, and that difference lives in how much of each
	ramp's dark end gets used, not in the ramps themselves — which are sampled
	from the originals and not up for adjustment.

	`fringe` lets leaves sit up to that many pixels outside the envelope, at
	falling odds. Without it the silhouette is exactly the ellipse it was
	generated from, and nothing in a valley has an outline that clean.

	Leaves come off a jittered grid rather than a uniform random draw, because
	random points clump and leave bald patches, and a bald patch in the middle
	of a bush reads as a hole. They are then sorted back to front, so a near
	leaf shades the one behind it and never the other way round.
	"""
	spots = []
	step = math.sqrt(max(1.0, _area(inside) / max(count, 1)))
	# Leaves may ravel out sideways and upward but never below the foot of the
	# bush, or the fringe leaves a scatter of green in the grass underneath it.
	bottom = max((y for y in range(SIZE)
		for x in range(SIZE) if inside(x + 0.5, y + 0.5)), default=SIZE)
	y = 0.0
	while y < SIZE:
		x = 0.0
		while x < SIZE:
			px = x + rng.uniform(0.0, step)
			py = y + rng.uniform(0.0, step)
			x += step
			if py > bottom:
				continue
			if inside(px, py):
				spots.append((px, py))
				continue
			# Outside: keep it only if it is close in, and less often the
			# further out it is. This is what ravels the edge.
			out = _distance_out(inside, px, py, fringe)
			if out <= fringe and rng.random() < (1.0 - out / (fringe + 1.0)) * 0.55:
				spots.append((px, py))
		y += step
	rng.shuffle(spots)
	spots.sort(key=lambda spot: spot[1])
	gx, gy = growth
	for px, py in spots:
		angle = math.atan2(py - gy, px - gx)
		# Straight out from the growth point, then pulled back toward vertical
		# by `lean`.
		angle = math.atan2(math.sin(angle) * lean, math.cos(angle))
		# ...then knocked off true. Leaves that all agree on their angle read as
		# a combed texture rather than as foliage, and the streaking is very
		# visible on a bush whose leaves are long.
		angle += rng.uniform(-0.55, 0.55)
		leaf(sheet, px, py, rx * rng.uniform(0.82, 1.18),
			ry * rng.uniform(0.82, 1.18), angle, tone_at(normal, px, py, bias))


def _area(inside) -> float:
	return float(sum(1 for y in range(SIZE) for x in range(SIZE)
		if inside(x + 0.5, y + 0.5)))


def _distance_out(inside, x: float, y: float, limit: float) -> float:
	"""Roughly how far a point sits outside the envelope, in pixels."""
	step = 0.5
	d = step
	while d <= limit:
		for i in range(8):
			a = math.tau * i / 8.0
			if inside(x + math.cos(a) * d, y + math.sin(a) * d):
				return d
		d += step
	return limit + 1.0


def fill(sheet: Sheet, inside, tone: int) -> None:
	"""The envelope, which is only ever seen through the gaps."""
	for y in range(SIZE):
		for x in range(SIZE):
			if inside(x + 0.5, y + 0.5):
				sheet.put(x, y, tone)


def tone_at(normal, x: float, y: float, bias: int = 0, gain: float = 1.0) -> int:
	"""Where a point sits on the ramp, given the light and the bush's volume.

	`gain` stretches the result across the ramp. A shape lit mostly across its
	width only ever sees the horizontal part of the light vector, so without it
	a tall narrow plant comes out in two tones and looks like a painted post.
	"""
	nx, ny = normal(x, y)
	t = (nx * LIGHT[0] + ny * LIGHT[1]) * gain
	if t > 0.68:
		tone = HOT
	elif t > 0.28:
		tone = LIT
	elif t > -0.18:
		tone = MID
	else:
		tone = DARK
	return max(DARK, min(HOT, tone + bias))


def shade_fill(sheet: Sheet, inside, normal, bias: int = 0,
		gain: float = 1.0) -> None:
	"""Fill the envelope with the light on it, rather than flat.

	For the conifer, which is not built out of leaves — see `cypress_shrub`.
	"""
	for y in range(SIZE):
		for x in range(SIZE):
			if inside(x + 0.5, y + 0.5):
				sheet.put(x, y, tone_at(normal, x + 0.5, y + 0.5, bias, gain))


def needles(sheet: Sheet, rng: random.Random, inside, count: int,
		centre: float = 32.0) -> None:
	"""Short sprays, a step either side of the tone underneath them.

	A conifer is not a mass of leaves and stamping it like one is what made the
	first attempt look like a lumpy pillar. What it has is fine texture inside a
	very clean outline — so the outline here is exactly the envelope, untouched,
	and all the detail happens inside it.

	Strokes lean away from the trunk as they descend, which is the direction
	cypress foliage actually hangs. Drawn straight down they comb into vertical
	stripes and the plant reads as a painted post.
	"""
	spots = [(x, y) for y in range(SIZE) for x in range(SIZE)
		if inside(x + 0.5, y + 0.5)]
	if not spots:
		return
	for x, y in rng.sample(spots, min(count, len(spots))):
		length = rng.choice((2, 3, 3, 4, 5))
		roll = rng.random()
		lift = 1 if roll < 0.45 else (-1 if roll < 0.85 else -2)
		drift = 1 if x > centre else -1
		at_x = float(x)
		for step in range(length):
			at_y = y + step
			at_x += drift * 0.4
			base = sheet.get(int(at_x), at_y)
			if base is None or not inside(int(at_x) + 0.5, at_y + 0.5):
				break
			sheet.put(int(at_x), at_y, max(DARK, min(HOT, base + lift)))


def occlude(sheet: Sheet, rows: int) -> None:
	"""Darken the last few rows of the silhouette, per column.

	Where the bush meets the ground is the one place it is not lit from
	anywhere, and without this every bush looks like it is hovering an inch up.
	"""
	for x in range(SIZE):
		column = [y for y in range(SIZE) if sheet.opaque(x, y)]
		if not column:
			continue
		floor = max(column)
		for y in range(floor - rows + 1, floor + 1):
			cell = sheet.get(x, y)
			if cell is not None:
				sheet.put(x, y, max(DARK, cell - 1))


def outline(sheet: Sheet) -> None:
	"""One dark pixel around the silhouette, so a bush does not dissolve into
	the grass it is standing on. Same rule as the material pickups."""
	edge = []
	for y in range(SIZE):
		for x in range(SIZE):
			if sheet.opaque(x, y):
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				if sheet.opaque(x + dx, y + dy):
					edge.append((x, y))
					break
	for x, y in edge:
		sheet.put(x, y, EDGE)


def ravel(sheet: Sheet, rng: random.Random, chance: float) -> None:
	"""Bite the odd pixel off either flank.

	For the shapes drawn as a filled envelope rather than stamped: a hand-clean
	curve is the one thing in a valley that looks generated, and a bitten edge
	costs four pixels to fix it.
	"""
	for y in range(SIZE):
		row = [x for x in range(SIZE) if sheet.opaque(x, y)]
		if len(row) < 6:
			continue
		if rng.random() < chance:
			sheet.cells[y * SIZE + min(row)] = None
		if rng.random() < chance:
			sheet.cells[y * SIZE + max(row)] = None


def despeckle(sheet: Sheet) -> None:
	"""Drop single pixels hanging off the silhouette.

	A leaf whose halo left one pixel stranded is a fleck of green in the grass,
	and at 64px a stray pixel is a visible defect rather than a soft edge.
	"""
	loose = []
	for y in range(SIZE):
		for x in range(SIZE):
			if not sheet.opaque(x, y):
				continue
			neighbours = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
				if sheet.opaque(x + dx, y + dy))
			if neighbours <= 1:
				loose.append((x, y))
	for x, y in loose:
		sheet.cells[y * SIZE + x] = None


# ------------------------------------------------------------------ the bushes
#
# Each of these owns a silhouette and a leaf size and nothing else.

def ellipse(cx: float, cy: float, rx: float, ry: float):
	"""An envelope and the volume that goes with it.

	Returned as a pair because the two always travel together: the shape decides
	where leaves may sit and the volume decides how they are lit, and a bush
	whose lighting belongs to a different shape than its outline looks wrong in
	a way that is very hard to name.
	"""
	def inside(x: float, y: float) -> bool:
		u, v = (x - cx) / rx, (y - cy) / ry
		return u * u + v * v <= 1.0

	def normal(x: float, y: float):
		return (x - cx) / rx, (y - cy) / ry

	return inside, normal


def cypress_shrub(rng: random.Random) -> Sheet:
	"""The one conifer, and the only one here not built out of leaves.

	**A cypress is an outline with texture in it, not a mass of leaves.** Stamped
	like the others it comes out a lumpy pillar, because the thing that says
	cypress is the clean flame silhouette and stamping ravels it. So this one
	fills its envelope with the light already on it and then breaks the fill up
	with short vertical strokes — fine needle texture inside an edge that was
	never touched.
	"""
	sheet = Sheet()
	top, foot, peak = 6.0, 60.0, 16.0

	def half_at(y: float) -> float:
		f = max(0.0, min(1.0, (y - top) / (foot - top)))
		# A flame, not a triangle: it swells fast out of the tip, carries its
		# width through the middle, and draws back in at the foot. A cone would
		# read as a fir, and a fir is a tree.
		return peak * (f ** 0.40) * (1.0 - 0.30 * max(0.0, f - 0.62) / 0.38)

	def inside(x: float, y: float) -> bool:
		return top <= y <= foot and abs(x - 32.0) <= half_at(y)

	def normal(x: float, y: float):
		# Across the trunk for the light, up it for the falloff — a cypress is a
		# cylinder, so it is lit like one.
		# Weighted hard toward the horizontal: on a column this thin, letting the
		# vertical term have equal say lights the top and shades the foot, which
		# is how you draw a bullet. A cypress is lit down one side.
		return (x - 32.0) / max(half_at(y), 1.0), (y - 26.0) / 70.0

	shade_fill(sheet, inside, normal, gain=2.2)
	needles(sheet, rng, inside, 300)
	ravel(sheet, rng, 0.25)
	occlude(sheet, 3)
	despeckle(sheet)
	outline(sheet)
	return sheet


def round_hedge(rng: random.Random) -> Sheet:
	"""A clipped ball. Regular on purpose — it is the one bush in the set that
	somebody planted, and it should read as tended next to the wild ones."""
	sheet = Sheet()
	inside, normal = ellipse(32.0, 32.0, 26.0, 25.0)
	fill(sheet, inside, DARK)
	scatter(sheet, rng, inside, normal, (32.0, 32.0), 170, 2.9, 2.1,
		lean=1.0, fringe=2.0)
	occlude(sheet, 4)
	despeckle(sheet)
	outline(sheet)
	return sheet


def hedge_shrub(rng: random.Random) -> Sheet:
	"""A wide, low dome — the default bush, and the one there is most of. The
	ragged crown is what keeps a row of them from being a row of one bush."""
	sheet = Sheet()
	dome, normal = ellipse(32.0, 38.0, 28.0, 22.0)

	def inside(x: float, y: float) -> bool:
		return dome(x, y) and y <= 59.0

	fill(sheet, inside, DARK)
	scatter(sheet, rng, inside, normal, (32.0, 56.0), 185, 2.7, 2.0,
		lean=1.4, fringe=3.0)
	occlude(sheet, 4)
	despeckle(sheet)
	outline(sheet)
	return sheet


def sage_bush(rng: random.Random) -> Sheet:
	"""A ragged spray. Longer, thinner leaves thrown out sideways from a low
	crown — the loose one, next to which the hedge reads as clipped."""
	sheet = Sheet()
	body, normal = ellipse(32.0, 44.0, 29.0, 17.0)

	def inside(x: float, y: float) -> bool:
		return body(x, y) and y <= 60.0

	fill(sheet, inside, DARK)
	scatter(sheet, rng, inside, normal, (32.0, 62.0), 150, 3.2, 1.5,
		lean=0.9, fringe=3.5)
	occlude(sheet, 3)
	despeckle(sheet)
	outline(sheet)
	return sheet


BUSHES = {
	"cypress_shrub": cypress_shrub,
	"round_hedge": round_hedge,
	"hedge_shrub": hedge_shrub,
	"sage_bush": sage_bush,
}


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	for name, build in BUSHES.items():
		sheet = build(random.Random(sum(ord(c) * (i + 1) for i, c in enumerate(name))))
		path = os.path.join(OUT, "%s.png" % name)
		write_png(path, SIZE, SIZE, sheet.pixels(RAMPS[name]))
		covered = sum(1 for cell in sheet.cells if cell is not None)
		print("  %-18s %dx%d  %d px drawn" % (name + ".png", SIZE, SIZE, covered))


if __name__ == "__main__":
	main()
