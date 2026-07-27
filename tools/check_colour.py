#!/usr/bin/env python3
"""Colour discipline check. Replaces the old fixed-palette checker.

    python3 tools/check_colour.py
    python3 tools/check_colour.py --map /tmp/colour_map.png
    python3 tools/check_colour.py --verbose

The project no longer runs on one fixed palette (GDD §15 A5). That decision
bought colour space; it did not buy permission to use it anywhere. Two things
the palette used to guarantee for free now have to be checked explicitly:

**1. The blight is the only thing that glows.** One luminous yellow-green,
reserved. Anything else sitting in that hue at high saturation competes with the
antagonist for the player's eye, and the antagonist has no other screen presence
— it never speaks and never appears as a figure. This is the hard rule and the
only thing that fails the build.

**2. Zones read as different places.** Previously guaranteed by giving each zone
a different slice of a shared palette. Now it has to be looked at: the report
below prints each directory's hue and saturation profile so drift is visible,
and `--map` plots them so two zones converging is obvious at a glance.

Icons are exempt from the saturation advisory. They live in a UI panel, not in
the world, and a bright gemstone in an inventory slot is not competing with
anything.
"""

from __future__ import annotations

import argparse
import colorsys
import os
import struct
import sys
import zlib
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Directories to profile, and whether world-art rules apply to them.
#   world=True  → the saturation advisory applies
#   world=False → UI surface, exempt
GROUPS = [
    ("sprites", os.path.join(ROOT, "art", "sprites"), True),
    ("tilesets", os.path.join(ROOT, "art", "tilesets"), True),
    ("icons", os.path.join(ROOT, "art", "icons"), False),
]

# The reserved accent. Hue in degrees, plus the floors that make it "glow"
# rather than merely "be greenish" — a muted olive is fine, a luminous
# yellow-green is the Blight.
BLIGHT_HUE = (60.0, 100.0)
BLIGHT_MIN_SATURATION = 0.55
BLIGHT_MIN_VALUE = 0.45

# Files allowed to use the reserved accent: the blight itself, and the tilesets
# that legitimately contain a blight tile among many.
BLIGHT_ALLOWED = ("blight", "rot", "husk", "seeder", "grave_bloom", "scale_demo", "greybox")

# A highlight edge that happens to land in the band is not a claim on the
# accent. Both thresholds must be crossed before a file is flagged, so a stray
# pixel is ignored and an actual yellow-green glow is not.
BLIGHT_TOLERANCE_PX = 40
BLIGHT_TOLERANCE_FRACTION = 0.02

# Above this share of high-saturation pixels, world art is shouting.
SATURATION_ADVISORY = 0.20
HOT_SATURATION = 0.65
HOT_VALUE = 0.45


# ---------------------------------------------------------------- PNG reading

def read_png(path: str):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat = 8, bytearray()
    width = height = depth = colour_type = interlace = 0
    plte = trns = b""
    while pos + 8 <= len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width = int.from_bytes(chunk[0:4], "big")
            height = int.from_bytes(chunk[4:8], "big")
            depth, colour_type, interlace = chunk[8], chunk[9], chunk[12]
        elif kind == b"PLTE":
            plte = chunk
        elif kind == b"tRNS":
            trns = chunk
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    if depth != 8:
        raise ValueError(f"bit depth {depth} unsupported (export 8-bit)")
    if interlace:
        raise ValueError("interlaced PNG unsupported")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour_type)
    if channels is None:
        raise ValueError(f"colour type {colour_type} unsupported")

    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    pixels, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        kind_byte = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        _unfilter(line, previous, kind_byte, channels, stride)
        previous = line
        for x in range(width):
            pixels.append(_rgba(line, x, colour_type, plte, trns))
    return width, height, pixels


def _unfilter(line, prev, kind, bpp, stride):
    if kind == 0:
        return
    if kind == 1:
        for x in range(bpp, stride):
            line[x] = (line[x] + line[x - bpp]) & 0xFF
    elif kind == 2:
        for x in range(stride):
            line[x] = (line[x] + prev[x]) & 0xFF
    elif kind == 3:
        for x in range(stride):
            left = line[x - bpp] if x >= bpp else 0
            line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
    elif kind == 4:
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[x] = (line[x] + pr) & 0xFF
    else:
        raise ValueError(f"unknown filter {kind}")


def _rgba(line, x, colour_type, plte, trns):
    if colour_type == 6:
        i = x * 4
        return (line[i], line[i + 1], line[i + 2], line[i + 3])
    if colour_type == 2:
        i = x * 3
        return (line[i], line[i + 1], line[i + 2], 255)
    if colour_type == 4:
        i = x * 2
        return (line[i], line[i], line[i], line[i + 1])
    if colour_type == 0:
        return (line[x], line[x], line[x], 255)
    index = line[x]
    i = index * 3
    return (plte[i], plte[i + 1], plte[i + 2],
            trns[index] if index < len(trns) else 255)


# ------------------------------------------------------------------ analysis

def is_blight(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return (BLIGHT_HUE[0] <= h * 360 <= BLIGHT_HUE[1]
            and s >= BLIGHT_MIN_SATURATION and v >= BLIGHT_MIN_VALUE)


def is_hot(r, g, b):
    _h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return s >= HOT_SATURATION and v >= HOT_VALUE


def scan(directory):
    files = []
    for base, _dirs, names in os.walk(directory):
        for name in sorted(names):
            if name.lower().endswith(".png"):
                files.append(os.path.join(base, name))
    return files


def profile(files):
    colours, hot, blight, opaque = Counter(), 0, 0, 0
    offenders = []
    for path in files:
        try:
            _w, _h, pixels = read_png(path)
        except ValueError:
            continue
        name = os.path.basename(path).lower()
        exempt = any(token in name for token in BLIGHT_ALLOWED)
        local_blight = 0
        for r, g, b, a in pixels:
            if a == 0:
                continue
            opaque += 1
            colours[(r, g, b)] += 1
            if is_hot(r, g, b):
                hot += 1
            if is_blight(r, g, b):
                blight += 1
                local_blight += 1
        local_opaque = sum(1 for _r, _g, _b, a in pixels if a > 0) or 1
        if (not exempt and local_blight > BLIGHT_TOLERANCE_PX
                and local_blight / local_opaque > BLIGHT_TOLERANCE_FRACTION):
            offenders.append((path, local_blight))
    return colours, hot, blight, opaque, offenders


def hue_profile(colours):
    """Weighted share of pixels per 30-degree hue bucket, plus mean saturation."""
    buckets = [0] * 12
    grey = 0
    sat_sum = 0.0
    total = 0
    for (r, g, b), count in colours.items():
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        total += count
        sat_sum += s * count
        if s < 0.12:
            grey += count
        else:
            buckets[int(h * 360) // 30 % 12] += count
    if total == 0:
        return buckets, 0.0, 0.0
    return ([b / total for b in buckets], grey / total, sat_sum / total)


# ------------------------------------------------------------------- the map

def write_map(path, groups):
    """Hue (x) against saturation (y), one panel per group.

    Two zones that have converged look the same here, which is the point — zone
    identity used to be guaranteed by a palette slice and is now something you
    have to be able to see.
    """
    panel_w, panel_h, pad = 380, 190, 30
    width = pad + len(groups) * (panel_w + pad)
    height = pad * 2 + panel_h
    img = [[(22, 23, 26, 255)] * width for _ in range(height)]

    for index, (name, colours, _world) in enumerate(groups):
        ox = pad + index * (panel_w + pad)
        oy = pad
        for y in range(panel_h):
            for x in range(panel_w):
                img[oy + y][ox + x] = (32, 33, 37, 255)
        # reserved blight band
        x0 = int(BLIGHT_HUE[0] / 360 * panel_w)
        x1 = int(BLIGHT_HUE[1] / 360 * panel_w)
        y1 = int((1.0 - BLIGHT_MIN_SATURATION) * panel_h)
        for y in range(0, y1):
            for x in range(x0, x1):
                img[oy + y][ox + x] = (46, 50, 34, 255)
        total = sum(colours.values()) or 1
        for (r, g, b), count in colours.items():
            h, s, _v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            px = ox + int(h * panel_w)
            py = oy + int((1.0 - s) * (panel_h - 1))
            radius = 1 if count / total < 0.01 else 2
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    yy, xx = py + dy, px + dx
                    if oy <= yy < oy + panel_h and ox <= xx < ox + panel_w:
                        img[yy][xx] = (r, g, b, 255)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + bytes(v for p in img[y] for v in p) for y in range(height))
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    print(f"\ncolour map: {path}  (x = hue, y = saturation, shaded band = reserved)")


# ---------------------------------------------------------------------- main

HUE_NAMES = ["red", "orange", "yellow", "chartreuse", "green", "spring",
             "cyan", "azure", "blue", "violet", "magenta", "rose"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--map", help="write a hue/saturation map to this path")
    parser.add_argument("--verbose", action="store_true", help="list offending files")
    args = parser.parse_args()

    failures = 0
    map_groups = []

    for name, directory, world in GROUPS:
        files = scan(directory)
        if not files:
            print(f"{name}: no PNGs yet")
            continue
        colours, hot, blight, opaque, offenders = profile(files)
        buckets, grey, mean_sat = hue_profile(colours)
        map_groups.append((name, colours, world))

        top = sorted(range(12), key=lambda i: -buckets[i])[:3]
        dominant = ", ".join(f"{HUE_NAMES[i]} {buckets[i] * 100:.0f}%" for i in top if buckets[i] > 0.01)

        print(f"\n{name}: {len(files)} file(s), {len(colours)} unique colours")
        print(f"   dominant hues   {dominant or '(none)'}")
        print(f"   neutral/grey    {grey * 100:.0f}%   mean saturation {mean_sat:.2f}")
        print(f"   high-saturation {hot / max(opaque, 1) * 100:.1f}% of pixels")

        if world and hot / max(opaque, 1) > SATURATION_ADVISORY:
            print(f"   NOTE  above the {SATURATION_ADVISORY * 100:.0f}% advisory for world art —"
                  " the blight has to out-shout this")

        if offenders:
            failures += len(offenders)
            print(f"   FAIL  {len(offenders)} file(s) use the reserved blight accent"
                  f" (hue {BLIGHT_HUE[0]:.0f}-{BLIGHT_HUE[1]:.0f}, sat>={BLIGHT_MIN_SATURATION})")
            shown = offenders if args.verbose else offenders[:5]
            for path, count in sorted(shown, key=lambda o: -o[1]):
                print(f"           {os.path.relpath(path, ROOT)}  {count} px")
            if not args.verbose and len(offenders) > 5:
                print(f"           ... and {len(offenders) - 5} more (--verbose)")

    if args.map and map_groups:
        write_map(args.map, map_groups)

    print()
    if failures:
        print(f"{failures} file(s) claim the blight's colour.")
        print("Shift the hue off yellow-green, or drop the saturation, or rename the")
        print("asset to something the allowlist covers if it genuinely is blight.")
        return 1
    print("Blight accent is uncontested.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
