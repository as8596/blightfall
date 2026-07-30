#!/usr/bin/env python3
"""Draw the skill icons.

    python3 tools/gen_skill_icons.py

Nine 32x32 placeholders, one per skill. Placeholders, and they look like it —
what they have to do is exactly one thing, and it is the thing an icon in a tree
is for: **be told apart at a glance, by shape.**

A tree read by hovering is a tree you read one node at a time. The whole point
of icons over text rows is that the shape of a branch is legible before you
point at anything — so these are built around silhouette, not detail. A sword, a
spear and an axe are three outlines you can tell apart at 32px; three grey
rectangles with different labels are not.

Muted, per GDD §8. These sit in a dark panel and the one saturated colour in
this game belongs to the blight, so nothing here goes near it —
`tools/check_colour.py` exempts icons from the saturation advisory but not from
the reserved hue, and none of these are in that band.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

SIZE = 32
OUT = os.path.join(ROOT, "art", "icons", "skills")
CLEAR = (0, 0, 0, 0)

STEEL = (150, 154, 162, 255)
STEEL_LIT = (196, 200, 208, 255)
STEEL_DARK = (96, 100, 108, 255)
WOOD = (112, 84, 52, 255)
WOOD_DARK = (78, 58, 36, 255)
LEATHER = (128, 96, 58, 255)
LEATHER_DARK = (88, 64, 38, 255)
FLESH = (170, 74, 66, 255)
FLESH_DARK = (118, 48, 44, 255)
AIR = (150, 170, 178, 255)
AIR_DIM = (104, 120, 128, 255)
EDGE_COLOUR = (24, 21, 18, 255)


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


def taper(px, y0, y1, half0, half1, cx, colour):
    """A wedge: half-width runs from `half0` at `y0` to `half1` at `y1`."""
    span = max(y1 - y0, 1)
    for y in range(max(y0, 0), min(y1 + 1, SIZE)):
        t = (y - y0) / span
        half = half0 + (half1 - half0) * t
        rect(px, int(cx - half), y, int(cx + half), y, colour)


def outline(px, colour=EDGE_COLOUR):
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


# ------------------------------------------------------------------ Blade

def edge():
    """A short sword, point up. The root of the branch, so the plainest shape."""
    px = blank()
    taper(px, 5, 20, 1.5, 3.0, 16, STEEL)
    rect(px, 14, 5, 15, 20, STEEL_LIT)
    rect(px, 10, 21, 22, 22, WOOD_DARK)      # crossguard
    rect(px, 15, 23, 17, 28, WOOD)           # grip
    return outline(px)


def long_arm():
    """A spear. Same family as the sword, obviously longer — the shape is the
    stat."""
    px = blank()
    rect(px, 15, 12, 17, 29, WOOD)
    rect(px, 15, 12, 15, 29, WOOD_DARK)
    taper(px, 2, 12, 0.5, 3.5, 16, STEEL)
    rect(px, 15, 3, 16, 11, STEEL_LIT)
    return outline(px)


def cleave():
    """An axe head. Wide where the sword is narrow."""
    px = blank()
    rect(px, 15, 6, 17, 28, WOOD)
    blob(px, 11, 13, 9, 7, STEEL)
    blob(px, 13, 13, 7, 5, STEEL_LIT)
    rect(px, 18, 4, 30, 24, CLEAR)           # cut the blade back off the haft
    rect(px, 15, 6, 17, 28, WOOD)
    return outline(px)


# ------------------------------------------------------------------- Body

def scar():
    """A heart with a seam across it. Not a clean heart — nothing out here
    heals right."""
    px = blank()
    blob(px, 12, 13, 6, 6, FLESH)
    blob(px, 20, 13, 6, 6, FLESH)
    taper(px, 15, 27, 9.0, 0.5, 16, FLESH)
    blob(px, 12, 11, 3, 3, (198, 96, 86, 255))
    for i in range(6):
        px[(12 + i) * SIZE + (20 - i)] = FLESH_DARK
        px[(12 + i) * SIZE + (21 - i)] = FLESH_DARK
    return outline(px)


def porter():
    """A pack. Trapezoid, strap, buckle."""
    px = blank()
    taper(px, 10, 27, 7.0, 9.5, 16, LEATHER)
    rect(px, 8, 10, 24, 12, LEATHER_DARK)    # flap
    rect(px, 14, 10, 18, 20, LEATHER_DARK)   # strap
    rect(px, 14, 17, 18, 19, (196, 178, 120, 255))
    return outline(px)


def thick_hide():
    """A shield. The only rounded-bottom shape in the set."""
    px = blank()
    rect(px, 7, 5, 25, 16, LEATHER)
    taper(px, 16, 28, 9.5, 0.5, 16, LEATHER)
    rect(px, 7, 5, 25, 7, LEATHER_DARK)
    rect(px, 15, 8, 17, 24, LEATHER_DARK)
    return outline(px)


# ------------------------------------------------------------------- Wind

def breath():
    """Three moving lines. Nothing solid in the whole icon, which is the
    branch's character."""
    px = blank()
    for i, y in enumerate((9, 15, 21)):
        length = (20, 24, 16)[i]
        rect(px, 5, y, 5 + length, y + 2, AIR)
        rect(px, 5 + length, y - 2, 5 + length + 2, y + 2, AIR_DIM)
    return outline(px)


def steady():
    """An hourglass — time, which is what recovery buys back."""
    px = blank()
    rect(px, 8, 4, 24, 6, WOOD)
    rect(px, 8, 26, 24, 28, WOOD)
    taper(px, 7, 15, 7.5, 1.0, 16, AIR)
    taper(px, 16, 25, 1.0, 7.5, 16, AIR)
    taper(px, 18, 25, 0.5, 6.0, 16, AIR_DIM)
    return outline(px)


def light_step():
    """A boot. The only icon with a flat base, so it reads as ground contact."""
    px = blank()
    rect(px, 11, 5, 19, 22, LEATHER)
    rect(px, 11, 22, 27, 27, LEATHER_DARK)
    rect(px, 11, 5, 13, 22, (156, 120, 74, 255))
    rect(px, 11, 26, 27, 27, (60, 46, 30, 255))
    return outline(px)


ICONS = {
    "edge": edge, "long_arm": long_arm, "cleave": cleave,
    "scar": scar, "porter": porter, "thick_hide": thick_hide,
    "breath": breath, "steady": steady, "light_step": light_step,
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, build in ICONS.items():
        write_png(os.path.join(OUT, "%s.png" % name), SIZE, SIZE, build())
        print("  %s.png" % name)


if __name__ == "__main__":
    main()
