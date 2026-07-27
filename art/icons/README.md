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
- **Stay on palette.** Same 64 colours as everything else.
- **One subject, centred.** An icon is read in under a second; it has a
  silhouette and one accent, same as an enemy.

## Naming

Flat files, category prefix, snake case — the prefix is what makes the folder
sort into something readable once there are forty of them.

```
art/icons/items/material_timber.png
art/icons/items/material_stone.png
art/icons/items/tool_wardens_hook.png
art/icons/items/upgrade_heart_shard.png
art/icons/items/key_magistrates_seal.png

art/icons/ui/heart_full.png
art/icons/ui/heart_empty.png
art/icons/ui/stamina_pip.png
```

Prefixes in use: `material_`, `tool_`, `upgrade_`, `key_`, `consumable_`.

## Checking your work

```
python3 tools/check_palette.py
```

Scans `art/icons/` along with sprites and tilesets, and fails on any colour
outside the committed palette — reporting the nearest entry and a delta, so a
filter that shifted one tone by 1 shows up as plainly as a stray magenta.

```
godot --path . tests/screenshot.tscn -- --scene=res://tests/icon_sheet.tscn --shot=/tmp/icons.png
```

Contact sheet of everything in these folders at true scale and at 3×, with sizes
flagged if they don't match the table above. Or open `tests/icon_sheet.tscn` in
the editor and press F6.
