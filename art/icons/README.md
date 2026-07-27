# Icons

Drop them in. `items/` for anything that appears in an inventory or a tooltip,
`ui/` for HUD furniture.

## Sizes

| Folder | Canvas | For |
|---|---|---|
| `items/` | **64×64** | Materials, tools, upgrades, key items — anything with a name |
| `ui/` | **32×32** | Hearts, stamina pips, button prompts, cursors |

64 matches the tile size and the enemy body size, so an item icon and the thing
it represents in the world are the same size. It's also comfortable in a grid:
at 1280×720 a 6×4 inventory of 64px icons with padding is about 500×350, which
is a panel rather than a postage stamp.

32 is for things that repeat. Six hearts at 32px is 192px of HUD; at 64px it's
384px and starts eating the screen.

## Rules

- **Transparent background.** Not a coloured square — the UI draws its own
  frames, and a baked background can't be reskinned later.
- **Leave 2–4px of margin.** Nothing should touch the canvas edge, or icons look
  cramped when a selection border is drawn around them.
- **Draw at 1:1.** 64×64 canvas, zoom in to work. Never draw large and downscale.
- **Avoid the reserved accent.** Hue 60–100° above 55% saturation belongs to
  the blight. Otherwise the colour space is yours (GDD §15 A5).
- **One subject, centred.** An icon is read in under a second; it has a
  silhouette and one accent, same as an enemy.

## Naming

Flat files, category prefix, snake case — the prefix is what makes the folder
sort into something readable once there are forty of them.

`items/` is sorted into role subfolders, so the working set stays obvious as it
grows:

```
art/icons/items/materials/     rebuild currency — ore, stone, gems
art/icons/items/consumables/   food and supplies
art/icons/items/keys/          key items
art/icons/items/parked/        drawn, but for systems the game doesn't have

art/icons/ui/                  hearts, pips, prompts
```

`parked/` is not a bin. It is art that is good and currently unused — equipment
and archery icons against a design with one weapon and no bow. If those systems
ever exist, the icons are already there.

## Checking your work

```
python3 tools/check_colour.py
```

Profiles `art/icons/` along with sprites and tilesets. Icons are exempt from the
saturation guidance — they sit in a UI panel, not in the world — but the blight
accent is reserved everywhere, so an icon that glows yellow-green fails.

```
godot --path . tests/screenshot.tscn -- --scene=res://tests/icon_sheet.tscn --shot=/tmp/icons.png
```

Contact sheet of everything in these folders at true scale and at 3×, with sizes
flagged if they don't match the table above. Or open `tests/icon_sheet.tscn` in
the editor and press F6.
