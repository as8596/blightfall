#!/usr/bin/env python3
"""Draw the three materials as they lie on the ground.

    python3 tools/gen_material_pickups.py

`world/pickup.tscn` ships a Sprite2D with no texture on it, which meant every
material scattered through Orchardfall was invisible — walkable, collectable,
and impossible to see. A pickup you cannot see is worse than no pickup: the
player learns the valley is empty and stops looking.

Placeholders, and they look like placeholders. What they have to do is exactly
two things, and both are about reading them at 1:1 from across a screen:

**Tell each other apart by silhouette, not by colour.** Timber is horizontal
bars, stone is a rounded heap, ironwork is a single blocky bar. Colour-coded
lumps of the same shape are three identical pickups to anyone playing at speed,
and to anyone colourblind they are three identical pickups full stop.

**Stay muted** (GDD §8). These sit on grass and dirt all over the zone, and the
one saturated colour in this game belongs to the blight. `tools/check_colour.py`
enforces that; these are nowhere near the reserved band.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

SIZE = 32
OUT = os.path.join(ROOT, "art", "sprites", "props")

CLEAR = (0, 0, 0, 0)


def blank():
    return [CLEAR] * (SIZE * SIZE)


def rect(px, x0, y0, x1, y1, colour):
    for y in range(max(y0, 0), min(y1 + 1, SIZE)):
        for x in range(max(x0, 0), min(x1 + 1, SIZE)):
            px[y * SIZE + x] = colour


def blob(px, cx, cy, rx, ry, colour):
    for y in range(SIZE):
        for x in range(SIZE):
            dx = (x - cx) / max(rx, 0.001)
            dy = (y - cy) / max(ry, 0.001)
            if dx * dx + dy * dy <= 1.0:
                px[y * SIZE + x] = colour


def outline(px, colour):
    """One-pixel dark edge, so a pickup does not dissolve into the grass."""
    edged = list(px)
    for y in range(SIZE):
        for x in range(SIZE):
            if px[y * SIZE + x][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < SIZE and 0 <= ny < SIZE and px[ny * SIZE + nx][3] != 0:
                    edged[y * SIZE + x] = colour
                    break
    return edged


EDGE = (26, 22, 18, 255)


def timber():
    """Three cut logs, stacked. Horizontal bars with visible end grain."""
    px = blank()
    bark, lit, grain = (86, 62, 38, 255), (112, 84, 52, 255), (140, 112, 76, 255)
    for i, y in enumerate((20, 15, 10)):
        left = 5 + i
        right = 26 - i
        rect(px, left, y, right, y + 4, bark)
        rect(px, left, y, right, y + 1, lit)
        # The sawn end, which is what makes it read as a log rather than a plank.
        rect(px, left, y + 1, left + 2, y + 3, grain)
    return outline(px, EDGE)


def stone():
    """A heap. Rounded, unequal, nothing straight about it."""
    px = blank()
    dark, mid, lit = (68, 68, 72, 255), (96, 96, 100, 255), (128, 128, 132, 255)
    blob(px, 11, 22, 8, 5, dark)
    blob(px, 21, 21, 7, 5, mid)
    blob(px, 16, 15, 8, 6, mid)
    blob(px, 15, 13, 5, 3, lit)
    blob(px, 20, 20, 3, 2, lit)
    return outline(px, EDGE)


def ironwork():
    """A single bar. Deliberately the simplest shape of the three — ironwork is
    the rarest material and the one you will be counting."""
    px = blank()
    dark, mid, lit = (58, 60, 66, 255), (92, 96, 104, 255), (146, 150, 158, 255)
    rect(px, 6, 14, 25, 22, mid)
    rect(px, 6, 14, 25, 15, lit)
    rect(px, 6, 21, 25, 22, dark)
    # Chamfered ends, so it is a forged bar and not a rectangle.
    rect(px, 6, 14, 7, 15, CLEAR)
    rect(px, 24, 21, 25, 22, CLEAR)
    return outline(px, EDGE)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, build in (("timber", timber), ("stone", stone), ("ironwork", ironwork)):
        path = os.path.join(OUT, "material_%s.png" % name)
        write_png(path, SIZE, SIZE, build())
        print("  material_%s.png" % name)


if __name__ == "__main__":
    main()
