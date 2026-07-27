#!/usr/bin/env python3
"""Generate the 64px greybox tileset for Ambry.

    python3 tools/gen_greybox_tileset.py

A 4x5 atlas of 64x64 tiles for blocking out the village before any art exists.

**Tiles are distinguished by pattern, not only by colour.** A greybox you can
only read in colour is one you can't read in a screenshot, can't read
colourblind, and can't read once you're squinting at pacing instead of at
pixels. Every tile has a distinct fill pattern as well as a distinct value.

Two things are deliberate about the palette. The village leans warm, because
that is the one location that gets the warm end of the palette and the player's
body should register safety before they read a word. And the blight creep tile
is the only saturated colour in the set, so even in greybox the encroaching edge
is the thing your eye goes to.
"""

from __future__ import annotations

import os
import struct
import zlib

TILE = 64
COLS = 4
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art", "tilesets", "greybox_64.png"
)

# name, base colour, pattern, solid
TILES = [
    # ground — warm, walkable, low contrast so actors read against it
    ("dirt_path",     (0x5b, 0x4d, 0x3d), "grid",  False),
    ("grass_yard",    (0x4a, 0x50, 0x3c), "dots",  False),
    ("cobble",        (0x5a, 0x55, 0x4c), "brick", False),
    ("floorboards",   (0x6a, 0x56, 0x3e), "plank", False),

    # structure
    ("wall",          (0x7d, 0x6b, 0x53), "solid", True),
    ("wall_inner",    (0x59, 0x4c, 0x3b), "solid", True),
    ("roof",          (0x8a, 0x6b, 0x4c), "plank", False),   # overhead layer
    ("fence",         (0x6e, 0x5c, 0x42), "post",  True),

    # village features
    ("door",          (0xb0, 0x94, 0x55), "ring",  False),
    ("window",        (0x8f, 0xa6, 0xb5), "cross", True),
    ("hearth",        (0xc2, 0x7a, 0x3a), "bloom", False),   # the warmth
    ("well",          (0x6a, 0x6f, 0x74), "ring",  True),

    # rebuild sites — the progression system, blocked out
    ("plot_empty",    (0x53, 0x4c, 0x44), "cross", False),
    ("plot_ruined",   (0x46, 0x41, 0x3c), "dots",  False),
    ("stockpile",     (0x74, 0x62, 0x45), "brick", True),
    ("bed_save",      (0x4e, 0x6d, 0x7a), "ring",  False),

    # edges
    ("gate",          (0x8a, 0x7a, 0x5e), "post",  True),
    ("npc_marker",    (0x6b, 0x74, 0x5e), "ring",  False),
    ("blight_creep",  (0x9d, 0xba, 0x33), "bloom", True),    # the only saturated tile
    ("void",          (0x17, 0x18, 0x1b), "hatch", True),
]

SOLID = {name for name, _c, _p, solid in TILES if solid}


def shade(colour, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in colour)


def draw_tile(base, pattern):
    px = [[base for _ in range(TILE)] for _ in range(TILE)]
    dark, light, mid = shade(base, 0.62), shade(base, 1.32), shade(base, 0.84)

    if pattern == "grid":
        for i in range(0, TILE, 16):
            for j in range(TILE):
                px[i][j] = mid
                px[j][i] = mid
    elif pattern == "solid":
        for y in range(0, 14):
            for x in range(TILE):
                px[y][x] = light
        for y in range(TILE - 8, TILE):
            for x in range(TILE):
                px[y][x] = dark
    elif pattern == "hatch":
        for y in range(TILE):
            for x in range(TILE):
                if (x + y) % 12 < 3:
                    px[y][x] = light
    elif pattern == "dots":
        for y in range(4, TILE, 12):
            for x in range(4, TILE, 12):
                for dy in range(3):
                    for dx in range(3):
                        px[y + dy][x + dx] = dark
    elif pattern == "brick":
        for y in range(0, TILE, 16):
            offset = 0 if (y // 16) % 2 == 0 else 16
            for x in range(TILE):
                px[y][x] = dark
            for x in range(offset, TILE, 32):
                for dy in range(16):
                    if y + dy < TILE:
                        px[y + dy][x] = dark
    elif pattern == "plank":
        for y in range(0, TILE, 12):
            for x in range(TILE):
                px[y][x] = dark
        for x in range(0, TILE, 21):
            for y in range(TILE):
                px[y][x] = mid
    elif pattern == "post":
        for x in range(6, TILE, 20):
            for y in range(12, TILE - 6):
                for dx in range(6):
                    if x + dx < TILE:
                        px[y][x + dx] = light
        for y in range(18, 24):
            for x in range(TILE):
                px[y][x] = light
    elif pattern == "bloom":
        for cy, cx, r in ((20, 20, 13), (44, 40, 11), (24, 46, 8), (46, 18, 7)):
            for y in range(TILE):
                for x in range(TILE):
                    if (y - cy) ** 2 + (x - cx) ** 2 <= r * r:
                        px[y][x] = light if (x + y) % 7 < 4 else base
    elif pattern == "ring":
        cx = cy = TILE // 2
        for y in range(TILE):
            for x in range(TILE):
                d2 = (y - cy) ** 2 + (x - cx) ** 2
                if 18 ** 2 <= d2 <= 22 ** 2 or d2 <= 7 ** 2:
                    px[y][x] = light
    elif pattern == "cross":
        for i in range(18):
            for t in range(3):
                px[t][i] = light
                px[i][t] = light
                px[TILE - 1 - t][TILE - 1 - i] = light
                px[TILE - 1 - i][TILE - 1 - t] = light

    # One-pixel border on every tile: while blocking out, the thing being judged
    # is spacing and sightlines, and cell boundaries have to stay visible.
    for i in range(TILE):
        px[0][i] = dark
        px[TILE - 1][i] = dark
        px[i][0] = dark
        px[i][TILE - 1] = dark
    return px


def main() -> None:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    rows = (len(TILES) + COLS - 1) // COLS
    width, height = COLS * TILE, rows * TILE
    sheet = [[(0, 0, 0, 0)] * width for _ in range(height)]

    for index, (_name, base, pattern, _solid) in enumerate(TILES):
        tile = draw_tile(base, pattern)
        ox, oy = (index % COLS) * TILE, (index // COLS) * TILE
        for y in range(TILE):
            for x in range(TILE):
                r, g, b = tile[y][x]
                sheet[oy + y][ox + x] = (r, g, b, 255)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + bytes(v for p in sheet[y] for v in p) for y in range(height))
    with open(OUT, "wb") as handle:
        handle.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b"")
        )

    print(f"{OUT}  {width}x{height}  {len(TILES)} tiles, {rows} rows")
    for index, (name, _c, pattern, solid) in enumerate(TILES):
        print("  (%d,%d)  %-6s %-14s %s"
              % (index % COLS, index // COLS, "SOLID" if solid else "", name, pattern))


if __name__ == "__main__":
    main()
