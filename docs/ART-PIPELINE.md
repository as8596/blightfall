# Art pipeline — Pixelorama → Godot

Conventions for getting pixels out of Pixelorama and into the game. Sizes and
frame counts come from GDD §8; everything else here is a decision made once so
it doesn't get made differently on a Tuesday six months from now.

**Timing:** M1 contains no art by design — the milestone gate is "is this fun"
with grey boxes. Art production starts at M2, in the order GDD §8 gives:

1. Player sprite, all animations
2. One enemy (Blighted Villager) — proves the pipeline end to end
3. Zone 1 tileset (~40 tiles)
4. UI
5. Everything else
6. Intro-specific assets **last**

Step 2 is the load-bearing one. Take one enemy all the way from Pixelorama to
running in the game before drawing a second, so that pipeline problems cost one
sprite instead of ten.

---

## Step zero: lock the palette

Before drawing anything. GDD §8: *"fixed, pre-made, from lospec.com. Do not
design your own — it's a week you don't have."*

**Size is an open decision (GDD §15, A2).** 32 colours was chosen when a
character had 8 of them. The 64×96 reference uses 21 on its own, which would
leave 11 for every environment, every other character and every effect. Either
take a larger pre-made palette (Endesga 64 or similar), or keep 32 and commit to
heavily shared ramps — skin and wood off the same warm browns, foliage and cloth
off the same greens. Shared ramps are what good pixel art does anyway, but they
do limit how distinct two characters can look, which is the reason the
resolution went up in the first place.

**Settle this before drawing the player.** Repalletting finished art is the
expensive kind of rework.

1. Download the chosen palette from [lospec.com](https://lospec.com/palette-list)
   as `.gpl` (GIMP palette — Pixelorama imports it directly).
2. Commit it to `art/palettes/` so every machine and every future you uses the
   identical values.
3. Import it into Pixelorama and work from it exclusively.

**If anything generates pixels rather than you drawing them** — Pixelorama's 3D
layers, a filter, an imported reference, a gradient — quantise it back to the
palette before it lands in the repo. Off-palette colours don't announce
themselves; they just quietly break the readability rule that the whole art
direction rests on:

> **Corruption is the one saturated colour.** Everything else muted — greys,
> browns, sick greens. The blight is the only thing that glows. (GDD §8)

That rule only holds if nothing else in frame is saturated. One stray
generated highlight competing with the blight accent costs you the visual
language, and it is very hard to spot one asset at a time.

Zone identity comes from **slices** of the same palette — Ambry warm,
Orchardfall that warmth sickened, Stillwater cold, Hollowdeep near-monochrome —
with the luminous yellow-green blight accent constant across all four. Consider
saving each slice as its own Pixelorama palette so a zone's tileset can't
accidentally borrow a colour from another zone's.

---

## Sizes

| Asset | Canvas |
|---|---|
| Tile | 64×64 |
| Player | 64×96 |
| Enemies | 64×64 to 128×128 |
| Bosses | up to 256×256 |

Internal resolution is 1280×720 (GDD §15, A1). A 64×96 character is 13% of the
screen height and exactly one tile wide.

At this size a sprite has ~6100 pixels, which is enough for a full ramp per
material — shadow, base, highlight, specular — plus an iris, cloth folds and
separated fingers. `art/sprites/scale_demo_64x96.png` is a reference of roughly
what fits; `tests/size_comparison.tscn` shows it against the two sizes it
replaced.

**Watch the colour count.** That reference uses 21 colours on its own. Whatever
palette size is settled on (GDD §15, A2), plan on sharing ramps between
materials rather than giving each one its own.

## Animation budget

Straight from GDD §8. Treat it as a ceiling, not a target:

| Animation | Frames |
|---|---|
| Idle | 2 |
| Walk | 4, ×4 directions |
| Attack | 3 per combo hit |
| Dodge | 4 |
| Hurt | 1 |
| Death | 5 |

**Treat this as a hard ceiling now, not a target.** It was set when a frame was
384 pixels; a frame is now 6144. Roughly 30 frames for the player alone is a
different proposition at 64×96, and the honest mitigation is fewer frames drawn
well rather than the same count drawn hastily.

**Left is a horizontal flip of right.** Draw three directions, not four. Half
the walk-cycle work for a difference nobody notices top-down.

---

## The one that will bite you: animation is slaved to frame data

The combo's timings are not negotiable and not evenly spaced (GDD §5):

| Hit | Windup | Active | Recovery |
|---|---|---|---|
| 1 | 0.08 | 0.10 | 0.16 |
| 2 | 0.07 | 0.10 | 0.18 |
| 3 | 0.14 | 0.12 | 0.32 |

Three frames per hit, three phases per hit. That is not a coincidence — draw
**one frame per phase**: wind-up pose, strike, recovery.

Do **not** give the attack animation a fixed FPS and let it run. A 3-frame
animation at 12fps takes 0.25s while hit 1 takes 0.34s, so the sprite finishes
its swing before the hitbox does, and then the game is lying to the player about
when they are about to be hit. Pillar 1 is *"every death is the player's fault
and they know it"* — that requires the picture and the hitbox agreeing.

So: **`PlayerAttackState` already tracks `_t` against the phase boundaries.**
When sprites land, it sets the sprite's `frame` from which phase it is in. The
animation has no clock of its own.

Idle, walk and death are free-running and can use a normal looping
`AnimatedSprite2D` with an FPS — nothing hangs off their timing.

---

## Export convention

**One horizontal strip per animation**, no padding, no trim:

```
art/sprites/player/player_idle_down.png      2 frames  →  128×96
art/sprites/player/player_walk_down.png      4 frames  →  256×96
art/sprites/player/player_attack_1_down.png  3 frames  →  192×96
art/sprites/enemies/villager_walk_down.png   4 frames  →  256×64
```

Strips rather than one big sheet per actor: re-exporting a single animation
rewrites a single small file, so git diffs stay readable and a bad export can't
clobber six good animations. Slice in Godot with `hframes` — no atlas region
maths, no offsets to keep in sync.

Turn **off** any "trim empty space" option on export. Trimming makes each frame
a different size and shifts the sprite's origin per frame, which produces a
character that jitters as it animates.

**Tilesets** export as one PNG grid, 64×64 cells, **no padding between tiles.**
Padding exists to stop bleed under linear filtering; this project filters
Nearest and has no bleed to stop. Use Pixelorama's tile mode while drawing so
edges are seamless by construction.

---

## Godot import

Already handled project-wide — `[importer_defaults]` in `project.godot` sets
lossless compression, no mipmaps, `fix_alpha_border` off and `detect_3d`
disabled, so you should never need to touch a texture's Import tab.

Two of those are worth knowing about because they are the classic ways a
pixel-art project goes quietly blurry:

- **`fix_alpha_border`** bleeds colour outward into transparent pixels. Harmless
  under linear filtering, but here it writes off-palette colours into the edge
  of every single sprite.
- **`detect_3d/compress_to`** silently switches a texture to VRAM compression
  the first time it's used in a 3D context. Disabled outright.

The project already sets Nearest filtering, pixel snapping for both transforms
and vertices, and a 1280×720 viewport (GDD §10, as amended by §15).

---

## Swapping a grey box for a sprite

Both actors currently draw themselves with a `ColorRect` named `Visual`. The
swap is small, and three things are already built to survive it:

- **`FlashComponent`** targets whatever `CanvasItem` sits at its `target_path`
  and builds its own `ShaderMaterial` at runtime. It works on a `Sprite2D` or
  `AnimatedSprite2D` with no changes.
- **Sprite origins are already at the feet**, and the level root is y-sorted, so
  depth sorting works the moment there is anything to sort.
- **The hit-flash shader** weights by alpha, so a transparent sprite flashes as
  a silhouette rather than a solid block.

Two places do need editing when the boxes go, both because they poke `ColorRect`
properties directly:

- `BaseEnemy._apply_data()` sets `visual.color`, the `offset_*` rect and
  `pivot_offset` from `EnemyData`. With a sprite, size comes from the texture;
  `body_size` stays useful for the collision shape and stops being layout.
- `EnemyTelegraphState` signals the wind-up by setting `visual.color` and
  `visual.scale`. With sprites that becomes a telegraph *animation* — but keep
  both channels. GDD §5 enemy rule 1 is "distinct colour **and** pose", and
  colour alone is invisible to some players while silhouette alone is invisible
  against a busy background.

Keep `EnemyData.telegraph_color` even after sprites exist, applied as
`modulate` — a tinted wind-up frame on top of a pose change is cheap and
readable at 320×180 in a way that either one alone is not.
