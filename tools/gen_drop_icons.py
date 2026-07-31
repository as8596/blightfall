#!/usr/bin/env python3
"""Draw the icons for what enemies leave behind.

    python3 tools/gen_drop_icons.py

Placeholders, and they look like it. Same rule as `gen_skill_icons.py`: what
they have to do is be told apart by **shape** at 32px, because a loot pile shows
several at once and the player is reading a list, not admiring a still life.

Muted, per the project's colour discipline — `tools/check_colour.py` keeps the
one saturated band in the game reserved for the blight, and none of these go
near it.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pack_strips import write_png  # noqa: E402

SIZE = 32
OUT = os.path.join(ROOT, "art", "icons", "items", "drops")
CLEAR = (0, 0, 0, 0)
EDGE = (26, 22, 19, 255)

MEAT = (168, 78, 72, 255)
MEAT_DARK = (122, 52, 50, 255)
FAT = (222, 198, 176, 255)
BONE = (226, 218, 198, 255)
HIDE = (128, 96, 60, 255)
HIDE_DARK = (92, 68, 42, 255)
CLOTH = (122, 116, 104, 255)
CLOTH_DARK = (86, 82, 74, 255)


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


def outline(px, colour=EDGE):
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


def raw_meat():
    """A cut on the bone. The bone is what stops it reading as a red blob."""
    px = blank()
    blob(px, 17, 18, 11, 9, MEAT)
    blob(px, 14, 15, 6, 4, MEAT_DARK)
    rect(px, 5, 8, 9, 11, BONE)          # the shank
    rect(px, 7, 10, 12, 13, BONE)
    blob(px, 6, 8, 3, 3, BONE)
    blob(px, 22, 22, 4, 3, FAT)
    return outline(px)


def wolf_hide():
    """A stretched pelt: wider at the shoulders, four legs, a tail. Nothing
    else in the set has limbs, which is the whole of how you tell it apart."""
    px = blank()
    blob(px, 16, 16, 8, 11, HIDE)
    rect(px, 3, 9, 9, 13, HIDE)          # foreleg left
    rect(px, 23, 9, 29, 13, HIDE)        # foreleg right
    rect(px, 5, 20, 10, 24, HIDE)        # hindleg left
    rect(px, 22, 20, 27, 24, HIDE)       # hindleg right
    rect(px, 15, 26, 17, 30, HIDE_DARK)  # tail
    blob(px, 16, 13, 4, 3, HIDE_DARK)
    return outline(px)


def rags():
    """A bundle of torn cloth. Deliberately shapeless — it is the one drop that
    should look like it was worth nothing to whoever had it."""
    px = blank()
    blob(px, 16, 19, 10, 8, CLOTH)
    rect(px, 6, 12, 26, 16, CLOTH)
    for i, x in enumerate((9, 15, 21)):
        rect(px, x, 24, x + 2, 28 - i, CLOTH_DARK)   # torn strips hanging
    rect(px, 6, 12, 26, 13, CLOTH_DARK)
    return outline(px)


ICONS = {"raw_meat": raw_meat, "wolf_hide": wolf_hide, "rags": rags}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, build in ICONS.items():
        write_png(os.path.join(OUT, "%s.png" % name), SIZE, SIZE, build())
        print("  %s.png" % name)


if __name__ == "__main__":
    main()
