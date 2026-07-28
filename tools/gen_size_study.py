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

    # ---- asymmetric primitives, for the profile ---------------------------
    #
    # Everything above mirrors about the centre line, which is exactly right
    # for a character facing the camera and exactly wrong for one in profile:
    # a face seen side-on has a nose on one side and a bun of hair on the
    # other. These take a signed offset `d` from the centre line instead —
    # d = 0 is the first column right of centre, d = -1 the first column left.

    def at(self, d, y, c):
        self.px(self.w // 2 + d, y, c)

    def band(self, y, d0, d1, c):
        for d in range(d0, d1 + 1):
            self.at(d, y, c)

    def block(self, y0, y1, d0, d1, c):
        for y in range(y0, y1 + 1):
            self.band(y, d0, d1, c)

    def wedge(self, y0, y1, back0, front0, back1, front1, c):
        """A panel whose back and front edges each ease from y0 to y1."""
        for y in range(y0, y1 + 1):
            t = (y - y0) / max(y1 - y0, 1)
            self.band(y,
                      int(round(back0 + (back1 - back0) * t)),
                      int(round(front0 + (front1 - front0) * t)), c)

    def blob(self, dc, cy, rx, ry, c, y0=None, y1=None,
             d_max=None, d_min=None, inner_rx=0):
        """An ellipse centred off the axis, optionally cut off in x.

        `d_max` is what lets hair sit over the back of a skull without
        swallowing the face in front of it.
        """
        for y in range(int(cy - ry), int(cy + ry) + 1):
            if (y0 is not None and y < y0) or (y1 is not None and y > y1):
                continue
            t = (y - cy) / ry
            if abs(t) > 1.0:
                continue
            k = math.sqrt(1.0 - t * t)
            hw = int(round(rx * k))
            hole = int(round(inner_rx * k)) if inner_rx else 0
            for d in range(dc - hw, dc + hw + 1):
                if hole and abs(d - dc) < hole:
                    continue
                if d_max is not None and d > d_max:
                    continue
                if d_min is not None and d < d_min:
                    continue
                self.at(d, y, c)

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


def _facing_body(c):
    """Legs, torso, belt, arms and neck — everything symmetric about the axis.

    Shared by the front and back views because from either side the body reads
    the same. The vertical landmarks — collar 45, belt 69, knee 84, sole 95 —
    are the contract: they are the same in all three views, so a walk offset or
    an attack lunge authored against one direction is right in every direction.
    """
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
    c.rect(45, 47, 11, 't')                       # collar
    for y in range(48, 70):                       # flank folds
        c.span(y, 14, 't', inner=11)
    for y in range(62, 68):                       # fold under the ribs
        c.span(y, 11, 't', inner=9)

    # ---- belt
    c.rect(69, 73, 15, 'L')
    c.rect(72, 73, 15, 'l')

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
    return c


def _skull(c):
    """The hair mass shared by the front and back views."""
    c.ellipse(24, 15, 20, 'H', y0=2)              # hair mass
    c.ellipse(24, 15, 20, 'h', y0=2, inner_rx=13)  # hair rim shadow
    c.ellipse(20, 10, 11, 'G', y0=4)              # crown
    c.ellipse(17, 5, 6, 'g', y0=6)                # specular
    return c


def build_64():
    """Facing the camera. South, and the view everything else is measured off."""
    c = _skull(_facing_body(Canvas(W64, H64)))

    c.taper(48, 68, 8, 6, 'U')                    # lit chest panel
    c.rect(70, 73, 3, 'K')                        # buckle
    c.px(31, 71, 'l'); c.px(32, 71, 'l')

    c.ellipse(28, 12, 16, 'S', y0=15)             # face
    c.ellipse(28, 12, 16, 's', y0=15, inner_rx=10)  # cheek shading
    c.ellipse(26, 8, 9, 'W', y0=18, y1=32)        # forehead light

    # The fringe stops well clear of the brow. Sitting on it — which it did —
    # reads as hair hanging in the eyes rather than as a hairline, and it costs
    # the face the one flat area that makes the features legible at this size.
    c.span(15, 13, 'h')
    c.span(16, 12, 'h')
    c.span(17, 10, 'h')

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


def build_64_up():
    """Walking away. North.

    The read has to survive being 64 pixels tall on a moving character, so it
    is carried by three things a player registers without looking: **no face**,
    hair continuing down past the jawline to the nape, and **no belt buckle**.
    Everything else is deliberately identical to the front view — a back that
    is a different character is worse than a back that is plain.
    """
    c = _skull(_facing_body(Canvas(W64, H64)))

    # Hair covers the whole skull and the nape. The front view's face ellipse
    # is replaced by the same shape in hair, one row shallower so a sliver of
    # neck shows beneath it.
    c.ellipse(27, 13, 15, 'H', y0=18, y1=38)
    c.ellipse(27, 13, 15, 'h', y0=30, y1=38)      # shadow where it falls
    c.ellipse(22, 9, 10, 'G', y0=18)              # crown light carries over

    for y in range(36, 39):                       # ragged hairline
        c.span(y, 10 - (y - 36) * 3, 'h')

    for dx in range(11, 14):                      # ears, seen edge-on
        for y in range(29, 35):
            c.pair(dx, y, 'S')
        c.pair(13, y, 's')

    # Shoulder blades catch the light; a single spine crease keeps the back
    # from reading as a flat board.
    c.taper(48, 62, 11, 8, 'U')
    c.taper(49, 68, 2, 1, 't')

    c.outline()
    return c.g


# Front edge of the hair at each row of the profile, as an offset from the
# centre line. Read by `build_64_side`; a table because a formula that produced
# this shape would be less readable than the shape itself.
# It drops almost straight from the crown to the brow — a forehead in profile
# is a near-vertical strip, and a hairline that slopes across it at 45 degrees
# is exactly what "hair hanging over the face" looks like. Only past the brow
# does it sweep back, to the temple and then behind the ear.
SIDE_HAIRLINE = {
    18: 9, 19: 9, 20: 9, 21: 9, 22: 8, 23: 8,
    24: 7, 25: 5, 26: 3, 27: 1,
    28: 0, 29: 0, 30: 0, 31: 0, 32: 0,
    33: -3, 34: -3, 35: -3, 36: -3, 37: -3, 38: -3, 39: -3,
}


def build_64_side():
    """In profile, facing right. East — and west is this flipped, which is why
    only one strip is drawn (`SpriteAnimation.side`).

    Nothing here can be mirrored: the nose is on one side and the back of the
    skull is on the other, so this is built from the asymmetric primitives and
    laid out on a signed offset from the centre line.

    It keeps the front view's vertical landmarks exactly — collar 45, belt 69,
    knee 84, sole 95 — so the shared per-frame offsets in
    `gen_placeholder_animations.py` land the same way in all three directions.
    """
    c = Canvas(W64, H64)

    # A profile loses both arms from the silhouette, so a torso as narrow as a
    # real one leaves the head looking enormous. Chest depth here is about
    # three-fifths of the front view's shoulder-to-shoulder, which is roughly
    # true of a person and reads as the same character rather than a thinner one.

    # ---- legs: one mass, with the far leg as a shadow behind it
    c.block(74, 94, -10, 8, 'P')
    c.block(74, 94, -10, -5, 'p')                 # far leg
    c.block(84, 88, -3, 6, 'p')                   # knee
    c.block(87, 94, -10, 12, 'B')                 # boot, toe forward
    c.block(88, 90, -8, 8, 'b')                   # cuff
    c.block(93, 94, -10, 12, '#')                 # sole

    # ---- torso: shoulders back a little, chest forward
    c.wedge(45, 70, -13, 12, -12, 11, 'T')
    c.block(45, 47, -11, 9, 't')                  # collar
    c.wedge(48, 68, -13, -9, -12, -8, 't')        # the back is the shadow side
    c.wedge(48, 66, 6, 12, 5, 11, 'U')            # and the chest the lit one

    # ---- belt, buckle at the front edge
    c.block(69, 73, -13, 12, 'L')
    c.block(72, 73, -13, 12, 'l')
    c.block(70, 73, 8, 12, 'K')

    # ---- the near arm, hanging just forward of the body
    c.wedge(47, 65, -6, 6, -5, 6, 'A')
    c.block(63, 65, -6, 6, 't')                   # cuff
    c.block(66, 74, -3, 7, 'S')                   # hand
    c.block(70, 74, 3, 3, '#')                    # one finger separation

    # ---- neck, set forward of the spine
    c.block(40, 47, -5, 6, 'S')
    c.block(40, 46, -5, -2, 's')

    # ---- head, in three passes, and the order is the whole trick.
    #
    # Face first. Then hair over it — right across above the hairline, nothing
    # below it. Then the features last, so nothing paints over them.
    #
    # The face sits further forward than the skull rather than concentric with
    # it. That is what leaves a forehead to see: a face centred on the same axis
    # as the hair has its front edge under the hair's, and the only skin left is
    # a sliver that widens into a wedge as it descends.
    c.blob(3, 28, 10, 16, 'S', y0=15)             # face
    c.blob(3, 28, 10, 16, 's', y0=15, d_max=-1)   # shaded toward the back
    # The face ellipse alone lets the jaw recede into nothing, so the chin is
    # built back on by hand and tapered rather than squared off.
    c.band(39, -4, 10, 'S')
    c.band(40, -4, 10, 'S')
    c.band(41, -3, 9, 'S')
    c.band(42, -2, 8, 'S')
    c.band(43, -1, 6, 's')
    c.blob(4, 26, 6, 9, 'W', y0=21, y1=32)        # cheekbone light

    # The nose is the single cheapest thing that says "profile", and it only
    # works if it breaks the silhouette.
    c.band(33, 13, 15, 's')
    c.band(34, 13, 16, 's')
    c.band(35, 12, 16, 's')
    c.band(36, 12, 15, 'h')                       # underside
    c.band(37, 11, 12, 's')
    c.band(40, 6, 9, 'h')                         # mouth

    # ---- hair, row by row along `SIDE_HAIRLINE`
    # Every hair pass is clipped to the hairline, the rim shadow included. It
    # was not, and a shadow drawn across the full ellipse lands on the forehead
    # and the cheek — which is most of what "hanging over the face" looked like.
    for y in range(4, 41):
        front = 99 if y <= 17 else SIDE_HAIRLINE[min(y, 39)]
        c.blob(-1, 22, 12, 18, 'H', y0=y, y1=y, d_max=front)
        c.blob(-1, 22, 12, 18, 'h', y0=y, y1=y, d_max=front, inner_rx=10)
        if y > 17:                                # a darker edge along the line
            c.at(front, y, 'h')
    c.blob(-2, 18, 8, 10, 'G', y0=5, y1=21)       # crown light
    c.blob(-4, 15, 4, 6, 'g', y0=7)               # specular

    # ---- one eye, one ear. Both are what sell a profile.
    c.block(30, 33, 4, 9, 'W')
    c.block(30, 32, 5, 8, 'E')
    c.at(6, 31, 'e'); c.at(7, 31, 'e')
    c.block(27, 28, 3, 12, 'h')                   # brow
    c.block(29, 35, -4, 0, 'S')                   # ear, in front of the hair
    c.block(31, 34, -3, -1, 's')
    c.block(29, 35, 1, 1, 'h')                    # crease, or it is just cheek

    c.outline()
    return c.g


BUILDERS_64 = {
    "down": build_64,
    "up": build_64_up,
    "side": build_64_side,
}


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
