#!/usr/bin/env python3
"""Turn a pile of exported frames into the horizontal strips this project reads.

    python3 tools/pack_strips.py ~/Downloads/wolf --actor forest_wolf
    python3 tools/pack_strips.py ~/Downloads/wolf --actor forest_wolf --clip walk
    python3 tools/pack_strips.py ~/Downloads/hero --actor player --dry-run

Pixellab (and every other generator) exports one PNG per frame per direction,
named however it feels like. `SpriteAnimation` wants one horizontal strip per
direction, named exactly `<actor>_<clip>_<direction>.png`. This is the bridge,
and it exists because doing it by hand is where the transcription errors are —
a frame packed out of order is a limp that nobody can find by reading code.

**Direction is read from compass words in the filename**, in any of the forms
these tools emit: `south`, `s`, `south-east`, `southeast`, `se`, `nw`, and so
on. **Frame order is the trailing number**, so `walk_south_1.png` ... `_4.png`
pack left to right. **Clip** is any of idle/walk/attack_1..3/dodge/hurt/death
appearing in the name; pass `--clip` when the filenames don't say.

Every frame in one strip must be the same size, and by convention that size is
square (see tools/build_animation_set.py, which infers frame counts from it).
Mismatches are reported and refused rather than padded — a silently padded
frame shifts the whole animation off its anchor.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_colour import read_png  # noqa: E402  (same folder, deliberate)

# Compass spellings -> the slot names in SpriteAnimation. Longest first, so
# "south-east" is matched before "south".
COMPASS = [
    ("south_east", "down_side"), ("southeast", "down_side"), ("south-east", "down_side"),
    ("north_east", "up_side"), ("northeast", "up_side"), ("north-east", "up_side"),
    ("south_west", "down_side_west"), ("southwest", "down_side_west"),
    ("south-west", "down_side_west"),
    ("north_west", "up_side_west"), ("northwest", "up_side_west"),
    ("north-west", "up_side_west"),
    ("south", "down"), ("north", "up"), ("east", "side"), ("west", "side_west"),
]
# Two-letter forms, matched only as whole tokens so "se" inside "sheath" is safe.
ABBREVIATIONS = {
    "se": "down_side", "ne": "up_side", "sw": "down_side_west", "nw": "up_side_west",
    "s": "down", "n": "up", "e": "side", "w": "side_west",
    # And the names we already use, so re-packing our own output works.
    "down": "down", "up": "up", "side": "side",
}

CLIPS = ["attack_1", "attack_2", "attack_3", "idle", "walk", "dodge", "hurt", "death"]


def classify(name: str, forced_clip: str | None) -> tuple[str | None, str | None, int]:
    stem = os.path.splitext(os.path.basename(name))[0].lower()

    clip = forced_clip
    if clip is None:
        for candidate in CLIPS:
            if candidate in stem:
                clip = candidate
                break
        # "attack" with no number is hit 1.
        if clip is None and "attack" in stem:
            clip = "attack_1"

    direction = None
    for spelling, slot in COMPASS:
        if spelling in stem:
            direction = slot
            break
    if direction is None:
        for token in re.split(r"[^a-z]+", stem):
            if token in ABBREVIATIONS:
                direction = ABBREVIATIONS[token]
                break

    numbers = re.findall(r"\d+", stem)
    # The clip name may carry a digit (attack_1); the frame index is the last one.
    index = int(numbers[-1]) if numbers else 0
    return clip, direction, index


def write_png(path: str, width: int, height: int, pixels) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += bytes((r, g, b, a))

    def chunk(kind: bytes, payload: bytes) -> bytes:
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="folder of exported frames")
    parser.add_argument("--actor", required=True, help="e.g. player, forest_wolf")
    parser.add_argument("--clip", help="force the clip when filenames don't name one")
    parser.add_argument("--dry-run", action="store_true", help="report, write nothing")
    args = parser.parse_args()

    if args.clip and args.clip not in CLIPS:
        sys.exit(f"--clip must be one of: {', '.join(CLIPS)}")

    source = os.path.expanduser(args.source)
    if not os.path.isdir(source):
        sys.exit(f"no such directory: {source}")

    groups: dict[tuple[str, str], list] = {}
    skipped = []
    for entry in sorted(os.listdir(source)):
        if not entry.lower().endswith(".png"):
            continue
        clip, direction, index = classify(entry, args.clip)
        if clip is None or direction is None:
            skipped.append((entry, "clip" if clip is None else "direction"))
            continue
        groups.setdefault((clip, direction), []).append((index, entry))

    for entry, why in skipped:
        print(f"  skipped {entry}: could not read the {why} from the filename")
    if not groups:
        sys.exit("nothing to pack — pass --clip, or rename the frames to include a direction")

    out_dir = os.path.join(ROOT, "art", "sprites", args.actor)
    if not args.dry_run:
        os.makedirs(out_dir, exist_ok=True)

    for (clip, direction), frames in sorted(groups.items()):
        frames.sort()
        sizes, strips = set(), []
        for _, entry in frames:
            width, height, pixels = read_png(os.path.join(source, entry))
            sizes.add((width, height))
            strips.append(pixels)
        if len(sizes) > 1:
            print(f"  ! {clip}/{direction}: mixed frame sizes {sorted(sizes)} — skipped")
            continue

        width, height = sizes.pop()
        if width != height:
            print(f"  ! {clip}/{direction}: frames are {width}x{height}, not square — "
                  "build_animation_set.py will need --frames")

        total = width * len(strips)
        packed = [(0, 0, 0, 0)] * (total * height)
        for column, pixels in enumerate(strips):
            for y in range(height):
                start = y * total + column * width
                packed[start:start + width] = pixels[y * width:(y + 1) * width]

        name = f"{args.actor}_{clip}_{direction}.png"
        order = ", ".join(str(index) for index, _ in frames)
        print(f"  {name:<40} {len(strips)} frames ({order}) -> {total}x{height}")
        if not args.dry_run:
            write_png(os.path.join(out_dir, name), total, height, packed)

    if args.dry_run:
        print("\ndry run — nothing written")
    else:
        print(f"\nwrote to art/sprites/{args.actor}/")
        print(f"next: python3 tools/build_animation_set.py {args.actor}")


if __name__ == "__main__":
    main()
