# Blightfall

Top-down action RPG in Godot 4.6. See [`docs/GDD.md`](docs/GDD.md) for the design
and [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md) for the schedule. Art conventions
live in [`docs/ART-PIPELINE.md`](docs/ART-PIPELINE.md). The village is described
in [`docs/AMBRY.md`](docs/AMBRY.md) and the valley outside it in
[`docs/ORCHARDFALL.md`](docs/ORCHARDFALL.md); everything not yet built is
inventoried in [`docs/WISHLIST.md`](docs/WISHLIST.md).

**Sprite standard: 64×96 characters, 64×64 tiles, 1280×720 internal**
(GDD §15, A1).

**Current milestone: M1 — combat prototype.** Grey boxes, one enemy, one room.
The only question it exists to answer is whether the combat is fun before any
art or story exists. See [`docs/M1-NOTES.md`](docs/M1-NOTES.md) for what is
built, what is deliberately missing, and what needs tuning by hand.

---

## Running it

Open the project in Godot 4.6+ and press F5. `ui/main_menu.tscn` is the main
scene — title, continue, new game. New Game lands you in Ambry, just inside the
south gate. It boots **fullscreen**; F11 toggles back to a window.

**The world and the UI are rendered separately.** The world draws into a fixed
1280×720 `SubViewport` with nearest filtering and is scaled up to fill the
window; the UI is laid out at the window's real resolution, so text rasterises
natively instead of being 720p type stretched. UI size is a setting in the Escape
menu, 1×–4× in half steps.

Walk **south out of the gate** and you are in Orchardfall — six connected areas
with a loop in them (`docs/ORCHARDFALL.md`). Outdoor edges are **walked into**:
follow a path off the screen and the same fade carries you to the next area. No
keypress — that is for doors, which are a choice. Edges are just the end of the
ground.

**Nothing out there fights back yet.** Ambry has no enemies by design (GDD §7 —
it is mechanically incapable of hurting you); Orchardfall has none because none
have been placed. For the combat prototype, open
`levels/prototype/prototype_room.tscn` and press **F6** to run just that scene.

Controls and debug keys are below.

### Open the editor after every pull

Godot imports changed files when it **opens the project in the editor**. The
`.godot/` cache is gitignored, so it is per-machine, and nothing else refreshes
it. In particular, hitting **Run from the Project Manager does not import** — it
launches the game against whatever the cache last held, so a `git pull` that
changed scripts or scenes appears to do nothing at all.

The symptoms are strange rather than obviously stale, because the game is
loading a coherent *old* project: a level that spawns the player at (0, 0)
outside the map, a character that will not move, a missing debug overlay, a
scene with no player in it. None of it looks like a caching problem.

So after pulling: **open the project in the editor and let the import progress
bar finish** before running. Or from a terminal:

```
godot --headless --path . --import
```

If it still misbehaves, delete `.godot/` and reopen the editor — running the
game with no cache at all creates a half-built one that then never rebuilds
itself.

**Don't put comments in `project.godot`.** The editor rewrites that file on
save, stripping comments and dropping any setting left at its default. It is
kept here in exactly the form Godot writes, so opening the project produces no
diff. What those settings do is explained in
[`docs/M1-NOTES.md`](docs/M1-NOTES.md#project-settings).

```
# headless self-check — 229 assertions over the M1 systems and Ambry
godot --headless --path . tests/m1_smoke_test.tscn

# opens a door with the interact key and comes back out, carrying materials
godot --headless --path . tests/doorway_test.tscn

# starts a new game from the title screen, walks out of town and back
godot --headless --path . tests/gateway_test.tscn

# walks up to the carpenter and has a branching conversation with him
godot --headless --path . tests/dialogue_test.tscn

# dies, with and without a save on disk, and checks the haul is still on the floor
godot --headless --path . tests/death_test.tscn

# colour discipline: profile every group, enforce the reserved blight accent
python3 tools/check_colour.py

# regenerate the greybox tileset, then rebuild the village and the valley
python3 tools/gen_greybox_tileset.py
godot --headless --path . --script res://tools/build_greybox.gd
godot --headless --path . --script res://tools/build_orchardfall.gd

# look at a level's whole layout rather than playing it
godot --path . tests/screenshot.tscn -- --scene=res://levels/ambry/ambry_level.tscn --shot=/tmp/plan.png --fit

# draw the UI font at a dozen sizes, for judging whether text is crisp
godot --path . tests/font_sheet.tscn -- --shot=/tmp/font.png

# capture a frame (needs a display; xvfb-run works)
godot --path . tests/screenshot.tscn -- --shot=/tmp/frame.png --near --boxes --attack=6
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrows | left stick |
| Attack | J | X |
| Dash / dodge | Shift or Space | A |
| Sprint | hold Shift while moving | hold A |
| Interact | E | B |
| Use selected item | K | Y |
| Pause menu | Escape | Start |
| Character menu | Tab | Select |
| Character / Inventory / Map | C / I / M | — |
| Hotbar select | 1–9, 0 or mouse wheel | — |

`interact` opens doors and talks to people. It is the general verb —
`world/interactable.gd` is the base class building, resting and the chest will
also use. In a conversation it advances the line, completes a line that is still
arriving, and picks a reply; **W/S** move between replies.

`tool` is what uses the selected hotbar slot. GDD §5 calls it
"context-dependent", and the hotbar is the context. Numbers and the wheel only
*select* — skimming the bar must never eat anything on the way past.

## Debug keys

BUILD-PLAN week 1, rule 2: the overlay goes in first and never comes out. It
shows state name, stamina, i-frames, active hitbox and combo index at all times,
because none of those are things you can see by squinting at a 0.10s window.

| Key | | Where |
|---|---|---|
| F1 | toggle the overlay | everywhere |
| F2 | draw hitboxes (red) and hurtboxes (blue, yellow while invulnerable) | everywhere |
| F3 | slow motion — how you read frame data with your eyes | everywhere |
| F11 | fullscreen / windowed | everywhere |
| F4 | spawn another enemy | prototype room only |
| F5 | reset the room | prototype room only |
| F6 / F7 | save / load slot 1 | prototype room only |

F1–F3 live in the `DebugSettings` autoload, so they work in any scene. **F4–F7
are handled by `prototype_room.gd` and do nothing anywhere else** — including
Ambry, where they are silent rather than broken. They belong to the combat test
bed; F4 has nothing to spawn in a village with no enemies, and F5/F6/F7 want a
real rest point rather than a debug key.

## Layout

```
actors/
  player/          player.gd + one script per state
  enemies/         base_enemy.gd, shared states, blighted_villager/
  components/      Health, Stamina, Knockback, Flash, Hitbox, Hurtbox, Input
systems/
  state_machine/   generic FSM — the player and every enemy use the same one
  targeting/       the single answer to "who do I attack?"
  save/            JSON save/load; nodes opt in via the `saveable` group
resources/
  combat/          the player's combo, as a tunable .tres
  enemy_data/      one .tres per enemy
autoloads/         Events, Rng, HitStop, Sfx, DebugSettings, SaveGame,
                   ScreenFade, Transition, Items, Hud
levels/
  level.gd         composes a map with a player and a camera
  ambry/           the village, greyboxed — map + level scene
  orchardfall/     the valley: six areas, one interior
  prototype/       the hand-placed box room (combat test bed)
camera/            the camera rig, which is not a child of the player
art/               shaders, fonts, sprites, tilesets, icons
resources/
  dialogue/        one JSON conversation per character
world/             pickups, the haul cache, interactables, doorways, gateways,
                   npcs
ui/                main menu, world viewport, HUD, dialogue box, stamina
                   wheel, menus, ui scale, type scale, debug overlay
tests/             headless smoke test + screenshot tool
tools/             SFX + tileset generators, colour checker, map builders
```

## Standing rules

Carried from GDD §12 / BUILD-PLAN. Cheap now, rewrite-expensive later — and all
of them are good practice regardless of whether co-op ever happens.

1. **Never make the player a singleton.** No `Player` autoload, no
   `Global.player`. Systems are handed a reference.
2. **No `get_first_node_in_group("player")` in enemy code.** Enemies ask
   `Targeting` for their nearest valid target.
3. **Input goes through `InputComponent`.** The player script never calls
   `Input.is_action_pressed()`.
4. **The camera rig is separate from the player.**
5. **All combat randomness goes through `Rng`,** the one seeded generator.
6. **Every tunable number is `@export`ed.**
7. **Commit at the end of every session, even broken. Tag every milestone.**
