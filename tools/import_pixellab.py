#!/usr/bin/env python3
"""Turn a Pixellab export folder into strips this project can read.

    python3 tools/import_pixellab.py ~/Downloads/hero --actor player --frame 128 --body 96
    python3 tools/import_pixellab.py ~/Downloads/wolf --actor forest_wolf --frame 96 --body 48
    python3 tools/import_pixellab.py ~/Downloads/fox  --actor fox --dry-run

`pack_strips.py` assembles frames that are already the right size. This is the
step before it: Pixellab exports a large square canvas (176 or 188 px) with the
subject floating somewhere in the middle, and neither the size nor the position
is what `AnimationComponent` expects.

**Nothing is ever rescaled.** The exports are already at 1:1 — one image pixel
per art pixel — and resampling would destroy that. All this does is choose a
window and copy pixels through it.

**One window for every frame of a character, and the same window next time.**
Cropping each frame to its own bounds is the obvious version and it is wrong
twice over. A walk cycle whose frames are individually centred jitters; and
Pixellab pads the canvas deliberately, so that animations have room to swing a
sword or throw a lunge past the idle silhouette — crop to the idle bounds and
the first attack you export gets its blade cut off.

So the window is derived from two things that do not move as clips are added:
the **canvas centre** horizontally (which is where Pixellab puts the character,
and keeps a turning actor standing on the same spot), and the **feet row of the
idle rotations** vertically. Re-run this after exporting a walk cycle and every
strip still lines up with the ones written today. Everything outside the frame
is headroom you chose with `--frame`; make it generous.

**The feet land on the anchor.** `AnimationComponent` offsets the sprite up by
`body_height / 2`, so the bottom of the subject has to sit at

    y = frame_size / 2 + body_height / 2

within the frame. Pass `--body` to declare it; the crop is positioned to satisfy
it exactly, so the number in the scene and the pixels in the file cannot drift
apart. Left unset, the measured subject height is used and printed for you to
paste into the scene.

Reads `metadata.json` for the rotation and animation layout, so it does not care
what the folders are called.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_colour import read_png          # noqa: E402
from pack_strips import write_png          # noqa: E402

# Pixellab's compass names -> the slots in SpriteAnimation.
DIRECTIONS = {
    "south": "down",
    "north": "up",
    "east": "side",
    "south-east": "down_side",
    "north-east": "up_side",
    "west": "side_west",
    "south-west": "down_side_west",
    "north-west": "up_side_west",
}

# Pixellab animation names -> our clip names. Anything unlisted is passed
# through lowercased, so a clip named "Attack_1" already works.
CLIPS = {
    "breathing_idle": "idle",
    "idle": "idle",
    "walking": "walk",
    "walk": "walk",
    "running": "walk",
    "attack": "attack_1",
    "slash": "attack_1",
    "hurt": "hurt",
    "hit": "hurt",
    "dying": "death",
    "death": "death",
    "dodge": "dodge",
    "roll": "dodge",
}

ALPHA_FLOOR = 8      # below this, a pixel is background rather than a soft edge


def bounds(pixels, width: int, height: int):
    minx, miny, maxx, maxy = width, height, -1, -1
    for y in range(height):
        row = y * width
        for x in range(width):
            if pixels[row + x][3] > ALPHA_FLOOR:
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
    return minx, miny, maxx, maxy


def load_all(source: str, meta: dict):
    """Every frame in the export, as {(clip, direction): [(index, path)]}."""
    state = meta["states"][0]
    frames = state["frames"]
    out: dict[tuple[str, str], list] = {}

    for compass, path in frames.get("rotations", {}).items():
        slot = DIRECTIONS.get(compass)
        if slot is None:
            print(f"  ! unknown direction '{compass}', skipped")
            continue
        out[("idle", slot)] = [(0, os.path.join(source, path))]

    for name, per_direction in frames.get("animations", {}).items():
        clip = CLIPS.get(name.lower(), name.lower())
        for compass, paths in per_direction.items():
            slot = DIRECTIONS.get(compass)
            if slot is None:
                continue
            out[(clip, slot)] = [(i, os.path.join(source, p)) for i, p in enumerate(paths)]
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="unzipped Pixellab export (contains metadata.json)")
    parser.add_argument("--actor", required=True, help="e.g. player, forest_wolf, fox")
    parser.add_argument("--frame", type=int, default=0,
                        help="output frame size; default is the smallest multiple of 16 that fits")
    parser.add_argument("--body", type=int, default=0,
                        help="body_height to anchor the feet against; default is the measured height")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    source = os.path.expanduser(args.source)
    meta_path = os.path.join(source, "metadata.json")
    if not os.path.isfile(meta_path):
        sys.exit(f"no metadata.json in {source}")
    with open(meta_path, encoding="utf-8") as handle:
        meta = json.load(handle)

    groups = load_all(source, meta)
    if not groups:
        sys.exit("the export contains no rotations or animations")

    # A clip carries one frame count for all eight directions (SpriteAnimation
    # slices by texture width / frames), but an export often animates only the
    # direction you asked for — Pixellab will give you a four-frame breathing
    # idle facing south and single poses everywhere else. Hold the still ones on
    # frame 0 for the same duration rather than dropping the animation or
    # refusing the import: you get motion where you are looking, and the seven
    # static directions cost seven repeated pixels-per-frame.
    for clip in {name for name, _ in groups}:
        counts = {d: len(f) for (c, d), f in groups.items() if c == clip}
        longest = max(counts.values())
        stretched = [d for d, n in counts.items() if n != longest]
        for direction in stretched:
            entries = groups[(clip, direction)]
            if len(entries) != 1:
                sys.exit("%s/%s has %d frames but %s has %d — cannot reconcile"
                         % [clip, direction, len(entries), clip, longest])
            groups[(clip, direction)] = [(i, entries[0][1]) for i in range(longest)]
        if stretched:
            print("  %s: %d frames; holding %s on their standing pose"
                  % (clip, longest, ", ".join(sorted(stretched))))

    # One pass to measure, one to write. The union is what makes every frame
    # share an origin.
    cache: dict[str, tuple] = {}
    union = [10 ** 6, 10 ** 6, -1, -1]     # every frame — reported, so you can size --frame
    rest = [10 ** 6, 10 ** 6, -1, -1]      # the idle rotations only — this sets the anchor
    canvas_w = canvas_h = 0
    for (clip, _direction), entries in groups.items():
        for _, path in entries:
            if path not in cache:
                cache[path] = read_png(path)
            width, height, pixels = cache[path]
            canvas_w, canvas_h = width, height
            box = bounds(pixels, width, height)
            if box[2] < 0:
                continue
            for target in ([union, rest] if clip == "idle" else [union]):
                target[0] = min(target[0], box[0])
                target[1] = min(target[1], box[1])
                target[2] = max(target[2], box[2])
                target[3] = max(target[3], box[3])
    if rest[2] < 0:
        rest = list(union)

    subject_w = union[2] - union[0] + 1
    subject_h = union[3] - union[1] + 1
    frame = args.frame or (max(subject_w, subject_h) + 15) // 16 * 16
    standing_h = rest[3] - rest[1] + 1
    body = args.body or standing_h

    if subject_w > frame or subject_h > frame:
        sys.exit(f"subject is {subject_w}x{subject_h}; --frame {frame} is too small")

    # The row the feet must land on, and therefore the window.
    anchor = frame // 2 + body // 2
    # Feet from the standing pose, centre from the canvas. Both are stable as
    # animations are added; the union is not.
    crop_y = rest[3] + 1 - anchor
    crop_x = canvas_w // 2 - frame // 2

    print(f"{args.actor}: canvas {canvas_w}x{canvas_h} -> frame {frame}x{frame}")
    print(f"  standing {rest[2] - rest[0] + 1}x{standing_h}, widest frame {subject_w}x{subject_h}")
    print(f"  body_height {body}, feet at y={anchor}")
    if standing_h != body:
        print(f"  (declared body {body} differs from the measured {standing_h} — the feet are "
              f"still anchored exactly; this number only sets the sprite offset)")

    out_dir = os.path.join(ROOT, "art", "sprites", args.actor)
    if not args.dry_run:
        os.makedirs(out_dir, exist_ok=True)

    written = 0
    for (clip, direction), entries in sorted(groups.items()):
        entries.sort()
        total = frame * len(entries)
        packed = [(0, 0, 0, 0)] * (total * frame)
        for column, (_, path) in enumerate(entries):
            width, height, pixels = cache[path]
            for y in range(frame):
                src_y = crop_y + y
                if src_y < 0 or src_y >= height:
                    continue
                base = y * total + column * frame
                for x in range(frame):
                    src_x = crop_x + x
                    if 0 <= src_x < width:
                        packed[base + x] = pixels[src_y * width + src_x]

        name = f"{args.actor}_{clip}_{direction}.png"
        print(f"  {name:<38} {len(entries)} frame(s) -> {total}x{frame}")
        if not args.dry_run:
            write_png(os.path.join(out_dir, name), total, frame, packed)
        written += 1

    portrait = os.path.join(source, meta["states"][0]["folder"], "portrait.png")
    if os.path.isfile(portrait) and not args.dry_run:
        width, height, pixels = read_png(portrait)
        write_png(os.path.join(out_dir, f"{args.actor}_portrait.png"), width, height, pixels)
        print(f"  {args.actor}_portrait.png{'':<20} {width}x{height}")

    if args.dry_run:
        print("\ndry run — nothing written")
        return
    print(f"\nwrote {written} strips to art/sprites/{args.actor}/")
    print(f"next: python3 tools/build_animation_set.py {args.actor}")
    print(f"      and set body_height = {body} on the actor's AnimationComponent")


if __name__ == "__main__":
    main()
