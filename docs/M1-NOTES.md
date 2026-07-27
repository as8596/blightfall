# M1 notes

State of the combat prototype, what it deliberately doesn't contain, and the
things that need a human at the keyboard.

---

## What's built

Weeks 1–3 of the build plan, plus the week 4 tooling.

**Week 1 — movement.** Generic `StateMachine` (the player and every enemy share
it), `InputComponent` producing an intent struct, `Player` as a 16×24 rectangle
at 82 px/s reaching full speed in 0.08s, 8-directional, a hand-placed 480×320
box room, a camera rig that is not a child of the player, and the debug overlay.

**Week 2 — the verbs.** `Hitbox`/`Hurtbox` components, the three-hit combo with
the frame data from GDD §5 exported as a tunable `.tres`, the combo window,
dodge-cancel out of recovery, the 0.36s dodge with i-frames 0.04→0.24, dodge
stamina, and F2 box visualisation.

**Week 3 — one enemy, and feel.** `HealthComponent`, `KnockbackComponent`,
`EnemyData` as a Custom Resource, the Blighted Villager (approach → 0.4s
telegraph → committed lunge → long vulnerable recovery), hitstop, shader-based
hit flash, distance-based knockback, pixel-snapped screen shake, and eight
placeholder SFX layered as swing + impact with ±10% pitch randomisation.

**Week 4 — the tools for deciding.** F4 spawns another enemy mid-fight, F5 soft
resets, F3 slow motion, and cheap separation steering so a pack reads as three
bodies rather than one stack.

## What's deliberately missing

Everything on the BUILD-PLAN "not in M1" list: no art, no tilemaps, no menus, no
save, no dialogue or NPCs, no XP, no tools (not even the Cinderflask), no second
enemy type, no music.

Two things from the GDD that also aren't here, on purpose:

- **`UsingTool` and `Cutscene` player states.** GDD §10 lists both. M1 has
  neither tools nor cutscenes, and an empty state is a place for bugs to hide.
  Add `Cutscene` at M2 when the intro placeholder cards need it — the state
  machine is built for it.
- **Y-sorting.** The level root has `y_sort_enabled` set and sprite origins are
  already at the feet, so the setup is right, but with one enemy and no props
  there is nothing yet to sort.

## Verification

`godot --headless --path . tests/m1_smoke_test.tscn` — 143 assertions, currently
all passing. It checks project configuration (viewport, stretch, snapping,
all eight physics layer names, every input action), measured frame data
(hitbox on at windup, active window length, hit durations, dodge duration and
distance, i-frame boundaries), the combo window outliving its state, chaining
and buffering, stamina rules, the damage exchange end to end, the enemy's full
behaviour loop, save/load, the haul, Ambry's twenty locations and ten NPCs, and
the design rules that live in `.tres` files.

`godot --headless --path . tests/doorway_test.tscn` — 9 assertions. Walks the
player through their front door and back out, carrying materials. Separate
because it is the one test that changes scenes, and `change_scene_to_file` frees
whatever the current scene is — including a test living inside it.

It cannot answer the M1 gate. "Is this fun" needs hands on a keyboard, and then
two or three other people's hands. What it does is stop the numbers in the code
from drifting away from the numbers in the GDD without anyone noticing.

`tests/screenshot.tscn` captures a frame to a PNG, optionally with hitboxes
drawn and mid-swing, for checking layout without a human present.

---

## Project settings

**`project.godot` is owned by the editor, not by us.** Godot rewrites the whole
file whenever it saves the project: it strips every comment, reorders sections,
and drops any setting whose value equals the engine default. Anything explained
in there is deleted the next time someone opens the project — and on a shared
repo it also produces a phantom diff that blocks the next `git pull`. So the
explanations live here instead, and the file is left in exactly the form Godot
writes so that opening the editor is a no-op.

**Pixel-art importer defaults** (`[importer_defaults] texture=`) apply to every
texture, so sprites exported from Pixelorama import correctly without anyone
touching the Import tab per file. Two of the five are load-bearing:

- `process/fix_alpha_border: false`. It bleeds colour outward into transparent
  pixels to stop seams under linear filtering. This project filters Nearest, so
  there are no seams to stop — and the bleed writes colours into the edge pixels
  of every sprite that the artist never chose.
- `detect_3d/compress_to: 0`. Left on, it silently switches a texture to VRAM
  compression the first time it is used in a 3D context, which turns crisp
  pixels to mush. It is the single most common way a pixel-art project
  mysteriously goes blurry.

**Physics runs at 60 ticks/second.** You will not find that in `project.godot`,
because 60 is Godot's default and the editor drops the line. It matters anyway:
every number in GDD §5 is expressed in seconds and converted against this rate,
so the smoke test's tick-counted assertions assume it. If it ever needs to
change, change it in the editor and re-run the smoke test — several measured
values will move.

**Line endings** are pinned to LF by `.gitattributes`, for the same reason as
the first paragraph: Godot writes LF on Windows too, so letting git check out
CRLF means the editor "modifies" every file it opens.

---

## Sprite resolution: 64×96 (GDD §15, A1)

The project runs at **1280×720 internal, 64×64 tiles, 64×96 characters** — a
straight 4× on the GDD's original 320×180 / 16px / 16×24.

Framing is unchanged: 20×11.2 tiles on screen, character at 13% of screen
height. Everything spatial scaled by 4 and **nothing temporal changed**, because
frame data is in seconds. If you are comparing against the GDD's original
numbers, the mapping is:

| | Was | Now |
|---|---|---|
| Move speed | 82 px/s | 328 px/s |
| Dodge distance | 46px | 184px |
| Hit 3 knockback | 16px | 64px |
| Screen shake | 2px | 8px |
| Knockback friction | 900 | 3600 |
| Villager speed / aggro / lunge | 34 / 120 / 44 | 136 / 480 / 176 |

Two consequences worth keeping in view:

- **1080p is a 1.5× upscale.** 1280×720 is integer at 720p, 1440p and 4K, but
  not at 1920×1080. At this pixel density the unevenness is subtle; the standard
  fix is an "integer scaling only" video option that letterboxes. Worth folding
  into the difficulty/accessibility options question (GDD §14) rather than
  solving now.
- **Art is ~4× the pixel work.** The sprite *count* in GDD §2 is unchanged; the
  hours per sprite are not. The §11 milestone estimates predate this and should
  be re-baselined before they're trusted.

If you ever want to change resolution again, the values above are all `@export`ed
and the smoke test measures them, so a mis-scaled number fails loudly rather
than turning into a game that feels mysteriously sluggish.

---

## Save/load

JSON at `user://save_NN.json`, not `ResourceSaver`. A `.tres` can name a script,
so loading one at runtime executes whatever it points at — and a save file is
the one file in the game a player can hand-edit or download from a friend, which
makes it the worst possible place to accept that. There is a test asserting the
written file contains no reference to a script.

Built now, while it persists almost nothing, because the point is the shape
rather than the contents. A node opts in by joining the `saveable` group and
implementing three methods:

```gdscript
func save_id() -> StringName: return &"player"
func save_data() -> Dictionary: return {"health": health.current}
func load_data(data: Dictionary) -> void: ...
```

Adding heart shards, tools, whetstones, quest flags or which lines the fox has
already used is then two methods on whichever node owns that state, and no
change to the save system at all. Ids are stable strings rather than node paths,
so moving a node in the scene tree can't invalidate saves.

Four things it already handles, all of which are miserable to add later:

- **Versioning.** Every file carries a schema version and there is a `_migrate`
  hook. Refuses to open a file from a newer build rather than half-applying it.
- **Atomic writes.** Writes to `.tmp` and renames over the real file, keeping
  the previous save as `.bak`. A save interrupted by alt-F4 or a full disk
  cannot destroy the save the player already had.
- **Corruption recovery.** A truncated or hand-edited file falls back to the
  backup instead of reporting the run as lost.
- **Typed reads.** JSON has one number type, so every integer comes back as a
  float and any field can be missing or the wrong type in a file someone has
  edited. `SaveGame.read_int` / `read_float` / `read_vector2` are the only way
  values should come out of a save entry.

There is no save *point* yet — that is level content. `SaveGame.save_slot(1)` is
on F6 and load on F7 in the prototype room.

One ordering trap worth knowing, because there is a test pinning it: restore
`max_health` **before** `current`, or a save with more heart containers than the
default silently clamps down to the default on load.

---

## The haul (GDD §15 A4)

The riskiest claim in A4 is that gathering-and-returning feels like an
expedition rather than a commute, and the mechanic that decides it is built:

- **Carry capacity** (12 units, all materials weighing the same). The
  interesting decision in the loop is *when to turn back*, and that only exists
  if you can be full. A second weight axis would turn it into arithmetic.
- **Death drops the haul where you fell**, in a cache that waits indefinitely.
  Nothing is destroyed, only displaced — it is a stake, not a punishment.
- **One cache at a time.** A second death moves the pile rather than scattering
  the valley with them, so there is always exactly one thing to go back for and
  the player always knows where it is.
- **Caches survive quitting.** Losing a haul to a crash instead of to a mistake
  would make the stake feel arbitrary, which is the one thing it must not be.

Pickups are walked over, not interacted with — materials are routine, and a
button press forty times a run is a tax rather than a decision. The interact
verb, when it exists, is for things worth stopping for.

**Not yet built:** anywhere to spend a haul, and — until the player's home is
rebuilt — anywhere to put one down. Both are deliberate (GDD §15 A6): storage
lives in the home chest, the home is the first rebuild project, and the rebuild
transaction is the next piece. The plots carry their id, state, district, cost
tier and prerequisite as metadata; nothing reads them yet.

**What still needs your hands:** whether losing a haul stings the right amount.
Capacity, and whether the cache should decay, are both single numbers. My guess
is 12 is generous and the tension only appears around 6–8, but that is a guess
and the whole point of building it early is that you can go and find out.

---

## Tuning notes — for the human

### 1. Stamina currently does nothing

**The finding:** the dodge pool never binds. The minimum gap between dodges is
0.36s of roll plus 0.12s of cooldown = 0.48s, and stamina regenerates at
4 / 1.5s = 2.67/s, so 1.28 stamina comes back per dodge cycle against 1.00
spent. You can roll forever. The cooldown is the only real limiter.

The smoke test prints this as a `NOTE` rather than failing, because the values
are exactly what GDD §6 specifies — the interaction is what's new.

**This may be correct.** GDD §6 says stamina is "a rhythm limiter that stops
panic-rolling, not a resource to manage", and cites *Hyper Light Drifter*'s
unlimited dash. A pool that only bites when you mash faster than the cooldown
allows is arguably the design working. But right now it never bites at all, so
the 4-dodge pool is decoration.

**Three ways out,** in increasing severity — all one number in the inspector:

- Raise `full_regen_time` past ~2.0s so sustained rolling drains.
- Add `regen_delay` (currently 0.0) so regen pauses briefly after each roll.
- Accept it, and cut stamina from M1 entirely rather than shipping a bar that
  never moves.

Decide this with hands on the controller in week 4, not from the arithmetic.

### 2. Values that are guesses, not GDD numbers

The GDD specifies the player's frame data precisely and says almost nothing
about the enemy. These are starting points chosen to make the loop legible, and
all live in `resources/enemy_data/blighted_villager.tres`:

| Value | Set to | Why |
|---|---|---|
| `move_speed` | 34 | ~40% of the player's 82, so "slow walker" reads as slow |
| `attack_range` | 26 | slightly outside its own hitbox reach |
| `lunge_distance` / `lunge_time` | 44 / 0.18 | covers a dodge's distance in half a dodge's time |
| `recover_time` | 0.5 | the player's turn; the longest lever on difficulty |
| `stagger_time` | 0.14 | short — knockback carries the impact, not the stun |
| `aggro_range` | 120 | under half the 320px screen width |

`recover_time` is the one to reach for first. It is what decides whether a fight
is a conversation or a scramble.

Similarly guessed on the player side: `time_to_stop` (0.06s, GDD only specifies
acceleration), `hurt_stun_time` (0.18s), input `buffer_time` (0.12s), and the
dodge's `speed_exponent` (2.0).

### 3. Input buffering exists and isn't in the GDD

`InputComponent.buffer_time` holds a press for 0.12s. With an 0.08s windup and a
0.10s active window, an unbuffered combo drops inputs that the player is certain
they made. Set it to 0 in the inspector to feel the difference — it is worth
feeling once, because it calibrates how much of "snappy" is the frame data and
how much is the buffer.

### 4. Facing is locked from the active frames onward

You can re-aim during a hit's windup but not after. Turning during the wind-up
is responsiveness; turning after it is a get-out from a commitment the game just
asked you to make. `PlayerAttackState.allow_turn_during_windup` toggles it.

### 5. Off-screen attacks are gated by a rect check, not the notifier

GDD §5 enemy rule 4 says no enemy attacks off-screen. `BaseEnemy.is_on_screen()`
computes this from the canvas transform rather than reading a
`VisibleOnScreenNotifier2D`, because the notifier needs the renderer to have
drawn a frame — it reports false in headless runs and for a frame or two after a
spawn. The failure mode is an enemy that walks up to you and then does nothing,
which reads as broken AI rather than as a disabled check.

---

## The gate

> Answer out loud, to another person if possible: **is this fun?**

Nothing above answers it. The prototype exists so that question can be asked
cheaply, and the honest answer to it is the only output of M1 that matters.
