# Blightfall

Top-down action RPG in Godot 4.6. See [`docs/GDD.md`](docs/GDD.md) for the design
and [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md) for the schedule. Art conventions
live in [`docs/ART-PIPELINE.md`](docs/ART-PIPELINE.md).

**Sprite standard: 64×96 characters, 64×64 tiles, 1280×720 internal**
(GDD §15, A1).

**Current milestone: M1 — combat prototype.** Grey boxes, one enemy, one room.
The only question it exists to answer is whether the combat is fun before any
art or story exists. See [`docs/M1-NOTES.md`](docs/M1-NOTES.md) for what is
built, what is deliberately missing, and what needs tuning by hand.

---

## Running it

Open the project in Godot 4.6+ and press F5. `levels/ambry/ambry_level.tscn` is
the main scene — the village, with the wall to the north and the gate south.
It boots **fullscreen**; F11 toggles back to a window.

**Ambry has no enemies**, by design: it is mechanically incapable of hurting you
(GDD §7). For the combat prototype, open
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
# headless self-check — 189 assertions over the M1 systems and Ambry
godot --headless --path . tests/m1_smoke_test.tscn

# opens a door with the interact key and comes back out, carrying materials
godot --headless --path . tests/doorway_test.tscn

# dies, with and without a save on disk, and checks the haul is still on the floor
godot --headless --path . tests/death_test.tscn

# colour discipline: profile every group, enforce the reserved blight accent
python3 tools/check_colour.py

# regenerate the greybox tileset and rebuild the village
python3 tools/gen_greybox_tileset.py
godot --headless --path . --script res://tools/build_greybox.gd

# look at a level's whole layout rather than playing it
godot --path . tests/screenshot.tscn -- --scene=res://levels/ambry/ambry_level.tscn --shot=/tmp/plan.png --fit

# capture a frame (needs a display; xvfb-run works)
godot --path . tests/screenshot.tscn -- --shot=/tmp/frame.png --near --boxes --attack=6
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrows | left stick |
| Attack | J | X |
| Dash / dodge | Shift or Space | A |
| Interact | E | B |
| Use selected item | K | Y |
| Pause menu | Escape | Start |
| Character menu | Tab | Select |
| Hotbar select | 1–9, 0 or mouse wheel | — |

`interact` opens doors. It is the general verb — `world/interactable.gd` is the
base class talking, building, resting and the chest will all use — but doors are
its only user so far.

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
  prototype/       the hand-placed box room (combat test bed)
camera/            the camera rig, which is not a child of the player
art/               shaders, fonts, sprites, tilesets, icons
world/             pickups, the haul cache, interactables and doorways
ui/                HUD, stamina wheel, pause + character menus, debug overlay
tests/             headless smoke test + screenshot tool
tools/             SFX + tileset generators, colour checker, greybox builder
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
