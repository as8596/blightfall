# Build Plan — *Blightfall*

Companion to `GDD.md`. The GDD is reference; this is what you work from.

**Current milestone: M1 — Combat prototype**
**Duration: 3–4 weeks · Deliverable: grey boxes that are fun · Gate: honest yes/no**

---

## The point of M1

One question: **is the combat fun with no art, no story, and one enemy?**

If yes, everything else in the GDD is worth building. If no, you've learned it in week four instead of month fourteen, and changing course costs you almost nothing.

### Two rules that decide whether M1 works

**1. Game feel is not polish. It is the thing being tested.**

The instinct is to defer hitstop, hit flash, and knockback as "juice for later." Don't. Grey boxes *with* hitstop feel good; grey boxes *without* it feel dead — and if you evaluate M1 without them, you will conclude your combat is bad when actually it's just unfinished. Feel is a required part of the prototype, not a reward for finishing it.

**2. Build a debug overlay in week one and never turn it off.**

Show on screen at all times: current state name, stamina value, whether i-frames are active, whether a hitbox is active, current combo index. Tuning frame data without this is guesswork. It takes an hour and saves you the whole milestone.

### What M1 does NOT contain

Write this list somewhere you'll see it. Every item is something solo devs build during M1 instead of testing whether the game is fun:

- ❌ No art. Coloured rectangles only.
- ❌ No tilemaps. One hand-placed box room.
- ❌ No menus, no title screen, no options.
- ❌ No save system.
- ❌ No dialogue, no NPCs, no fox.
- ❌ No XP, no levelling, no upgrades.
- ❌ No tools (not even Cinderflask).
- ❌ No second enemy type.
- ❌ No music. Placeholder SFX only.

---

## Week 1 — Movement that feels good on its own

**Goal:** you can move a rectangle around a room and it feels satisfying before any combat exists.

### Day 1 — project setup

- [ ] New Godot 4.4+ project
- [ ] Project Settings → Display → Window: Viewport `320×180`, Window `1280×720`
- [ ] Stretch Mode `canvas_items`, **Snap 2D Transforms to Pixel** on
- [ ] Rendering → Textures → Default Texture Filter: `Nearest`
- [ ] Rendering → 2D → Snap 2D Vertices to Pixel: on
- [ ] Physics layers named per GDD §10 (all eight, now — renaming later is painful)
- [ ] Input map: `move_up/down/left/right`, `attack`, `dodge`, `tool`
- [ ] Folder structure per GDD §10
- [ ] Git repo initialised, `.gitignore` for Godot

### Days 2–5 — player + state machine

- [ ] `StateMachine` node (generic, reusable — enemies use it too)
- [ ] `InputComponent` producing an intent struct. **The player script never calls `Input.is_action_pressed()` directly** (GDD §12 rule 3)
- [ ] `Player` as `CharacterBody2D`, 16×24 coloured rect
- [ ] States: `Idle`, `Move`
- [ ] 8-directional movement, 82 px/s, full speed in 0.08s
- [ ] All movement values `@export`ed so you tune in the inspector, not in code
- [ ] Grey box room with `StaticBody2D` walls
- [ ] `Camera2D` on a **separate rig**, not a child of the player (GDD §12 rule 4)
- [ ] Debug overlay: state name, velocity

**Week 1 gate:** walk around for two minutes. Does it feel responsive? If movement feels floaty or sticky now, it will feel worse with combat on top. Fix it here.

---

## Week 2 — the combat verbs

**Goal:** attack and dodge exist with exact frame data and are tunable live.

### Attack

- [ ] `Hitbox` (Area2D) and `Hurtbox` (Area2D) components
- [ ] `Attack` state with the three-hit combo from GDD §5
- [ ] Frame data `@export`ed — windup, active, recovery per hit
- [ ] Combo window: closes 0.25s after recovery begins
- [ ] Movement during attack: 25% speed hits 1–2, 0% hit 3
- [ ] Dodge-cancel out of recovery only

### Dodge

- [ ] `Dodge` state: 0.36s duration, 46px distance
- [ ] i-frames from 0.04 → 0.24
- [ ] 0.12s cooldown after recovery
- [ ] Stamina: 4-dodge pool, full regen in ~1.5s, **attacks cost nothing**

### Debug

- [ ] Hitbox/hurtbox visualisation toggle
- [ ] Overlay additions: stamina bar, i-frame indicator, combo index, active-hitbox flag

**Week 2 gate:** attacking empty air should already feel good. If the combo doesn't have rhythm against nothing, adding an enemy won't fix it.

---

## Week 3 — one enemy, and feel

**Goal:** a fight exists, and it has impact.

### Enemy

- [ ] `HealthComponent` (HP, damage handling, emits `died`)
- [ ] `KnockbackComponent`
- [ ] `base_enemy.tscn` designed for inheritance
- [ ] `EnemyData` custom Resource with `@export`ed stats (GDD §10)
- [ ] One enemy — the Blighted Villager: walk toward player, telegraph 0.4s, lunge, recover
- [ ] 12 HP, dies in ≤5 hits

### Game feel — do not skip

- [ ] **Hitstop:** 0.05s on hits 1–2, 0.10s on hit 3
- [ ] **Hit flash:** white for 0.08s via shader (not `modulate`)
- [ ] **Knockback:** 12–20px on the final combo hit
- [ ] **Screen shake:** 2px, heavy hits only
- [ ] **Placeholder SFX:** swing + impact as separate layers, pitch-randomised ±10%

**Week 3 gate:** killing one enemy should feel satisfying enough that you do it again without being asked.

---

## Week 4 — tune, then decide honestly

- [ ] Spawn 3–5 enemies in the room. Does fighting a group work, or does it collapse?
- [ ] Tune frame data. Expect real changes — the numbers in the GDD are starting points, not truth
- [ ] Verify the stamina pool. **If dodging ever feels like budgeting, the pool is too small**
- [ ] Check every enemy telegraph is readable at speed
- [ ] **Get 2–3 other people to play it.** You have lost the ability to judge this — you know exactly when the hitbox activates and they don't
- [ ] Record 30 seconds of footage and watch it back. Problems are obvious in video that are invisible while playing

### The gate

Answer out loud, to another person if possible: **is this fun?**

- **Yes** → proceed to M2. Lock §1 and §3 of the GDD; premise churn gets expensive from here.
- **Not yet, but close** → spend another 2–4 weeks here. This is a legitimate and common outcome.
- **No** → change the design. You have spent one month, not fourteen. This is the plan working correctly, not failing.

Do not proceed to M2 on a maybe. Everything downstream multiplies whatever you decide here.

---

## M2 preview — vertical slice (6–8 weeks)

Don't start this until M1 gates green. Sketch only:

- One room, fully finished to shipping quality — final art, final audio, lighting, transitions
- Player sprite with the complete animation set (GDD §8)
- Two enemy types with real sprites
- Ambry's first version, warm palette, three NPCs
- Intro as **text placeholder cards only** — proves pacing without building it
- Save/load, since it touches everything and finding out late is painful

M2's purpose is different from M1's: it establishes the **quality bar**. Whatever this room looks and sounds like is what the whole game will look and sound like, because you won't have time to raise it later.

---

## Standing rules

Carried from GDD §12 — cheap now, rewrite-expensive later. Follow them from day one.

1. Never make the player a singleton. No `Player` autoload, no `Global.player`.
2. No `get_first_node_in_group("player")` scattered through enemy code — one targeting helper.
3. Input goes through `InputComponent`, never `Input.is_action_pressed()` in the player script.
4. Camera rig separate from the player.
5. All combat randomness through one seeded RNG.
6. Every tunable number is `@export`ed.
7. Commit at the end of every session, even broken. Tag every milestone.
