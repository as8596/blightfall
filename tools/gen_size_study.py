#!/usr/bin/env python3
"""Draw the same character at three sizes, for choosing a sprite resolution.

    python3 tools/gen_size_study.py

Writes 16x24, 32x48 and 64x96 versions of one character into art/sprites/, each
carrying as much detail as its resolution actually supports. They are
placeholders for judging *size*, not final art and not in the project palette.

The small two are authored as ASCII grids, which is the honest way to place
384 and 1536 pixels. The large one is built from a tiny painting API instead:
6144 pixels is past the point where hand-counting rows stays reliable, and a
64px-wide head needs to be genuinely round rather than approximately round.
Everything is drawn as a left half and mirrored, so symmetry is exact.
"""

from __future__ import annotations

import math
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art", "sprites")

# One palette across all three, so the comparison is about resolution and
# nothing else. Muted per the art direction — no saturated colour, because the
# blight accent is meant to be the only one in frame.
PAL = {
    '.': (0, 0, 0, 0),
    '#': (0x22, 0x1f, 0x26, 255),  # outline
    'h': (0x33, 0x25, 0x1e, 255),  # hair shadow
    'H': (0x4a, 0x36, 0x2c, 255),  # hair
    'G': (0x63, 0x4a, 0x3a, 255),  # hair highlight
    'g': (0x7a, 0x5e, 0x49, 255),  # hair specular
    's': (0xa8, 0x82, 0x68, 255),  # skin shadow
    'S': (0xc9, 0xa3, 0x87, 255),  # skin
    'W': (0xdd, 0xbb, 0x9f, 255),  # skin highlight
    'E': (0x2b, 0x24, 0x2a, 255),  # eye
    'e': (0x6b, 0x7a, 0x74, 255),  # iris
    't': (0x47, 0x4c, 0x42, 255),  # tunic shadow
    'T': (0x5a, 0x60, 0x52, 255),  # tunic
    'U': (0x6e, 0x75, 0x63, 255),  # tunic highlight
    'A': (0x4a, 0x50, 0x45, 255),  # sleeve
    'L': (0x6b, 0x4a, 0x33, 255),  # belt
    'l': (0x52, 0x38, 0x26, 255),  # belt shadow
    'K': (0xa8, 0x8b, 0x4a, 255),  # buckle
    'p': (0x39, 0x3d, 0x36, 255),  # trouser shadow
    'P': (0x45, 0x4a, 0x40, 255),  # trousers
    'b': (0x4a, 0x38, 0x2c, 255),  # boot highlight
    'B': (0x3a, 0x2c, 0x24, 255),  # boot
}

# --------------------------------------------------------------------------
# 16x24 — silhouette, one flat colour per material, no shading. There is no
# room for a second tone anywhere; every pixel is doing structural work.
# --------------------------------------------------------------------------

ROWS_16 = [
    (0, ""), (5, "######"), (4, "##HHHH##"), (3, "#HHHHHHHH#"),
    (3, "#HSSSSSSH#"), (3, "#HSSSSSSH#"), (3, "#SEESSEES#"), (3, "#SSSSSSSS#"),
    (4, "#SSSSSS#"), (5, "######"), (4, "#TTTTTT#"), (2, "##TTTTTTTT##"),
    (1, "#ATTTTTTTTTTA#"), (1, "#ATTTTTTTTTTA#"), (1, "#ATTTTTTTTTTA#"),
    (1, "#ASSTTTTTTSSA#"), (2, "#TTTTTTTTTT#"), (2, "#LLLLLLLLLL#"),
    (2, "#TTTT##TTTT#"), (3, "#TT#..#TT#"), (3, "#TT#..#TT#"),
    (3, "#BB#..#BB#"), (3, "####..####"), (0, ""),
]

# --------------------------------------------------------------------------
# 32x48 — room for one shadow and one highlight per material. Hair gets a
# crown, skin gets a cheek shadow, the tunic gets a lit chest, the belt gets a
# buckle. This is where a sprite stops reading as a shape and starts reading as
# a person.
# --------------------------------------------------------------------------

ROWS_32 = [
    (0, ""), (0, ""), (12, "########"), (10, "##hhhhhhhh##"),
    (9, "#hhhHHHHHHHhh#"), (8, "#hhHHHHHHHHHHhh#"), (8, "#hHHHHGGGGHHHHh#"),
    (8, "#hHHHGGGGGGHHHh#"), (8, "#hHHHGGGGGGHHHh#"), (8, "#hHHHHGGGGHHHHh#"),
    (8, "#hhHHHHHHHHHHhh#"), (8, "#hhhhhhhhhhhhhh#"), (8, "#hSSSSSSSSSSSSh#"),
    (8, "#hSSSSSSSSSSSSh#"), (8, "#hSSEESSSSEESSh#"), (8, "#hSSEESSSSEESSh#"),
    (8, "#hSSSSSSSSSSSSh#"), (8, "#hSsSSSSSSSSsSh#"), (8, "#hSSSssssssSSSh#"),
    (9, "#SSSSSSSSSSSS#"), (10, "#SSSSSSSSSS#"), (13, "#ssss#"),
    (10, "##TTTTTTTT##"), (7, "##TTTTTTTTTTTTTT##"), (5, "##AAATTTTTTTTTTTTAAA##"),
    (5, "#AAAATTTTTTTTTTTTAAAA#"), (5, "#AAAATTTTUUUUTTTTAAAA#"),
    (5, "#AAAATTTUUUUUUTTTAAAA#"), (5, "#AAAATTTUUUUUUTTTAAAA#"),
    (5, "#AAAATTTTUUUUTTTTAAAA#"), (5, "#AAAATTTTTTTTTTTTAAAA#"),
    (5, "#SSS#TTTTTTTTTTTT#SSS#"), (5, "#SSS#TTTTTTTTTTTT#SSS#"),
    (5, ".###.TTTTTTTTTTTT.###."), (5, ".....#TTTTTTTTTT#....."),
    (7, "#LLLLLLLLLLLLLLLL#"), (7, "#LLLLLLLKKLLLLLLL#"), (7, "#PPPPPPPPPPPPPPPP#"),
    (8, "#PPPPP##..##PPPPP#"), (8, "#PPPPP#..#PPPPP#"), (8, "#PPPPP#..#PPPPP#"),
    (8, "#PppPP#..#PPppP#"), (8, "#PPPPP#..#PPPPP#"), (8, "#BBBBB#..#BBBBB#"),
    (8, "#BbbBB#..#BBbbB#"), (8, "#BBBBB#..#BBBBB#"), (8, "#BBBBB#..#BBBBB#"),
    (8, "#######..#######"),
]


def from_ascii(rows, w, h):
    grid = [['.'] * w for _ in range(h)]
    assert len(rows) == h, f"{len(rows)} rows, need {h}"
    for y, (indent, content) in enumerate(rows):
        line = "." * indent + content
        assert len(line) <= w, f"row {y} overflows: {len(line)} > {w}"
        for x, c in enumerate(line.ljust(w, ".")):
            grid[y][x] = c
    return grid


# --------------------------------------------------------------------------
# 64x96 — enough pixels for a per-material ramp (shadow / base / highlight /
# specular), an actual iris, brows, a nose, cloth folds, separated fingers and
# boot cuffs. Drawn as a left half and mirrored about x=31.5.
# --------------------------------------------------------------------------

W64, H64 = 64, 96


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [['.'] * w for _ in range(h)]

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c

    def span(self, y, half_width, c, inner=0):
        """Symmetric horizontal run about the x=31.5 centre line."""
        for d in range(inner, half_width):
            self.px(self.w // 2 - 1 - d, y, c)
            self.px(self.w // 2 + d, y, c)

    def ellipse(self, cy, rx, ry, c, y0=None, y1=None, inner_rx=0):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            if y0 is not None and y < y0:
                continue
            if y1 is not None and y > y1:
                continue
            t = (y - cy) / ry
            if abs(t) > 1.0:
                continue
            k = math.sqrt(1.0 - t * t)
            hw = int(round(rx * k))
            inner = int(round(inner_rx * k)) if inner_rx else 0
            if hw > 0:
                self.span(y, hw, c, inner)

    def rect(self, y0, y1, half_width, c, inner=0):
        for y in range(y0, y1 + 1):
            self.span(y, half_width, c, inner)

    def taper(self, y0, y1, hw0, hw1, c):
        """Body panel whose half-width eases from hw0 to hw1."""
        for y in range(y0, y1 + 1):
            t = (y - y0) / max(y1 - y0, 1)
            self.span(y, int(round(hw0 + (hw1 - hw0) * t)), c)

    def pair(self, x, y, c):
        """Place a pixel and its mirror. `x` is an offset from the centre."""
        self.px(self.w // 2 - 1 - x, y, c)
        self.px(self.w // 2 + x, y, c)

    def outline(self, c='#'):
        """One-pixel dark border around the whole silhouette."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] != '.':
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.g[ny][nx] not in ('.', c):
                        add.append((x, y))
                        break
        for x, y in add:
            self.g[y][x] = c


def build_64():
    c = Canvas(W64, H64)

    # ---- legs and boots (drawn first; the tunic overlaps them)
    for y in range(74, 95):
        c.span(y, 13, 'P', inner=2)
    for y in range(80, 95):                       # inner-thigh shadow
        c.span(y, 5, 'p', inner=2)
    for y in range(84, 88):                       # knee shading
        c.span(y, 12, 'p', inner=8)
    for y in range(87, 95):                       # boots
        c.span(y, 13, 'B', inner=2)
    for y in range(88, 91):                       # boot cuff highlight
        c.span(y, 12, 'b', inner=3)
    for y in range(93, 95):                       # sole
        c.span(y, 13, '#', inner=2)

    # ---- torso
    c.taper(45, 70, 17, 14, 'T')
    c.taper(48, 68, 8, 6, 'U')                    # lit chest panel
    c.rect(45, 47, 11, 't')                       # collar
    for y in range(48, 70):                       # flank folds
        c.span(y, 14, 't', inner=11)
    for y in range(62, 68):                       # fold under the ribs
        c.span(y, 11, 't', inner=9)

    # ---- belt
    c.rect(69, 73, 15, 'L')
    c.rect(72, 73, 15, 'l')
    c.rect(70, 73, 3, 'K')                        # buckle
    c.px(31, 71, 'l'); c.px(32, 71, 'l')

    # ---- arms
    for y in range(47, 70):
        t = (y - 47) / 23.0
        outer = int(round(22 - 2 * t))
        c.span(y, outer, 'A', inner=int(round(15 - t)))
    for y in range(63, 66):                       # cuffs
        c.span(y, 22, 't', inner=15)
    for y in range(66, 76):                       # hands
        c.span(y, 21, 'S', inner=15)
    for y in range(70, 76):                       # finger separations
        c.span(y, 20, '#', inner=19)
        c.span(y, 18, '#', inner=17)

    # ---- neck
    c.rect(40, 47, 7, 'S')
    c.rect(40, 43, 7, 's')                        # jaw shadow on the neck

    # ---- head
    c.ellipse(24, 15, 20, 'H', y0=2)              # hair mass
    c.ellipse(24, 15, 20, 'h', y0=2, inner_rx=13)  # hair rim shadow
    c.ellipse(20, 10, 11, 'G', y0=4)              # crown
    c.ellipse(17, 5, 6, 'g', y0=6)                # specular
    c.ellipse(28, 12, 16, 'S', y0=18)             # face
    c.ellipse(28, 12, 16, 's', y0=18, inner_rx=10)  # cheek shading
    c.ellipse(26, 8, 9, 'W', y0=20, y1=32)        # forehead light

    for y in range(18, 21):                       # fringe over the brow
        c.span(y, 13 - (y - 18), 'h')

    # ---- face detail
    for dx in range(3, 10):                       # brows
        c.pair(dx, 27, 'h')
        c.pair(dx, 28, 'h')
    for dx in range(3, 10):                       # eye whites
        for y in range(30, 34):
            c.pair(dx, y, 'W')
    for dx in range(4, 9):                        # eyes
        for y in range(30, 33):
            c.pair(dx, y, 'E')
    for dx in range(5, 8):                        # iris
        c.pair(dx, 31, 'e')
    for dx in range(0, 2):                        # nose
        c.pair(dx, 35, 's')
        c.pair(dx, 36, 's')
        c.pair(dx, 37, 'h')
    for dx in range(0, 4):                        # mouth
        c.pair(dx, 40, 'h')
    for dx in range(11, 13):                      # ears
        for y in range(29, 35):
            c.pair(dx, y, 'S')

    c.outline()
    return c.g


# --------------------------------------------------------------------------

def png(path, grid, w, h):
    def chunk(t, d):
        body = t + d
        return struct.pack('>I', len(d)) + body + struct.pack('>I', zlib.crc32(body))
    raw = b''.join(
        b'\x00' + bytes(v for x in range(w) for v in PAL[grid[y][x]])
        for y in range(h)
    )
    with open(path, 'wb') as handle:
        handle.write(b'\x89PNG\r\n\x1a\n'
                     + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9))
                     + chunk(b'IEND', b''))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sizes = [
        ("scale_demo_16x24.png", from_ascii(ROWS_16, 16, 24), 16, 24),
        ("scale_demo_32x48.png", from_ascii(ROWS_32, 32, 48), 32, 48),
        ("scale_demo_64x96.png", build_64(), W64, H64),
    ]
    for name, grid, w, h in sizes:
        png(os.path.join(OUT_DIR, name), grid, w, h)
        used = len({grid[y][x] for y in range(h) for x in range(w)} - {'.'})
        print(f"  {name}  {w}x{h}  {w * h} px  {used} colours")


if __name__ == "__main__":
    main()
