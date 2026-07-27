#!/usr/bin/env python3
"""Fail the build if any sprite uses a colour outside the project palette.

    python3 tools/check_palette.py
    python3 tools/check_palette.py --palette art/palettes/endesga-64.gpl
    python3 tools/check_palette.py --list          # print the palette and exit

The art direction rests on one rule — *corruption is the one saturated colour,
everything else muted* — and that rule holds only if nothing else in frame is
saturated. Off-palette colours never announce themselves. A filter, a gradient,
a resize, a paste from a reference image, a generated layer: any of these can
introduce a handful of near-miss pixels that look fine on their own sprite and
quietly dilute the visual language across forty of them.

This finds them. Run it before committing art.

Exit code is 0 when everything is on-palette, 1 otherwise, so it works as a
pre-commit hook or a CI step as-is. No third-party dependencies — the PNG
reader below handles what Pixelorama and Godot emit.
"""

from __future__ import annotations

import argparse
import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE_DIR = os.path.join(ROOT, "art", "palettes")
SEARCH_DIRS = [
    os.path.join(ROOT, "art", "sprites"),
    os.path.join(ROOT, "art", "tilesets"),
    os.path.join(ROOT, "art", "icons"),
]

# Placeholders that are deliberately not in the palette. Keep this list short —
# every entry is a file the checker is blind to.
IGNORE_PREFIXES = ("scale_demo_",)

# Colours no palette needs to contain.
FULLY_TRANSPARENT = 0


# ---------------------------------------------------------------- PNG reading

def read_png(path: str):
    """Return (width, height, [(r, g, b, a), ...]). Depth 8, non-interlaced."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")

    pos = 8
    idat = bytearray()
    width = height = depth = colour_type = interlace = 0
    plte = b""
    trns = b""
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
        raise ValueError(f"bit depth {depth} unsupported (export as 8-bit)")
    if interlace:
        raise ValueError("interlaced PNG unsupported (turn interlacing off)")

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour_type)
    if channels is None:
        raise ValueError(f"colour type {colour_type} unsupported")

    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        _unfilter(line, previous, filter_type, channels, stride)
        rows.append(line)
        previous = line

    pixels = []
    for line in rows:
        for x in range(width):
            pixels.append(_to_rgba(line, x, channels, colour_type, plte, trns))
    return width, height, pixels


def _unfilter(line: bytearray, prev: bytearray, kind: int, bpp: int, stride: int) -> None:
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
        raise ValueError(f"unknown PNG filter {kind}")


def _to_rgba(line: bytearray, x: int, channels: int, colour_type: int, plte: bytes, trns: bytes):
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
        v = line[x]
        return (v, v, v, 255)
    index = line[x]                                   # colour type 3
    i = index * 3
    alpha = trns[index] if index < len(trns) else 255
    return (plte[i], plte[i + 1], plte[i + 2], alpha)


# ------------------------------------------------------------ palette loading

def load_palette(path: str) -> list[tuple[int, int, int]]:
    """Read a GIMP .gpl or a Lospec .hex / .txt palette."""
    colours: list[tuple[int, int, int]] = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()

    if lines and lines[0].strip().lower().startswith("gimp palette"):
        for line in lines[1:]:
            line = line.strip()
            if not line or line.startswith("#") or ":" in line.split()[0]:
                continue
            parts = line.split()
            if len(parts) >= 3 and all(p.isdigit() for p in parts[:3]):
                colours.append(tuple(int(p) for p in parts[:3]))
        return colours

    for line in lines:                                # .hex — one RRGGBB per line
        token = line.strip().lstrip("#")
        if len(token) == 6:
            try:
                colours.append((int(token[0:2], 16), int(token[2:4], 16), int(token[4:6], 16)))
            except ValueError:
                pass
    return colours


def find_palette() -> str | None:
    if not os.path.isdir(PALETTE_DIR):
        return None
    candidates = sorted(
        f for f in os.listdir(PALETTE_DIR)
        if f.lower().endswith((".gpl", ".hex", ".txt"))
    )
    return os.path.join(PALETTE_DIR, candidates[0]) if candidates else None


# ------------------------------------------------------------------ the check

def sprite_files() -> list[str]:
    found = []
    for directory in SEARCH_DIRS:
        for base, _dirs, files in os.walk(directory):
            for name in sorted(files):
                if not name.lower().endswith(".png"):
                    continue
                if name.startswith(IGNORE_PREFIXES):
                    continue
                found.append(os.path.join(base, name))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--palette", help="palette file (default: first in art/palettes/)")
    parser.add_argument("--list", action="store_true", help="print the palette and exit")
    args = parser.parse_args()

    palette_path = args.palette or find_palette()
    if palette_path is None:
        print("No palette found in art/palettes/.")
        print("Download the project palette as .gpl and commit it there — see")
        print("art/palettes/README.md. Nothing can be checked until then.")
        return 1

    palette = load_palette(palette_path)
    if not palette:
        print(f"Could not read any colours from {palette_path}")
        return 1

    name = os.path.relpath(palette_path, ROOT)
    if args.list:
        print(f"{name} — {len(palette)} colours")
        for r, g, b in palette:
            print(f"  #{r:02x}{g:02x}{b:02x}")
        return 0

    allowed = set(palette)
    files = sprite_files()
    print(f"palette: {name} ({len(palette)} colours)")
    print(f"checking {len(files)} sprite(s)\n")

    failures = 0
    for path in files:
        rel = os.path.relpath(path, ROOT)
        try:
            _w, _h, pixels = read_png(path)
        except ValueError as error:
            print(f"  SKIP  {rel} — {error}")
            failures += 1
            continue

        offenders: dict[tuple[int, int, int], int] = {}
        for r, g, b, a in pixels:
            if a == FULLY_TRANSPARENT:
                continue
            if (r, g, b) not in allowed:
                offenders[(r, g, b)] = offenders.get((r, g, b), 0) + 1

        if not offenders:
            print(f"  ok    {rel}")
            continue

        failures += 1
        total = sum(offenders.values())
        print(f"  FAIL  {rel} — {len(offenders)} off-palette colour(s), {total} pixel(s)")
        for colour, count in sorted(offenders.items(), key=lambda kv: -kv[1])[:8]:
            nearest, distance = _nearest(colour, palette)
            print("          #{:02x}{:02x}{:02x} x{:<6} nearest #{:02x}{:02x}{:02x} (delta {})".format(
                *colour, count, *nearest, distance))
        if len(offenders) > 8:
            print(f"          ... and {len(offenders) - 8} more")

    print()
    if failures:
        print(f"{failures} file(s) with problems.")
        print("Fix in Pixelorama by re-indexing the sprite to the project palette,")
        print("then re-export. A near-miss delta usually means a filter or a resize.")
        return 1
    print("All sprites on palette.")
    return 0


def _nearest(colour, palette):
    """Closest palette entry, to show whether it's a near-miss or a real stray."""
    best = min(palette, key=lambda p: sum((a - b) ** 2 for a, b in zip(colour, p)))
    distance = int(sum((a - b) ** 2 for a, b in zip(colour, best)) ** 0.5)
    return best, distance


if __name__ == "__main__":
    sys.exit(main())
