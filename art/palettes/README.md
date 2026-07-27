# Palettes

**There is no global palette** (GDD §15 A5). This folder holds *per-location*
working palettes — a set of colours you choose for a zone and then stay inside,
so four zones and a hub don't drift into the same brown over eighteen months.

Nothing enforces these. They are a working aid, not a gate.

## What to put here

One `.gpl` (GIMP palette — Pixelorama imports it directly) per location:

```
art/palettes/ambry.gpl          warm — amber, ochre, cream, ember
art/palettes/orchardfall.gpl    that warmth sickened — yellow-green, grey-brown
art/palettes/stillwater.gpl     cold — blue-grey, teal, black water
art/palettes/hollowdeep.gpl     near-monochrome, tightly narrowed
```

Build them however you like — sample from a piece of finished art, pull one off
lospec.com, or mix your own. The only requirement is that they read as different
places.

## The one rule that is enforced

> Corruption is the one saturated colour. The blight is the only thing that glows.

**Hue 60–100° above 55% saturation is reserved.** `tools/check_colour.py` fails
on any world asset that claims it. Small highlights are tolerated; a glow is not.

That reservation is the antagonist's whole screen presence — it never speaks and
never appears as a figure. Everything else in the colour space is yours.

## Checking

```
python3 tools/check_colour.py                        # profile + enforce
python3 tools/check_colour.py --map /tmp/colour.png  # hue vs saturation, per group
```
