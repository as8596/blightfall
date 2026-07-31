#!/usr/bin/env python3
"""Move the terrain grass out of the blight's colour.

    python3 tools/shift_grass_hue.py

`tools/check_colour.py` reserves hue 60-100 at saturation 0.55 and up for one
thing: the blight. That reservation is the whole reason the rot reads as wrong
when it appears — it is the only saturated yellow-green in the game.

The imported grass tilesets sit squarely in that band (measured: hue ~101,
saturation 0.70, and 91k pixels of the dirt sheet inside the window). Left
alone, healthy grass and the rot are the same colour, and when the blight
creeps into Orchardfall it reads as more grass rather than as something wrong.

**The source art is not modified.** This writes derived copies into
`art/tilesets/derived/` and `tools/build_terrain_tileset.gd` reads those, so the
originals stay exactly as they were exported and the whole transform is one
deletion away from being undone.

The shift is a hue rotation rather than a desaturation, because the vividness is
presumably why the art was picked — dropping saturation to clear the band would
take the life out of it. Yellow-green becomes an ordinary leaf green, which is
what grass mostly is anyway.
"""

from __future__ import annotations

import colorsys
import os
import sys
import zlib
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The untouched exports live outside `art/tilesets/` on purpose. Everything
# under that directory is scanned by `tools/check_colour.py`, and the originals
# would fail it forever — they are the reason this script exists. Keeping them
# in `art/source/` says plainly that they are input, not shipped art.
SRC = os.path.join(ROOT, "art", "source", "tilesets")
OUT = os.path.join(ROOT, "art", "tilesets", "derived")

SOURCES = [
    ("sandy dirt ↗ field grass-godot.png", "grass_dirt.png"),
    ("forest pond ↗ field grass-godot.png", "grass_water.png"),
]

# The reserved window, slightly widened at the edges so the fringe pixels that
# antialias into it move with the body of the colour rather than being left
# behind as a rim in the old hue.
BAND_LO, BAND_HI = 50.0, 108.0
# Where those hues land instead: a leaf green, clear of the reservation.
TARGET_LO, TARGET_HI = 104.0, 132.0
# Below this saturation a pixel is too grey for its hue to read, and moving it
# only risks tinting the dirt.
MIN_SAT = 0.20


def read_png(path):
    d = open(path, "rb").read()
    pos, idat = 8, b""
    w = h = ct = 0
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        if typ == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", d[pos + 8:pos + 18])
        elif typ == b"IDAT":
            idat += d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    bpp = {2: 3, 6: 4}[ct]
    stride = w * bpp
    out = bytearray()
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        f = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line
        prev = line
    return w, h, bpp, bytes(out)


def write_png(path, w, h, bpp, data):
    raw = b"".join(b"\x00" + data[y * w * bpp:(y + 1) * w * bpp] for y in range(h))
    ct = 6 if bpp == 4 else 2

    def chunk(tag, payload):
        body = tag + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b""))


def shift(w, h, bpp, data):
    px = bytearray(data)
    moved = 0
    for o in range(0, len(px), bpp):
        r, g, b = px[o] / 255.0, px[o + 1] / 255.0, px[o + 2] / 255.0
        hue, light, sat = colorsys.rgb_to_hls(r, g, b)
        degrees = hue * 360.0
        if sat < MIN_SAT or not (BAND_LO <= degrees <= BAND_HI):
            continue
        t = (degrees - BAND_LO) / (BAND_HI - BAND_LO)
        wanted = TARGET_LO + (TARGET_HI - TARGET_LO) * t
        nr, ng, nb = colorsys.hls_to_rgb(wanted / 360.0, light, sat)
        px[o] = int(round(nr * 255))
        px[o + 1] = int(round(ng * 255))
        px[o + 2] = int(round(nb * 255))
        moved += 1
    return bytes(px), moved


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for source, target in SOURCES:
        path = os.path.join(SRC, source)
        if not os.path.exists(path):
            print("  missing: %s" % source)
            sys.exit(1)
        w, h, bpp, data = read_png(path)
        shifted, moved = shift(w, h, bpp, data)
        write_png(os.path.join(OUT, target), w, h, bpp, shifted)
        print("  %-22s %d of %d pixels moved out of the blight band"
              % (target, moved, w * h))


if __name__ == "__main__":
    main()
