# Blightfall

Top-down action RPG in Godot 4.6. See [`docs/GDD.md`](docs/GDD.md) for the design
and [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md) for the schedule.

**Current milestone: M1 — combat prototype.** Grey boxes, one enemy, one room.
The only question it exists to answer is whether the combat is fun before any
art or story exists. See [`docs/M1-NOTES.md`](docs/M1-NOTES.md) for what is
built, what is deliberately missing, and what needs tuning by hand.

---

## Running it

Open the project in Godot 4.6+ and press F5. `levels/prototype/prototype_room.tscn`
is the main scene.

```
# headless self-check — 69 assertions over the M1 systems
godot --headless --path . tests/m1_smoke_test.tscn

# capture a frame (needs a display; xvfb-run works)
godot --path . tests/screenshot.tscn -- --shot=/tmp/frame.png --near --boxes --attack=6
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrows | left stick |
| Attack | J | X |
| Dodge | Space | A |
| Tool | K | Y |

`tool` is mapped but not wired to anything — M1 has no tools, not even the
Cinderflask (BUILD-PLAN). The action exists so the input map is complete on day
one rather than being edited during M3.

## Debug keys

BUILD-PLAN week 1, rule 2: the overlay goes in first and never comes out. It
shows state name, stamina, i-frames, active hitbox and combo index at all times,
because none of those are things you can see by squinting at a 0.10s window.

| Key | |
|---|---|
| F1 | toggle the overlay |
| F2 | draw hitboxes (red) and hurtboxes (blue, yellow while invulnerable) |
| F3 | slow motion — how you read frame data with your eyes |
| F4 | spawn another enemy |
| F5 | reset the room |

## Layout

```
actors/
  player/          player.gd + one script per state
  enemies/         base_enemy.gd, shared states, blighted_villager/
  components/      Health, Stamina, Knockback, Flash, Hitbox, Hurtbox, Input
systems/
  state_machine/   generic FSM — the player and every enemy use the same one
  targeting/       the single answer to "who do I attack?"
resources/
  combat/          the player's combo, as a tunable .tres
  enemy_data/      one .tres per enemy
autoloads/         Events, Rng, HitStop, Sfx, DebugSettings
levels/prototype/  the one hand-placed box room
camera/            the camera rig, which is not a child of the player
ui/                debug overlay
tests/             headless smoke test + screenshot tool
tools/             placeholder SFX generator
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
