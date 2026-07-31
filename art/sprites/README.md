# Sprites

Where drawn things go, and what they have to be named for the code to find
them. Nothing here is style guidance — that is GDD §8.

## Actors (player, enemies, NPCs)

```
art/sprites/<actor>/<actor>_<clip>_<direction>.png
```

**clip** — `idle`, `walk`, `attack_1`, `attack_2`, `attack_3`, `dodge`, `hurt`,
`death`. Frame budget per GDD §8: idle 2, walk 4, attack 3, dodge 4, hurt 1,
death 5. Enemies need no `dodge`; anything with one attack needs no
`attack_2`/`attack_3`.

**direction** — one of eight, though almost nothing needs all eight:

| slot | facing | needed when |
|---|---|---|
| `down` | south | always — everything falls back to it |
| `up` | north | always in practice |
| `side` | east | always in practice |
| `down_side` | south-east | you want true 8-way movement |
| `up_side` | north-east | " |
| `side_west` | west | **the actor is asymmetric** — see below |
| `down_side_west` | south-west | " |
| `up_side_west` | north-west | " |

**Three, five, or eight are all valid sets.** With three, west is drawn by
mirroring east and the diagonals resolve to the nearest drawn strip. With five,
movement is true 8-way and the western half is still mirrored. With eight,
nothing is mirrored.

**Draw all eight for anything carrying something on one side** — a scabbard, a
satchel, a bandaged arm. Mirroring swaps it to the other hip as the character
turns around, which reads as a glitch rather than as a missing file. The player
carries a sword, so the player is an eight-strip actor. A wolf is symmetrical,
so five is enough for it.

### Strips, not sheets

One **horizontal row** per direction. Frame width is the texture width divided
by the frame count, and by convention frames are square (128×128 for the player,
96×96 for the forest wolf), so a 4-frame walk is 384×96.

### The anchor

The feet sit on the node origin: `AnimationComponent` offsets the sprite up by
`body_height / 2`. So within the frame, the feet must be at

```
y = frame_height / 2 + body_height / 2
```

The player: 128px frames, `body_height = 96` → feet at y=112.
The forest wolf: 96px frames, `body_size.y = 48` → paws at y=72.

Get this wrong and the actor sinks into or floats above the ground, and
y-sorting puts them behind things they are standing in front of.

### Getting there from a Pixellab export

Unzip it somewhere and run two commands:

```bash
python3 tools/import_pixellab.py ~/Downloads/wolf --actor forest_wolf --frame 128 --dry-run
python3 tools/import_pixellab.py ~/Downloads/wolf --actor forest_wolf --frame 128
python3 tools/build_animation_set.py forest_wolf
```

`import_pixellab.py` reads `metadata.json`, re-canvases every frame onto the
frame size you pick, and anchors the feet — **nothing is rescaled**, the exports
are already 1:1 and resampling would destroy the grid.

Two things about the crop are worth knowing, because they are why you can
re-import later without breaking what is already in:

- **Pixellab pads the canvas on purpose**, so animations have room to swing past
  the idle silhouette. Choose `--frame` with headroom (128 for a human-sized
  actor) rather than cropping tight.
- The window is anchored to the **canvas centre** horizontally and the **feet of
  the idle rotations** vertically. Both hold as clips are added, so a walk cycle
  exported next month lines up with the idle exported today.

Pass `--body` to declare the `body_height` you want on the AnimationComponent;
the feet are anchored to satisfy it exactly, so the number in the scene and the
pixels in the file cannot drift apart. Without it, the measured height is used
and printed.

A clip that is animated in only one direction is padded: the other seven hold
their standing pose for the same number of frames, so `frames` stays one number
per clip. You get motion where you are looking and nothing breaks.

`tools/pack_strips.py` is the other route in — loose frames that are already the
right size, with the direction in the filename (`south`, `se`, `north-west`, …)
and the order in a trailing number.

`build_animation_set.py` reads whatever strips exist and writes
`resources/animation/<actor>.tres`. Re-run it after adding a direction; the file
is generated, not hand-edited.

Import every sprite with **filter off and mipmaps off**, or the pixel grid goes
soft. Then `python3 tools/check_colour.py` before committing.

## Props (trees, bushes, barrels, statues)

```
art/sprites/props/<name>.png
```

One image, no strips, no directions. Dropped into the world through
`world/prop.tscn`, whose `footprint` is the *blocking* rectangle — the trunk,
not the canopy. **The base of the picture is the origin**, so a tree's roots
should sit at the bottom edge of its canvas; use `art_offset` for art that
doesn't.

A shrine (`world/shrine.tscn`) takes two: `<name>_dormant.png` and
`<name>_lit.png`.

**Author a prop at the size it is drawn at.** `Prop.art_scale` snaps to whole
numbers, so a canvas only ever has integer multiples of itself available — 96px
art can be 96, 192 or 288 and nothing in between, and a tile is 64. Art whose
native size is not on the ladder either sits at the wrong scale or gets a
non-integer zoom that breaks the pixel grid. The ladder in use:

| what | canvas | drawn at | why |
| --- | --- | --- | --- |
| undergrowth | 64 | 64 (1 tile) | below the knee; the player is 96 |
| trees | 128 | 256 (4 tiles) | 256 art would be better, see `build_orchardfall.gd` |

`tools/gen_shrubs.py` draws the four bushes, and its docstring is the long
version of why they are 64 and not 96.

## Icons

```
art/icons/items/<consumables|gear|keys|materials>/<name>.png
```

UI surface, not world art — exempt from the saturation advisory in
`check_colour.py`, because a bright gemstone in an inventory slot is not
competing with anything for the player's eye.

## Tiles

```
art/source/tiles/<sheet>.png   what arrived, untouched
art/tiles/<greybox name>.png   a 64x64 override
```

A file in `art/tiles/` named for a greybox tile replaces that tile's flat colour
in the atlas — `tools/gen_greybox_tileset.py` looks for one before it draws.

**The atlas is the seam, not a new layer.** Ground art went in as a TileMapLayer
over the greybox because terrain has its own tileset and its own blend tiles. A
wall has neither: it is one tile, in one cell, that stops you. Swapping the
picture inside the atlas keeps the same tile in the same cell with the same
collision polygon, so every assertion in `build_greybox.gd` still measures what
it measured and y-sorting never enters into it.

`tools/import_stone_tiles.py` cuts the current set out of its source sheet.

## UI plates and frames

```
art/source/ui/<set>/    what arrived, untouched
art/ui/<name>.png       what the game uses
```

Imported through `tools/import_ui_borders.py` rather than dropped straight in,
because a bought UI set arrives in somebody else's palette — the first one was
214 degrees of hue away from this game's. The tool rotates it onto one warm hue,
caps saturation so the gems stop shouting, and strips decoration that cannot
tile. Its docstring is the long version.

The source stays in the repo so the numbers can be changed later. Nothing edits
`art/ui/` by hand.
