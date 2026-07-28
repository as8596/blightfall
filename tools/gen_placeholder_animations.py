#!/usr/bin/env python3
"""Build placeholder animation strips from the 64x96 reference character.

    python3 tools/gen_placeholder_animations.py

Composites the reference bodies into 128x128 frames at the documented anchor and
offsets each per frame, producing real multi-frame strips in exactly the format
the game expects. They are not animation — a body sliding around is not a walk
cycle — but they are enough to prove the whole path end to end before a single
real frame is drawn: strip slicing, the feet-on-origin offset, direction
flipping, and above all that attack frames advance off the combo's frame data
rather than off a frame rate.

**Three bodies, four directions.** Which body a strip uses is read off its own
name, so `_up` cannot silently get the front view — which is exactly what it
had been doing, and the reason the character faced the camera while walking
north. West is east flipped at runtime, so there is no fourth body to draw.

Replace these with real exports from Pixelorama one animation at a time.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_size_study as ref                                    # noqa: E402

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art", "sprites", "player"
)

FRAME = 128
BODY_W, BODY_H = 64, 96
# Feet anchor inside the frame: centred horizontally, floor margin below.
ANCHOR_X = FRAME // 2
ANCHOR_Y = FRAME - (FRAME - BODY_H) // 2       # 112

# name -> per-frame (dx, dy) offsets from the anchor.
STRIPS = {
    # A breath. Two frames is the whole idle budget.
    "player_idle_down": [(0, 0), (0, -1)],
    "player_idle_up": [(0, 0), (0, -1)],
    "player_idle_side": [(0, 0), (0, -1)],
    # A bob. Real walk cycles move legs; this moves the whole body, which is
    # obviously wrong and obviously a placeholder — deliberately so.
    "player_walk_down": [(0, 0), (0, -2), (0, 0), (0, -1)],
    "player_walk_up": [(0, 0), (0, -2), (0, 0), (0, -1)],
    "player_walk_side": [(0, 0), (0, -2), (0, 0), (0, -1)],
    # Three frames, one per phase: wind-up leans back, the strike lunges
    # forward, recovery settles. Distinct enough that you can see which phase
    # the hitbox is in just by looking at the sprite — which is the point.
    "player_attack_1_side": [(-6, 0), (10, -2), (2, 0)],
    "player_attack_2_side": [(-6, 0), (10, -2), (2, 0)],
    "player_attack_3_side": [(-9, 0), (14, -3), (3, 0)],
    "player_attack_1_down": [(0, 4), (0, 12), (0, 3)],
    "player_attack_2_down": [(0, 4), (0, 12), (0, 3)],
    "player_attack_3_down": [(0, 6), (0, 16), (0, 4)],
    "player_attack_1_up": [(0, -4), (0, -12), (0, -3)],
    "player_attack_2_up": [(0, -4), (0, -12), (0, -3)],
    "player_attack_3_up": [(0, -6), (0, -16), (0, -4)],
    # Curls in, then extends out of the roll.
    "player_dodge_side": [(-2, 6), (6, 10), (12, 6), (16, 0)],
    "player_dodge_down": [(0, 4), (0, 8), (0, 6), (0, 0)],
    "player_dodge_up": [(0, -4), (0, -8), (0, -6), (0, 0)],
    "player_hurt_down": [(0, -4)],
    "player_hurt_up": [(0, -4)],
    "player_hurt_side": [(-6, -4)],
    # Sinks to the floor.
    "player_death_down": [(0, 0), (0, 8), (0, 18), (0, 30), (0, 40)],
    "player_death_up": [(0, 0), (0, 8), (0, 18), (0, 30), (0, 40)],
    "player_death_side": [(0, 0), (-4, 8), (-8, 18), (-12, 30), (-14, 40)],
}


def composite(body, frames):
    """Lay `body` into one 128x128 cell per offset, side by side."""
    width = FRAME * len(frames)
    sheet = [["."] * width for _ in range(FRAME)]
    for index, (dx, dy) in enumerate(frames):
        left = index * FRAME + ANCHOR_X - BODY_W // 2 + dx
        top = ANCHOR_Y - BODY_H + dy
        for y in range(BODY_H):
            for x in range(BODY_W):
                pixel = body[y][x]
                if pixel == ".":
                    continue
                ty, tx = top + y, left + x
                if 0 <= ty < FRAME and 0 <= tx < width:
                    sheet[ty][tx] = pixel
    return sheet, width


def facing_of(name: str) -> str:
    """Which of the three bodies a strip is drawn from, off its own name."""
    facing = name.rsplit("_", 1)[-1]
    assert facing in ref.BUILDERS_64, f"{name}: unknown facing '{facing}'"
    return facing


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    # Three bodies, built once each: south faces the camera, north is the back
    # of the head, and east is the profile. West is east flipped at runtime
    # (`AnimationComponent._flip`), which is why there is no fourth.
    bodies = {facing: build() for facing, build in ref.BUILDERS_64.items()}
    print(f"writing {len(STRIPS)} strips to {OUT_DIR}")
    for name, frames in STRIPS.items():
        sheet, width = composite(bodies[facing_of(name)], frames)
        ref.png(os.path.join(OUT_DIR, name + ".png"), sheet, width, FRAME)
        print(f"  {name}.png  {len(frames)} frames  {width}x{FRAME}  {facing_of(name)}")


if __name__ == "__main__":
    main()
