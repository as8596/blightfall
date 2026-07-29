# Wishlist — everything between here and a v1 slice

Companion to `BUILD-PLAN.md`. That document is the plan for the milestone you
are in; this is the standing inventory of what does not exist yet, so that
"what's next" is a decision rather than a memory test.

Written against the repo as it actually stands, not against the GDD's
intentions. Where something is half-built, it says so and says which half.

---

## What "v1 slice" means here

The GDD's M2 is *"one polished room"*. That target is now behind us in some
directions and nowhere near us in others — Ambry is a 48×42 village with four
interiors and working doors, and there is still no dialogue, no second enemy,
and nowhere to go outside the gate.

So the useful definition is not a room. It is **one complete turn of the loop,
played by a stranger without explanation**:

> Arrive in Ambry. Meet someone who talks. Take a reason to leave. Go out the
> gate into somewhere hostile. Fight things that are not all the same thing.
> Fill the satchel. Come back — or die and lose it. Build one thing. Watch the
> town change because you built it. Be told there is more.

If a stranger can do that unaided and wants to do it again, the slice is real
and everything in the GDD is worth building. If they can't, the fix is cheap
now and ruinous at M5.

**Everything below is measured against that sentence.** Slice-critical items
are marked ⭑. Everything unmarked is real work that the slice does not need.

---

## The critical path

The shortest line from here to that paragraph. Ordered by dependency, not by
size — later items are blocked by earlier ones.

| # | Thing | Why it's on the path |
|---|---|---|
| 1 | ⭑ **Place pickups** | The satchel has no source. Nothing in any level fills it. |
| 2 | ⭑ **The rebuild transaction** | The satchel has no sink. `building_plots()` is read by tests and nothing else. |
| 3 | ⭑ **Village state in saves** | A town that forgets what you built is not a progression system. |
| 4 | ~~One zone outside the gate~~ | **Built.** Orchardfall: six areas, walk-into edges, one interior (`docs/ORCHARDFALL.md`). It has no enemies and nothing to pick up. |
| 5 | ⭑ **Three more enemies** | One enemy is a test fixture. A fight needs a reason to choose between verbs. |
| 6 | ~~Dialogue~~ | **Built.** Typewriter box, per-character voice blips, branching replies. All ten of the cast are bodies you can talk to. The lines are placeholders. |
| 7 | ~~Title screen~~ | **Built.** `ui/main_menu.tscn` — continue, new game, UI scale, quit. |
| 8 | ⭑ **The town visibly changes** | The payoff. Without it, building is a receipt. |

That is the slice. Items 1–3 are days, not weeks — the systems around them
already exist and are tested. Item 4 is the largest single piece of work in the
list.

---

## 1. Programming

### The haul loop — both ends missing

The loop A4 is built around cannot currently be closed. This is the single
biggest gap in the project and it is not a large amount of code.

- ⭑ **Pickups placed in a level.** `world/pickup.tscn` exists and is tested;
  no level instances one. Materials are placed by hand, never dropped (A4).
- ⭑ **Rebuild transaction.** Stand on a plot, spend timber/stone/ironwork,
  change its state. `Level.building_plots()` already returns id, state,
  district, cost and requirements. Nothing reads it outside the tests.
- ⭑ **Village state in the save.** A `village` node joins the `saveable` group
  and implements three methods. The save system takes it with no changes.
- ⭑ **Per-building effects wired to `StatsComponent`.** The component enforces
  the rule (every modifier names its building) and nothing grants one yet.
- **Project prerequisites.** The archive needs the wall. The data carries it;
  nothing checks it.

### Interaction

- ~~Dialogue.~~ **Built** — `ui/dialogue_box.gd`, one JSON file per character in
  `resources/dialogue/`. What it does *not* have is state: every conversation
  starts at the same node every time. An NPC saying something different after
  the wall goes up needs a condition on a node, and that needs village state
  (item 3) to exist first.
- **Talk / build / rest / read as separate `Interactable` subclasses.** Talking
  is done (`world/npc.gd`); the rest are small now that the verb exists.
- **The bed.** Rest, save, and the reason death has somewhere to send you.
- **The chest.** Storage that survives death — the counterweight to
  loss-on-death.
- **Prompts on anything but doors.**

### World

- ~~One zone.~~ **Built** — Orchardfall, six areas with a loop in the graph
  (`docs/ORCHARDFALL.md`). What it does not have is anything in it.
- ~~Zone travel.~~ **Built** — `world/gateway.gd`. Edges are walked into, doors
  are still pressed.
- ⭑ **Encounter placement.** Enemies currently spawn at random markers in a test
  room. Six areas exist and not one of them contains a fight.
- **The blight as terrain.** It blocks paths and recedes when the town is
  rebuilt. Nothing implements it.
- **The north wall unlock at runtime.** The map is built both ways and asserted
  both ways; nothing flips it in game.

### Tools (the four keys)

Zero of four. Each is a combat option *and* a traversal unlock.

- **A tool framework at all** — the `tool` verb is bound and does nothing.
- ⭑ **Cinderflask**, if the slice wants a second verb. GDD §6 flags a
  production dependency: the intro grants it, the intro is built at M6, so
  M1–M5 need a debug flag. Ten minutes, easy to forget until it blocks you.
- Warden's Hook, Clearwater Charm, Deeproot Sight.
- **Status effects** (burning, stun) — nothing in the damage path carries a
  type.

### Front end and options

- ~~Title screen.~~ **Built** — `ui/main_menu.tscn`, and it is the boot scene.
- ~~New game / continue.~~ **Built.** Continue is disabled when the slot is
  empty rather than doing nothing. New Game deliberately does *not* delete the
  save — overwriting a run on a mis-click needs a confirmation, and that needs
  more than one slot to be worth building.
- **Audio buses and volume sliders.** Everything plays on Master. There is no
  way to turn the music down.
- **Controller support.** `InputComponent` already reads an aim stick; nothing
  else is mapped or tested.
- **Key rebinding.**
- **Resolution / windowed / integer-scale toggles.** `WorldView.integer_scale`
  exists and is not exposed.

### Systems with no owner yet

- **What a level does.** A8 left it deliberately open: a title, a story beat,
  or a gate on which projects Ambry will attempt. It currently pays nothing,
  and a bar that pays nothing is one players resent.
- **Enemy variety in code.** `EnemyData` covers one behaviour shape — approach,
  telegraph, lunge, recover. Ranged, stationary, splitting and spawning enemies
  each need new states.
- **Bosses.** No boss framework: phases, arena, one-time-only, a door that
  locks.
- **Cutscene sequencer** (GDD §10). Needed at M6, needed sooner if the slice
  wants a cold open.
- **Day / town-state progression.** "How the town changes" is a documented
  design with no implementation.

---

## 2. Effects and game feel

The M1 feel work — hitstop, shader flash, knockback, shake — is done and is the
reason the combat reads. What is missing is everything that makes a *place*
feel inhabited.

- **The weapon arc has no art.** It is a drawn polygon fan. It works; it is
  placeholder.
- **Impact particles.** Hits flash and stop time and produce nothing.
- **Enemy death.** They vanish. A dissolve, a puff, anything.
- **Footstep dust**, and grass that reacts to being walked through.
- ⭑ **The blight glow.** GDD §8's single most load-bearing art rule: corruption
  is the only saturated colour in the game and it is the only thing that glows.
  Nothing implements it. A shader plus a palette discipline.
- **Ambient light / time of day.** Ambry is meant to read warm — amber, ochre,
  ember. A `CanvasModulate` and a lighting pass would do most of it.
- **Camera lookahead** in the direction of travel.
- **Weather and ambient particles** — motes, ash, rain.
- **Transitions beyond fade-to-black.** The fade works and is used everywhere.

---

## 3. Story and script

Nothing is written. The GDD has a beat sheet and a cast; the repo has ten
markers and no words.

- **Ten NPCs with lines.** All ten now speak, and every line is a placeholder
  written to the "warmth expressed as" column in `docs/AMBRY.md` rather than to
  a script that does not exist. The carpenter's is the only one that branches.
  This is scaffolding for a writer, not writing.
- ~~A reason to leave town.~~ The carpenter gives one: timber and stone, gate's
  south.
- **The opening sequence** (GDD §4). Full beat sheet exists. Built last, on
  purpose — but the slice may want text placeholder cards, which is what M2 was
  always supposed to prove.
- **The unresolved prologue idea.** Raised in a previous session — the game
  opening as your younger self, with a sister. Two questions were asked and
  never answered, and nothing was recorded. **It is not in the GDD.** If it is
  still wanted, it needs a decision before the intro is built, because it
  changes §4 substantially.
- **The gallows conversation.** GDD calls this the most important piece of
  writing in the rebuild loop: the unrepentant objects, the magistrate says
  nothing, and neither position is scored. If the slice ships one written
  scene, this is the one worth it.
- **The fox.** Named, bipedal (A3), no lines and no sprite.
- **Environmental writing** — the ledger, notes, what the chest contains.
- **Boss identities.** All three are corrupted named NPCs, which is where the
  drama comes from and which means they need to be met before they are fought.
- **The ending.** Win condition is defined (§3); nothing is written.

---

## 4. Art

Production order is GDD §8: player, one enemy, zone 1 tileset, UI, everything
else, intro assets last.

- ⭑ **Real player animation.** What ships is the reference body composited at
  an anchor and slid around per frame. Four directions are now correct; the
  walk cycle still does not move legs. Replace one clip at a time.
- ⭑ **Enemy sprites.** One of ten enemies exists and it is a coloured box.
- ⭑ **Ambry tileset.** ~40 tiles, warm palette. Everything is greybox.
- **Orchardfall tileset.** ~40 more.
- **Interiors.** Four exist as greybox rooms.
- **Props and set dressing.** The gallows in particular has to read as what it
  is without a line of dialogue.
- **UI art.** Every panel, bar and slot is a drawn rectangle. It is consistent
  and it is not designed.
- **Item icons.** 39 exist, sorted into `materials/`, `consumables/` and
  `parked/`. Four items are defined.
- **The fox.**
- **VFX sprites** — impacts, the blight, pickups.
- **Portraits — a decision, not a task.** Dialogue without them is cheaper and
  the game may not want them at all.

---

## 5. Audio

The thinnest area in the project, and the one the GDD explicitly says to
license rather than make.

- **1 of 6 music tracks.** And it is a **27 MB WAV** that should be an OGG at
  roughly a tenth the size. There is no encoder in the build environment; this
  is a job for the desktop.
- **13 of ~45 SFX.** All generated placeholders — the five newest are the
  dialogue voice blips and two UI ticks.
- **0 of 4 ambience beds.**
- **No mixing.** One bus, no ducking, no options.
- **Missing whole categories** — footsteps by surface, doors, UI, the build
  sound, pickups, ambient village noise.
- Pitch-randomisation ±10% is already in `Sfx`, which is the cheap win the GDD
  asks for.

---

## 6. Interface

Built: HUD (health, experience, satchel, twelve-slot hotbar with reserved
potion slots), stamina wheel, Tab menu with character / inventory / map,
Escape menu with UI scaling, pause, fade transitions, debug overlay.

Missing:

- ~~Dialogue box.~~ **Built.** No portraits — a decision deferred, not an
  oversight.
- ⭑ **Build prompt** — what this costs, what you carry, what it gives.
- ~~Equipment slots.~~ **Built** — weapon, armour, tool, in the inventory pane
  (GDD §15 A9). Two placeholder items exist; nothing in the world drops gear.
- **The map tab is a joke that has not been made yet.** It says *"You have no
  map"*, which is correct and deliberate — the archive grants it (project 6) —
  but nothing grants it and there is no map to grant.
- **The character tab has no source of stats.** It reads `StatsComponent`
  faithfully and every number is currently a base value.
- **Settings** — audio, controls, display.
- **Save slot UI.**
- **Item tooltips outside the inventory grid.**

---

## 7. Debts already on the books

Small, known, and each one is a thing that will be more annoying later.

- **The XP bar pays nothing.** Recorded as GDD §15 A8, deliberately, with the
  risk stated. It is a placeholder for a decision.
- **`the_beginning.wav` is 27 MB.** Every clone carries it.
- ~~39 orphaned `.png.import` files.~~ **Removed.** They were not harmless: an
  `.import` with no source file is one Godot rewrites, and a rewritten tracked
  file that a later commit deletes blocks `git pull` with "your local changes
  would be overwritten". Which is exactly what it did.
- **The prototype room is still the only combat space**, and it is reachable
  only by opening the scene and pressing F6. Orchardfall has six areas and no
  enemies in any of them.
- **Stamina regen is upgradeable and nothing upgrades it.** Same for damage,
  reach, carry and max health — the plumbing is in, the taps are not.
- **`SpriteAnimation` has no per-frame timing**, so a clip's frames are evenly
  spaced. Fine for placeholders, wrong for a real walk cycle.
- **No enemy has a hurt-flash-to-death readability pass** at the sprite level,
  because there are no sprites.

---

## 8. Deliberately not in the slice

Written down so that wanting them is a decision rather than a drift.

- Zones 2 and 3, and bosses 2 and 3.
- Tools 2–4.
- The full intro sequence with bespoke art (GDD §4 says build it last, and it
  is right).
- Five of six music tracks.
- Heart shards and whetstones — 24 and 3 hidden pickups is content, not system.
- Co-op (GDD §12 — explicitly not scoped; the architecture insurance is
  already paid).
- Store page, achievements, localisation.
- Six of the eight rebuild projects. **The slice needs two: your home, which
  teaches the mechanic, and one that visibly changes the town.**

---

*Living document. Reread when "what's next" stops being obvious.*
