# Palettes

**Target: 64 colours, fixed, pre-made.** (GDD §8, as amended by §15 A2.)

Nothing is committed here yet. Download the palette and drop it in this
directory — the whole art pipeline keys off it.

## What to get

[Endesga 64](https://lospec.com/palette-list/endesga-64) is the natural pick:
same author as the Endesga 32 the GDD originally named, designed as ramps rather
than as 64 unrelated swatches, which is what makes shared ramps practical.

Download it as **`.gpl`** (GIMP palette). Pixelorama imports that format
directly, and `tools/check_palette.py` reads it. `.hex` also works.

Save it here as `endesga-64.gpl`, then commit it. Every machine and every future
you needs the identical 64 values — a palette that drifts between machines is
worse than no palette.

## Then

```
python3 tools/check_palette.py --list     # confirm it parsed, see the colours
python3 tools/check_palette.py            # verify every sprite is on-palette
```

Run the second one before committing art. It catches the failure mode that
matters: a filter, a resize, a gradient or a paste introducing a handful of
near-miss pixels that look fine on their own sprite but dilute the visual
language across forty of them. It reports the nearest palette entry and a delta,
so a delta of 1 reads as "a tool nudged this" and a delta of 130 reads as "this
colour does not belong in the game."

## Zone slices

Zone identity comes from slices of the same 64 — roughly 20 colours each:

| Zone | Slice |
|---|---|
| Ambry | warm — amber, ochre, cream, ember. The only warm location in the game |
| Orchardfall | that same warmth sickened — yellow-green, grey-brown |
| Stillwater | cold — blue-grey, teal, black water |
| Hollowdeep | near-monochrome, tightly narrowed |

Consider saving each slice as its own Pixelorama palette, so a zone's tileset
can't accidentally borrow a colour from another zone's and blur the transition
the player is supposed to feel when they walk into it.

## The rule 64 colours does not relax

> **Corruption is the one saturated colour.** Everything else muted — greys,
> browns, sick greens. The blight is the only thing that glows. (GDD §8)

Doubling the palette doubles the rope. Endesga 64 contains plenty of saturated
colours; most of them must stay unused, or be used only at low coverage, or the
luminous yellow-green blight accent stops being the thing your eye goes to. The
extra 32 colours are for **more tones per material**, not for more hues.
