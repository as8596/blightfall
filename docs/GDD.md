# Game Design Document — *Blightfall* (working title)

**Genre:** Top-down action RPG, pixel art
**Engine:** Godot 4.4+ (GDScript)
**Team:** 1 developer
**Platform:** PC (Windows/Linux), Steam or itch.io
**Target playtime:** 2.5–4 hours
**Status:** Working draft, and a **template** — sections are amended when the
build says otherwise. Open questions marked 🔶. Amendments logged in §15.

---

## 1. High Concept

> A valley is dying of a rot nobody understands, and the frightened towns have started hanging anyone suspected of carrying it. You are on the gallows for a crime you don't have — and as the axe rises, the real thing arrives.

**The hook:** You are condemned by people who turn out to be right about the danger and wrong about you. Then you go and fix it for them anyway.

### Design pillars

1. **Readable, snappy combat.** Every enemy telegraphs. Every death is the player's fault and they know it. No damage sponges.
2. **Small world, dense with secrets.** A compact map the player learns by heart, not a large one they cross once.
3. **Grim world, warm people.** The valley is rotting. The town is a genuine refuge — warm, safe, and worth saving. Warmth comes from kindness and steadiness, not humor.

### Non-goals

- ❌ Not a party-based RPG. One playable character.
- ❌ No crafting system.
- ❌ No procedural generation. Hand-authored maps only.
- ❌ No voice acting.
- ❌ No open world.
- ⚠️ Co-op is a **stretch goal only** — see §12. Not designed for, not built for, not scoped.

---

## 2. Scope Contract

Hard ceilings. Reread whenever a new idea seems exciting.

| Content type | Budget |
|---|---|
| Playable characters | 1 |
| Zones | 3 + 1 hub |
| Enemy types | 11 (incl. 3 variant reskins) |
| Bosses | 3 |
| Tools / abilities | 4 |
| NPCs with dialogue | 10 (incl. the fox and the carpenter — §15 A6) |
| Music tracks | 6 |
| Scripted sequences | 5 |
| Unique sprites | ~47 |

**Estimated solo timeline:** 12–18 months at 10 hrs/week.

---

## 3. The Antagonist — The Blight

An **inhuman force**, deliberately not a character. It never speaks, never appears as a figure, and has no motive. It spreads.

### Making an impersonal antagonist work

Four techniques, all cheap, all mandatory:

1. **It has a grammar, not a personality.** Consistent, legible rules the player learns. That legibility becomes its character.
2. **Victims carry the drama.** The blight doesn't need to talk if the people it takes do. This is why pillar 3 exists.
3. **Bosses are its products, not its avatars.** Each of the three is something it made, carrying a fragment of who they were.
4. **Its screen time is environmental.** How far the rot has spread through the tilesets *is* its presence.

Reference: *Hollow Knight*'s Infection is the best-executed version of exactly this.

### What it does

Transforms people and animals into monsters. Physical, visible, progressive — you can see how far gone something is by looking at it.

### Reversibility — ASYMMETRIC (decided)

Enemies you fight and people you save are deliberately decoupled:

- **Nameless enemies are always beyond help.** Blighted Villagers, Rot Hounds, Husks — universally too far gone. Killing them is mercy. No guilt loop, no second-guessing, no pacifist route to design around.
- **Named characters are individually saveable** through specific quests, choices, or reaching them before a story beat. Never on a real-time clock — story-gated only, so rescue never competes with the exploration pillar.

The ending's tone scales with how many named characters were saved. **Boss 1 (the cellmate) is the emotional centerpiece** — whether they can be saved is the hardest optional objective in the game, and pays off the opening a second time.

### Win condition

**Destroy a physical heart/source.** Concrete, killable, satisfying. The three zones each contain something guarding or feeding it; the finale is reaching and destroying it.

---

## 4. The Opening Sequence

Target runtime **6–8 minutes**. Structure follows Skyrim's Helgen opening, which works for reasons worth naming explicitly:

- **No control for a long time.** Tension built by denying agency, then granting it.
- **Exposition arrives sideways.** Nobody explains the world; you eavesdrop and assemble it.
- **You are explicitly a nobody.** Condemned by clerical convenience. Petty injustice motivates better than epic tragedy.
- **Someone else dies first, on screen.** Stakes demonstrated, not asserted.
- **The world-level threat interrupts the personal one.**
- **The tutorial is disguised as escape.**
- **It ends on a real choice.**

### Premise

You are being executed as a **suspected blight carrier**. You aren't one. The valley is terrified, the infection is poorly understood, and the response has been to hang the accused. The people about to kill you are scared and wrong, not evil — which matters, because you'll come back to this town later and they'll help you.

### Beat sheet

| # | Beat | Duration | Control | Notes |
|---|---|---|---|---|
| 0 | Black screen, audio only | 0:15 | None | Cart wheels, crowd, a bell ×3. No title card. |
| 1 | The cart | 2:00 | Move within cart | Three cellmates. All exposition happens here. |
| 2 | Arrival & the ledger | 1:00 | None | Diegetic character creation. "You're not on this list." |
| 3 | The first execution | 0:45 | None | The Liar dies, still protesting. Camera does not cut away. |
| 4 | The walk | 0:30 | Forward only | Camera pushes in. Crowd audio drops. Music thins to one instrument. |
| 5 | The block | 0:20 | None | Forced kneel. The axe rises. |
| 6 | **The blight arrives** | 0:30 | None | It reaches the town mid-execution. Chaos. |
| 7 | Escape (tutorial) | 2:00 | Full | Movement → attack → dodge, all under pressure. |
| 8 | The offer | 0:45 | Dialogue choice | Two exits. Seeds later dialogue. |

### The cellmates

Each does a job:

- **Wren (The Talker)** — terrified, cannot stop narrating. Delivers world exposition because his anxiety demands it.
- **Halvard (The Stoic)** — says four things total, all load-bearing. Has made peace with dying.
- **The Liar** (unnamed) — insists there's been a mistake, that someone is coming. Nobody comes. Dies first, so the player learns that protest doesn't work here.

**Writing note:** none of them should address the player directly for the first 60 seconds. Let the player eavesdrop. The moment an NPC says "So, stranger, what brings *you* here?" the illusion collapses into a tutorial.

**Payoff:** one cellmate survives the escape and becomes **Boss 1**, found transformed in Zone 1. Sprite already built, player already attached.

### Build the intro LAST

The most important production note in this document. The intro is the most fun part to design and the least important to validate. Schedule it at **M6**, prototype it as text placeholder cards during M2, and **make it skippable after first completion** — you will play it a hundred times in testing.

---

## 5. Combat Design

Real-time, action-focused. Few verbs, demanding execution. Difficulty comes from enemy design, not moveset depth.

### Player verbs

| Verb | Input |
|---|---|
| Move | WASD / left stick |
| Attack | J / X — 3-hit combo |
| Dodge | Space / A — directional roll, i-frames |
| Tool | K / Y — context-dependent |

### Frame data

Concrete starting values, all in seconds.

**Attack (light combo)**

| Hit | Windup | Active | Recovery | Damage | Cancel |
|---|---|---|---|---|---|
| 1 | 0.08 | 0.10 | 0.16 | 4 | into hit 2 from 0.12 |
| 2 | 0.07 | 0.10 | 0.18 | 4 | into hit 3 from 0.12 |
| 3 | 0.14 | 0.12 | 0.32 | 8 | none (commit) |

- Combo window closes 0.25s after recovery begins
- Attacks dodge-cancel during recovery only — the main skill expression
- Movement during attack: 25% speed on hits 1–2, 0% on hit 3

**Dodge**
- Duration 0.36s · i-frames 0.04→0.24 · distance 184px · 0.12s cooldown after recovery

**Player baseline**
- Move speed 328 px/s (at 1280×720) · full speed in 0.08s · 6 hearts start, 12 max · 0.8s i-frames on damage

### Game feel checklist

- **Hitstop:** 0.05s on hits 1–2, 0.10s on hit 3
- **Screen shake:** 8px on heavy hits only
- **Knockback:** 48–80px on final combo hit
- **Hit flash:** white for 0.08s via shader, not `modulate`
- **Sound layering:** every hit gets a swing sound *and* an impact sound

### Enemy design rules

1. Telegraph minimum **0.4s**, distinct colour and pose
2. One attack pattern per enemy (bosses get three)
3. Every enemy killable in ≤5 hits at matched gear
4. No enemy attacks off-screen

### Roster

Everything is a corrupted human or animal — one humanoid rig plus one quadruped rig, with corruption variants, covers nearly the whole list.

**One exception, and it is the point.** The Forest Wolf is an ordinary animal: no rot, no accent, nothing to be merciful about. It exists so the valley is dangerous *before* the blight is, which is what makes the first Blighted Villager land as a change rather than as a difficulty curve. It also shares the quadruped rig with the Rot Hound, so it costs one sprite set rather than one enemy.

| Enemy | Zone | Behavior | HP |
|---|---|---|---|
| Blighted Villager | All | Slow walker, lunge | 12 |
| Forest Wolf | 1 | Fast, lunges; hunts in pairs. **Not blighted** | 10 |
| Rotcrow | 1 | Erratic flight, dive attack | 8 |
| Thornmass | 1 | Stationary, ranged volley | 16 |
| Blighted Guard | 1 | Shielded front, flank to damage | 24 |
| Hollow Stag | 2 | Charges in straight lines | 18 |
| Fused Pair | 2 | Two victims grown together; splits at 50% HP | 28 |
| Rot Hound | 2 | Fast, circles before lunging, packs of 3 | 14 |
| Seeder | 3 | Spawns Villagers; must be rushed | 20 |
| Grave Bloom | 3 | Heavy, ground-slam AoE, slow | 40 |
| Husk | 3 | Long-transformed; unrecognizable, fast | 18 |

### Bosses

All three are corrupted named NPCs. Drama comes free.

1. **Zone 1 — the surviving cellmate.** Direct payoff to the intro. Teaches dodge timing; forgiving, telegraph-heavy.
2. **Zone 2 — the valley's protector.** The guard captain who tried to hold the line. Teaches crowd control.
3. **Zone 3 — the first victim.** Transformed for generations, closest to the heart. Barely humanoid.

---

## 6. Progression

> ⚠️ **Superseded by §15 A4.** Progression is now the rebuild state of Ambry:
> materials are carried home from zones and spent on buildings, and each
> rebuilt building grants a capability. XP is recommended for deletion. The
> section below is kept for the reasoning behind the four XP rules, which
> still applies to any numeric progression that replaces it.

**Item gates for world progression, light XP for numbers.** Item gates do all gating; XP only adjusts values.

### XP rules (non-negotiable)

Violate these and you've signed up for permanent tuning debt across every encounter:

1. **Cap at 10–15 levels** across the whole game
2. **Never scale enemies to level.** Levels make you absolutely stronger — grinding becomes an accessibility valve, not a treadmill
3. **Weight XP toward bosses and exploration**, not trash kills
4. **Levels gate nothing**

### Tools (the four keys)

Each is a combat option *and* a traversal unlock, so every acquisition opens the world.

| Tool | Combat use | Traversal use |
|---|---|---|
| **Cinderflask** | Ignite enemies | Burn away blight growth blocking paths |
| **Warden's Hook** | Pull an enemy toward you | Grapple across gaps |
| **Clearwater Charm** | Stun corrupted enemies | Safely cross blighted water |
| **Deeproot Sight** | Reveal Husks | Reveal hidden paths |

**Acquisition order — DECIDED.** Four tools, one granted in the intro, then one per zone:

| Where | Tool | Opens |
|---|---|---|
| Intro escape | Cinderflask | — (tutorial verb) |
| Orchardfall | Warden's Hook | Stillwater |
| Stillwater | Clearwater Charm | Hollowdeep |
| Hollowdeep | Deeproot Sight | the finale |

Strictly linear; each zone teaches exactly one new verb. Cinderflask is grabbed while fleeing the burning town, so the escape tutorial covers move, attack, dodge, and one tool.

⚠️ **Production dependency:** the intro is built at M6, so M1–M5 need a debug flag granting Cinderflask. Ten minutes of work, but easy to forget until it blocks you.

### Found upgrades

Placed by hand as rewards for exploration or challenge rooms. Never random drops.

- **Heart Shards** — 4 = 1 container. 24 hidden (6 hearts total)
- **Whetstones** — +2 base damage. 3 in the world

### Stamina — DODGE ONLY (decided)

- **Attacks never cost stamina.** They stay free and snappy; the frame data already prevents mashing via commit windows and combo timeouts.
- **Dodge costs stamina.** Generous pool (4 consecutive dodges), refill in 6s
  after a 0.7s pause. **Amended from ~1.5s**, which is what the "validate at M1"
  line below asked for and got: at 1.5s the pool refilled faster than the dodge
  cooldown could spend it, so it never bound and the meter was decoration.
- It functions as a rhythm limiter that stops panic-rolling, not a resource to manage.

Rationale: *Hyper Light Drifter*, the closest reference for this game's feel, has an unlimited dash, and that's a large part of why it plays as well as it does. Gating 0.08s-windup attacks behind a meter would fight pillar 1 directly. Validate the pool size at M1 — if dodging ever feels like budgeting, the pool is too small.

---

## 7. World Structure

```
                    ┌──────────────┐
                    │    AMBRY     │  ← the town that condemned you
                    │   (the hub)  │     NPCs, shops, save point
                    └──────┬───────┘
            ┌──────────────┼──────────────┐
      ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
      │ ORCHARD-  │  │ STILL-    │  │ HOLLOW-   │
      │   FALL    │  │  WATER    │  │   DEEP    │
      │           │  │           │  │           │
      │ recently  │  │   long    │  │  origin   │
      │  taken    │  │  taken    │  │           │
      │           │  │           │  │           │
      │ Cellmate  │  │ Protector │  │  First    │
      │           │  │           │  │  Victim   │
      └───────────┘  └───────────┘  └───────────┘
```

### Zone identities

Not biomes. Each zone is **a place with a former function, consumed at a different stage** — the organizing axis is how long the blight has been there. This gives visual identity from the old architecture, environmental storytelling from what's left, and enemy logic from who was standing there when it happened.

**Orchardfall — recently taken.** Farmland and orchards on the valley floor, an hour's walk from Ambry. Fruit rotting unpicked, doors standing open, a plough left mid-furrow. The most emotionally legible zone precisely *because* it's still recognizable — everyone knows what a farm should look like, so the player reads the loss without being told.

Palette: **the hub's warm colours, sickened.** Ochre sliding to yellow-green, warm browns going grey. Corruption of the familiar, not a new biome — Orchardfall should feel adjacent to safety.
Enemies: Blighted Villagers, Blighted Guards, Rotcrows, Thornmass. People you might recognize.

**Stillwater — long taken.** The valley's lower reach, flooded: a river dammed by rot until the water rose over a mill and the buildings around it. Roofs above the waterline, a mill wheel still turning because nothing told it to stop.

Palette: cold. Blue-grey, teal, deep green, black water.
Enemies: the human vanishes and the wild takes over — Hollow Stags, Rot Hounds, the Fused Pair.

**Hollowdeep — the origin.** A sinkhole in the high valley. The ground gave way and revealed caverns that were always under the farmland, and the thing in them has been there far longer than the town has. The player descends.

Palette: near-monochrome, tightly narrowed, with the blight accent as almost the only colour in frame.
Enemies: Seeders, Grave Blooms, Husks. Barely anything reads as human.

The horror is retroactive: the valley was always sitting on top of it.

**Zone template** — identical for all three. Consistency is a solo dev's ally.

- 15–20 screens
- 1 mini-boss / challenge room
- 1 tool acquisition room
- 3–4 hidden Heart Shards
- 2 shortcuts back to the entrance, unlocked from the far side
- Save point every 5–6 rooms
- Boss arena

### The hub

> ⚠️ **Amended by §15 A4.** Ambry is now also the progression system — the
> player rebuilds it, and its state is a live readout of whether they are
> winning. Everything below still holds; it gains a mechanical spine.

Narratively the most important location, and where the warmth lives. The zones are grim; the town is warm, safe, and worth saving. Concentrating emotional investment into one reusable scene is cheap and effective.

**Tone: warm, not funny.** Humor is deliberately not used. Warmth comes from three other sources:

1. **Kindness at cost.** Not people being nice — people helping when helping is expensive for them, and not mentioning it.
2. **Continued domesticity.** Ordinary rituals persisting through catastrophe. Bread still baked, clothes still mended, a song still sung at the same hour. Costs one line and one idle animation.
3. **Safety as a sensory quality.** Not a writing problem — art, audio, and pacing. The player's body should register the hub as safe before they read a word:
   - **Palette:** the hub is the *only* location using the warm end of the 64 colours. Zones get the cold slice. Entering town should feel like temperature changing.
   - **Music:** zones get drones and ambience; the hub gets melody and real instrumentation.
   - **Zero pressure:** no enemies, no timers, no fail states, no screen shake, slower camera. Mechanically incapable of hurting you, and the player feels it within ten seconds.
   - **Light is hearths, not glare.** Fire, lamps, windows.

Get those right and the NPCs can be written completely straight.

**It changes as the blight advances.** After each zone: more refugees, fewer shops open, walls further reinforced. The same handful of NPCs under increasing pressure, getting *more* screen time rather than less.

### Cast

Each character is defined by how they're kind under strain, not by a comic bit. Varied in age, temperament, and relationship to your condemnation.

| NPC | Warmth expressed as | Note |
|---|---|---|
| The magistrate | Doing things for you unasked, never mentioning it | Read your sentence. Can't look at you |
| The smith | Work. Upgrades gear, refuses payment, changes the subject | Few words, elderly |
| The innkeeper | A made bed and hot food, every time | Keeps the inn open though nobody comes |
| The child | Treating you as ordinary | Not afraid of you. Asks about the world outside |
| The apothecary | Taking you seriously | Methodical, out of her depth, honest about it |
| The hidden case | Warmth curdling into dread | Infected, concealing it |
| The reluctant guard | Practical protection | Opposed the hanging, was overruled |
| The unrepentant | None — and that's the point | Still believes you're a carrier |
| **The fox** | Unambiguous, uncomplicated gentleness | See below |

The unrepentant is load-bearing: a town that fully forgives itself never really condemned you.

**Implementation:** 5–8 rotating idle lines per NPC, cycling per visit. Trivial to build, enormous perceived depth. Nobody thanks the player until late — earned gratitude lands, free gratitude is noise.

### The fox 🔶 *(name TBD)*

A fox that talks. **The game never explains this and no NPC ever remarks on it.** The moment it's justified it stops being charming and becomes a lore item.

**Role: guide.** Solves the structural problem that an antagonist which never speaks still needs someone to convey its grammar — without turning a human NPC into an exposition dispenser.

**Source of authority is observation, not wisdom.** It goes where people can't: small, unafraid, has been through the whole valley, and notices the rot before people do — better senses, not magic. This makes it credible *and* frequently uncertain, which is warmer than being oracular.

**Guide rules** (the difference between beloved and despised):

1. **Player-initiated only.** Speaks when spoken to. Never interrupts, never auto-triggers, never pops up.
2. **Never repeats.** Track what it has said.
3. **Observes, doesn't instruct.** "The rot's thicker by the water than it was" — not "go to the lake and use the Charm."
4. **Warmth through presence, not chatter.** It waits. It doesn't fill silence.

**Placement, not companionship.** A following companion costs pathfinding, geometry snags, combat interference, camera problems, and special handling in every cutscene — weeks of bugs for a solo dev. Instead the fox **appears at fixed points, sitting, waiting**: in the hub, plus 2–3 placed spots per zone. Finding it already there inside a rotting zone extends the hub's safety into hostile space at controlled intervals. Cost: a static NPC placement.

**It is never harmed.** Not sentiment — design. "Warm and safe" is a stated goal, and in a game about a valley being taken from people, exactly one thing that *cannot* be taken is what makes safety feel real instead of provisional. Never threatened, never infected, never at risk. Like the talking, never addressed.

---

## 8. Art Direction

- **Internal resolution:** 1280×720 (1× at 720p, 2× at 1440p, 3× at 4K; 1080p lands on 1.5× — see §15)
- **Tile size:** 64×64
- **Character sprite:** 64×96; enemies 64×64 to 128×128; bosses up to 256×256
- **Palette:** **64 colours**, fixed. Use a pre-made one (Endesga 64 or similar, from lospec.com). Do not design your own — it's a week you don't have. The extra 32 over the original budget are for more *tones per material*, not more hues — see §15 A2
- **Animation budget:** idle 2 · walk 4 (×4 dir) · attack 3/hit · dodge 4 · hurt 1 · death 5

### Visual language

- **Corruption is the one saturated colour.** Everything else muted — greys, browns, sick greens. The blight is the only thing that glows.
- **Transformation is readable at a glance.** Corruption stage visible in silhouette, so players judge threat instantly.
- **Zone identity via palette subsets.** Same 64 colours, different ~20-colour slices per zone: Ambry warm (amber, ochre, cream, ember); Orchardfall the same warmth sickened (yellow-green, grey-brown); Stillwater cold (blue-grey, teal, black water); Hollowdeep near-monochrome. The blight accent — one luminous yellow-green — is constant across all four and is the only saturated colour in the game.
- **Readability rule:** enemies carry one accent colour no environment tile uses.

### Production order

1. Player sprite, all animations
2. One enemy (Blighted Villager) — proves the pipeline
3. Zone 1 tileset (~40 tiles)
4. UI
5. Everything else
6. Intro-specific assets **last**

---

## 9. Audio

| Asset | Count |
|---|---|
| Music tracks | 6 |
| SFX | ~45 |
| Ambience | 4 |

Unless audio is a genuine strength, license or commission. Budget $300–800 for six tracks.

**Cheap wins:** pitch-randomise every SFX ±10% on playback — one footstep becomes infinite footsteps, two lines of code. And the intro's most powerful audio moment is silence, which is free.

---

## 10. Technical Architecture (Godot 4)

### Project structure

```
res://
├── actors/
│   ├── player/  (player.tscn, player.gd, states/)
│   ├── enemies/ (base_enemy.tscn, per-enemy folders)
│   └── components/  (Hurtbox, Health, Knockback, Input)
├── systems/  (state_machine/, dialogue/, sequencer/, save/)
├── resources/  (enemy_data/, items/, dialogue/)
├── levels/  (intro/, hub/, zone_01/…)
├── ui/ · art/ · audio/ · autoloads/
```

### Core patterns

**1. Component-based actors.** `HealthComponent`, `Hurtbox` (Area2D), `Hitbox` (Area2D), `KnockbackComponent`, `StateMachine`. An enemy = `CharacterBody2D` + sprite + components + one behavior script. Enemy #7 takes an afternoon, not a week.

**2. Player finite state machine.** States: `Idle`, `Move`, `Attack`, `Dodge`, `Hurt`, `Dead`, `UsingTool`, `Cutscene`. Each its own script with `enter()`, `exit()`, `update()`, `physics_update()`. The `Cutscene` state is what makes the intro tractable — without it you scatter input-disable flags through every other state.

**3. Custom Resources for data.**

```gdscript
class_name EnemyData extends Resource

@export var display_name: String = ""
@export var max_health: int = 10
@export var move_speed: float = 40.0
@export var contact_damage: int = 1
@export var xp_value: int = 5
@export var telegraph_time: float = 0.4
```

Each enemy becomes a `.tres` you tune without touching code.

**4. Autoload event bus.** One `Events.gd` singleton with global signals — `player_died`, `boss_defeated`, `item_acquired`, `xp_gained`. Prevents deep node-path coupling.

**5. Physics layers.** Assign day one; renaming in month six is genuinely painful.

| Layer | Name |
|---|---|
| 1 | World |
| 2 | Player |
| 3 | PlayerHitbox |
| 4 | PlayerHurtbox |
| 5 | Enemy |
| 6 | EnemyHitbox |
| 7 | EnemyHurtbox |
| 8 | Interactable |

### Cutscene sequencer

The intro is ~8 minutes of linear beats. Don't build it from nested timers and signal spaghetti — use a coroutine sequencer on Godot 4's `await`. Reads like a screenplay, editable a year later:

```gdscript
func play_intro() -> void:
    player.state_machine.transition_to("Cutscene")
    await Seq.play_audio("cart_wheels")
    await Seq.wait(15.0)
    await Seq.fade_from_black(2.0)
    await Seq.camera_to(cart_marker, 0.0)
    await Seq.dialogue("intro_cart_01")
    # ...
```

`Seq` is an autoload where each method returns when its effect completes. ~200 lines, pays for itself across all five scripted sequences. Build skip support at the same time, not later.

### Pixel-perfect setup

- **Viewport** 1280×720, **Window** 1280×720
- **Stretch Mode:** `canvas_items` + **Snap 2D Transforms to Pixel**
- **Default Texture Filter:** `Nearest`
- **Snap 2D Vertices to Pixel:** on

### Top-down specifics

- **Y-sorting** on the level root and object `TileMapLayer`; sprite offset so sort origin sits at the feet
- **Use `TileMapLayer`** (Godot 4.3+), not deprecated `TileMap`. Layers: Ground, Objects (y-sorted), Overhead, Collision
- **Camera2D** with smoothing ~5.0, per-room limits via `Area2D` triggers

### Save system

JSON, not `ResourceSaver` — loading arbitrary `.tres` at runtime is a code-execution vector and a versioning headache. Save to `user://save_01.json` on save-point rest and zone transition.

---

## 11. Milestones

| # | Milestone | Deliverable | Est. |
|---|---|---|---|
| **M1** | **Combat prototype** | Grey boxes. Move, attack, dodge. One enemy. **Is it fun?** | 3–4 wks |
| **M2** | **Vertical slice** | One polished room. Final art, sound, hitstop. Intro as text placeholders | 6–8 wks |
| **M3** | Orchardfall complete | Farmland, Warden's Hook, cellmate boss, Ambry v1 | 10–12 wks |
| **M4** | Stillwater complete | Flooded mill, Clearwater Charm, protector boss | 8–10 wks |
| **M5** | Hollowdeep + ending | The sinkhole, final tool, first victim, finale | 8–10 wks |
| **M6** | **Intro sequence** | Full opening, bespoke art, sequencer, skip support | 5–7 wks |
| **M7** | Content complete | Secrets placed, dialogue written, audio in | 4–6 wks |
| **M8** | Polish & ship | Playtesting, balance, options, controller, store page | 6–8 wks |

**Gate at M1:** if combat isn't fun with grey boxes, no amount of pixel art or story will save it. Be willing to spend another month here or change the design. Cheapest possible place to learn the game doesn't work.

---

## 12. Co-op (Stretch Goal — Not Scoped)

Deferred. Nothing in the current design depends on it. If revisited, the intended shape was: **online, host's world, host keeps progress, solo remains first-class** — the Dark Souls summon model, where guests visit and help.

### Architecture insurance

These cost nothing now and prevent a rewrite later. Follow them regardless of whether co-op ever happens; they're good practice anyway.

1. **Never make the player a singleton.** No `Player` autoload, no `Global.player`. Player state lives on the player node; systems receive a reference. This is the big one — a global player reference means retrofitting multiple players is a from-scratch rewrite.
2. **No `get_first_node_in_group("player")` scattered through enemy code.** Enemies ask "who is my nearest valid target?" through one targeting helper.
3. **Isolate input behind a component.** An `InputComponent` producing an intent struct the state machine consumes. The player script never calls `Input.is_action_pressed()` directly.
4. **Keep camera logic out of the player.** A separate rig that follows a target.
5. **Route all combat randomness through one seeded RNG.**

### Known problem if revisited

The frame data in §5 is tuned tighter than naive netcode supports — an 80ms attack windup is shorter than typical network round-trip. Solving it means either separate co-op timing values (cheap) or client-side prediction with reconciliation (4–8 weeks, genuinely hard).

---

## 13. Risk Register

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Building the intro first** | Very high | It's the most fun part to make. §11 schedules it at M6 |
| **Scope creep** | Very high | §2 is a hard ceiling. New ideas go in `sequel.md` |
| **Premise churn after art exists** | Medium | Lock §1 and §3 before M2. Changing them after tilesets exist is expensive |
| **Art becomes the bottleneck** | High | Fixed palette, low frame counts, corruption variants over unique enemies |
| **Motivation collapse in the long middle** | High | M2 gives you something showable. Post progress publicly |
| **Combat isn't fun** | Medium | M1 gate |
| **XP creates permanent tuning debt** | Medium | The four rules in §6. Especially: never scale enemies to level |
| **Audio never gets done** | Medium | Outsource. Budget now |
| **Co-op creeps back in** | Medium | §12 is a stretch goal. Revisit only after M8 ships |

---

## 14. Open Questions

- 🔶 The fox's name (§7)
- 🔶 Does the Beat 8 choice have mechanical consequences or purely narrative ones?
- 🔶 Difficulty options? (Recommend: yes, as accessibility)

See `BUILD-PLAN.md` for the operational M1 plan.

---

## 15. Amendments

This document is a template. Where the build has overridden it, the change is
recorded here rather than silently diverging.

### A1 — Sprite resolution raised to 64×96 (supersedes §8)

**Was:** 320×180 internal, 16×16 tiles, 16×24 character.
**Now:** 1280×720 internal, 64×64 tiles, 64×96 character.

A straight 4× on everything spatial. Framing is unchanged — still 20×11.2 tiles
on screen, still a character 13% of screen height — so nothing about camera
work, encounter spacing or telegraph readability shifts. What changes is pixel
density: a 16×24 character has 384 pixels and room for one flat colour per
material, while 64×96 has 6144 and room for a full shadow/base/highlight/
specular ramp, an iris, cloth folds and separated fingers. That is what makes
individual characters distinguishable at a glance, which the cast in §7 and the
corruption-stage readability rule in §8 both depend on.

**All timings are unchanged.** Frame data is in seconds; only distances and
speeds scaled. Move speed 82→328 px/s, dodge 46→184px, knockback 12–20→48–80px,
shake 2→8px, and every range in `EnemyData` ×4.

**Costs, accepted knowingly:**

- **Art is roughly 4× the pixel work.** §13 already rates "art becomes the
  bottleneck" as High; this raises it. The §2 sprite count is unchanged, the
  hours per sprite are not. Re-baseline the §11 estimates before trusting them.
- **1080p is a 1.5× upscale.** 1280×720 is integer at 720p, 1440p and 4K, but
  1920×1080 is not a whole multiple. At this pixel density the unevenness is
  subtle, and the fix is a standard "integer scaling only" video option that
  letterboxes — worth folding into the §14 difficulty/accessibility options
  question rather than solving now.

### A2 — Palette raised to 64 colours (supersedes §8) — DECIDED

**Was:** 32 colours. **Now:** 64.

32 was chosen when a character had 8 of them. The drawn 64×96 reference uses 21
on its own, which would have left 11 for every environment, every other
character and every effect in the game. At A1's resolution that is not a
discipline, it is a wall.

**The extra 32 are for tones, not hues.** A material at 64×96 wants a four-step
ramp — shadow, base, highlight, specular — where at 16×24 it wanted one flat
colour. That is where the budget goes. It is *not* licence for more distinct
hues, and the rule that does not bend is unchanged:

> Corruption is the one saturated colour. The blight is the only thing that glows.

Doubling the palette doubles the rope. Endesga 64 contains plenty of saturated
colours; most must stay unused or stay at very low coverage, or the luminous
yellow-green stops being the thing the eye goes to, and the antagonist loses the
only screen presence §3 gives it.

Zone slices (§8) go from ~10 colours to ~20 each.

**Superseded by A5** — the fixed palette was dropped entirely. The reasoning
above still explains why the count had to rise; A5 explains why a count was the
wrong instrument.

### A3 — The fox is bipedal (affects §7, §8)

Built on the humanoid rig, standing on two legs, same construction as any other
character. **Body 64×80, frame canvas 128×128** — shorter than a person, same
rig.

**Production:** this is the cheap direction. The humanoid rig now covers the
player, 8 NPCs, the fox and 4 enemies — 14 of the ~47 sprites in §2 — where a
quadruped fox would have been a one-off rig used exactly once, for a character
that has no walk cycle because §7 places it sitting.

**Two things it changes that are worth holding onto:**

- **"Small" is load-bearing.** §7 grounds the fox's credibility in observation,
  not wisdom: *"It goes where people can't: small, unafraid."* If it stands at
  human height that reasoning quietly stops working — it can go exactly where a
  person can. Hence 64×80 rather than the full 64×96: still unmistakably
  smaller, still able to be somewhere a person could not have reached, but on
  the humanoid rig. If it ends up person-height, §7's justification for why it
  knows things needs rewriting.
- **It raises the register.** A normal-looking fox that happens to talk is
  uncanny and charming, and §7 depends on never explaining it: *"The moment it's
  justified it stops being charming and becomes a lore item."* A bipedal fox is
  more overtly fantastical, and the more obviously impossible it looks, the more
  the silence around it has to carry. The rule doesn't change — nobody remarks
  on it, ever — but it is doing more work now.

Everything else in §7 is untouched: player-initiated dialogue only, never
repeats, observes rather than instructs, placed rather than following, and never
harmed.

### A4 — The village is the progression system (supersedes §6, reshapes §7)

**The loop:** go out into a zone, take what you can carry, bring it home, rebuild
part of Ambry, gain something that lets you go further. Repeat, deeper.

This replaces item-gated progression and light XP with a single system, and it
resolves the tools question in §6 by giving them somewhere to come from.

#### The village is the character sheet

Not a hub with shops. The *rebuild state of Ambry is* the player's progression.
Every capability comes from a building brought back:

| Rebuilt | Gives |
|---|---|
| The forge | Weapon damage; later, reach and the third-hit finisher |
| The apothecary | Healing capacity carried into a zone |
| The inn | Supplies per expedition; a bed that restores |
| The wall / gate | Safe passage, opening a route toward the next zone |
| The chapel or archive | Reveals what the blight is doing — map, tracking, the fox's range |

One system instead of two. It also means the player's power is visibly made of
other people's work, which is the story: they condemned you, and their help is
what makes stopping this possible.

**Recommendation: cut XP entirely.** §6's four XP rules existed to stop XP
causing problems — capping levels, never scaling enemies, weighting away from
trash. Deleting XP is the strongest version of all four, removes a tuning
surface, and stops two progression systems competing for the same feeling.
Levels gated nothing anyway.

#### Tools come from the town, not from rooms

The four keys in §6 stop being pickups in an acquisition room. The smith,
rebuilt, makes you the Hook. This costs nothing mechanically and buys a lot:
every traversal unlock becomes evidence of the town's investment in you rather
than loot on a pedestal.

Whether they stay as the four named tools, become survival gear (something that
lets you *endure* a hazard rather than *unlock* a door), or reduce to two is
still open. The delivery mechanism is the decided part.

#### Materials are placed, not dropped

**Hand-placed in the world. Never a drop from a killed enemy.** This is the same
rule §6 already applies to Heart Shards and Whetstones, and it is the single
line between "rebuilding is exploration" and "rebuilding is farming". The moment
a Blighted Villager drops two timber, the optimal play is to kill villagers in a
loop, and the game becomes about the loop instead of the valley.

It also protects §3's asymmetry: nameless enemies are beyond help and killing
them is mercy. Mercy that pays out in construction materials is not mercy.

#### The tension, and the fix

A rebuild loop pulls the player *back* to town. The stated goal is adventure —
travelling through dangerous zones toward the heart. Those fight each other, and
a game that makes you commute is the failure mode.

Three things keep it an expedition:

1. **Long trips, big hauls.** You do not pop home after every room. Carrying
   capacity is limited, so a run ends when you are full or nearly dead, and
   deciding *when to turn back* is the interesting choice.
2. **You can lose the haul.** Die in a zone and what you were carrying stays
   there, recoverable if you can reach it again. This is what makes the walk
   home tense instead of administrative — the adventure extends to the return
   journey, which is otherwise dead time.
3. **Shortcuts, opened from the far side.** Already in the §7 zone template.
   Returning becomes fast only once you have earned it, so the first trip out is
   an expedition and the tenth is a commute *by choice*.

Point 2 is the load-bearing one and the one to prototype first. Without it,
gathering has no risk and the return trip is a chore.

#### The town also un-degrades

§7 has Ambry worsening as the blight advances — more refugees, fewer shops open,
walls further reinforced. Keep that as the *default drift*, and let rebuilding
push against it. The town's state becomes a live readout of whether the player
is winning, in the one location the game has already decided is the emotional
centre. Warmth stops being a backdrop and becomes the score.

#### Scope — read this before starting

This is the largest addition to the design so far, and §2 is a hard ceiling that
does not currently contain it. New systems required:

- A carried-resource type or three, with capacity and loss-on-death
- Rebuild projects: state, costs, and a build interaction
- Per-building unlock effects wired into player capability
- UI for all of the above — the first real UI in the project
- Save state for village progress (the save system already takes this: a
  `village` node joins the `saveable` group and implements three methods)

Two or three resource types, not ten. Six to eight rebuild projects, not twenty.
§2 was written to stop exactly this kind of idea from quietly tripling the
project, and it is still right even though it is being amended.

### A5 — No fixed palette (supersedes §8 and §15 A2)

**Was:** one fixed palette — 32 colours, then 64 — with each zone taking a slice.
**Now:** no global palette. Full colour space, with per-zone discipline.

A2 raised the count to 64 because a 64×96 character needs four tones per
material. That was the right diagnosis and the wrong fix: the real constraint
was never the number, it was that four zones and a hub were being asked to share
one set. Dropping the ceiling gives each location its own range instead of a
slice of somebody else's.

It also settles the icon question. The uploaded item set uses 532 colours across
39 icons; re-indexing to any fixed palette would have flattened the gemstones for
no benefit, since icons sit in a UI panel and are not competing with anything in
the world.

**What the palette was silently doing, that now needs doing on purpose:**

1. **Guaranteeing the blight owns its colour.** This is the one that matters.
   §3 gives the antagonist no voice, no face and no motive — its only screen
   presence is environmental, and it is carried almost entirely by one luminous
   yellow-green. With a fixed palette, nothing else could be that colour because
   the colour did not exist twice. Now anything can be, so it is checked:
   `tools/check_colour.py` reserves hue 60–100° above 55% saturation and fails
   on any world asset that claims it. Small highlights are tolerated; a glow is
   not.

2. **Guaranteeing zones read as different places.** Previously free, because
   each zone got a different slice. Now it has to be looked at. The same tool
   prints per-directory hue and saturation profiles, and `--map` plots hue
   against saturation so two zones converging is visible rather than
   discovered late.

**Zone identity is now stated as intent, not as a slice:**

| Zone | Range |
|---|---|
| Ambry | warm — amber, ochre, cream, ember. The only warm location |
| Orchardfall | that warmth sickened — yellow-green tending grey-brown |
| Stillwater | cold — blue-grey, teal, black water |
| Hollowdeep | near-monochrome, tightly narrowed |

Give each zone its own working palette in the art tool. They are no longer
required to be subsets of anything, only to be recognisably unlike each other.

**Still true, and now the only hard rule:** corruption is the one saturated
colour. Everything else muted. The blight is the only thing that glows.

### A6 — Ambry, in two halves (extends §7 and §15 A4; amends §2)

**Was:** one village, a stockpile in the square to bank hauls into, a "wall"
project that pushed the blight edge back as a number, nine NPCs.
**Now:** twenty locations across two districts, storage in a house you build,
the wall as a district unlock, and a tenth NPC. See `docs/AMBRY.md`.

Four changes, each with a reason:

1. **The player rebuilds their own home, and it is the first build.** The
   magistrate put a derelict's deed in their name and never mentioned it —
   which is his §7 characterisation exactly, and it ties the first mechanical
   lesson to the most loaded relationship in the cast. It is cheap (timber from
   just outside the gate), it is the only build anyone explains, and the payoff
   is a room the player uses for the rest of the game.

2. **Storage moves into the home, and there is none before it.** The stockpile
   in the square is gone. Until the home exists the satchel is all the player
   has, which is what makes the first build worth making and the first zone run
   genuinely all-or-nothing. The save point moves with it: the inn's made bed
   first, your own bed after.

3. **The wall is a gate, not a stat.** Repairing the breach opens a sealed
   northern district — the graves, the archive, the old shrine, a second road
   out — rather than decrementing a blight counter. It is the most expensive
   project and the largest payoff, and it puts one project (the archive) behind
   another, which gives the rebuild loop a shape instead of a shopping list.

4. **§2's cast goes 9 → 10.** The carpenter. He stands at whatever can be built
   next, which is a quest marker with no quest log attached. One more speaking
   role is a real cost against §2's budget; the alternative was teaching the
   game's central mechanic through a menu.

**What this does not change:** eight projects remains the ceiling (A4), three
material types remains the cap, and the gallows remains the project that costs
materials and grants nothing.

### A7 — The village modifies real stats (amends §15 A4)

**Was (A4):** the rebuild state of Ambry *is* the character sheet. No numbers —
your capabilities were buildings, and there was nothing else to show.
**Now:** the player has real stats, and the projects move them.

This reverses the most distinctive claim A4 made, so it is worth being honest
about the trade rather than pretending it is a refinement.

**What A4 was protecting.** "The village is your character sheet" meant the
rebuild loop could never degrade into a shop that sells stat points — because
there were no stat points. Every capability was a place, and a place is
authored, sited and reacted to by the people who live there. That is still the
best idea in the document.

**Why it gave.** A4 left the player with nothing to look at and nothing to feel
progress against between projects, and projects are expensive — a full satchel
each for the high-cost ones. Eight discrete jumps across a campaign is very
coarse pacing, and there was no way to answer "am I stronger than I was" except
by remembering which buildings are standing. It also made a character screen
impossible to write, which is a symptom rather than a cause but a telling one.

**The rule that keeps A4's intent alive:** every stat modifier has a **named
source**, and every source is a building. Nothing raises a number without
something in Ambry standing that did not stand before. There are no points to
spend and no way to increase a stat that is not "go and rebuild the thing". The
village is no longer the sheet — it is the only thing that writes to it.

| Stat | Moved by |
|---|---|
| Strike damage, then reach | The forge |
| Carry capacity | The market |
| Health | The apothecary, and heart shards |
| Departure speed / safety | The watchpost |

**The test that keeps it honest:** a stat with a modifier from no building is a
bug. If a number ever moves for a reason the player cannot walk to and look at,
A4 has been abandoned rather than amended, and this section is the record of
what that would cost.

### A8 — There is XP, and it buys nothing (amends A7)

**Was (A7):** "there is no XP, no level". **Now:** there is. The HUD carries a
thin bar under health, gold as it fills, silent until pointed at.

A7 wrote that line while arguing against stat points, and it overshot — it
banned the *counter* along with the *shop*. Those are separable, and separating
them is the whole of this amendment:

- **A level grants nothing.** `ExperienceComponent` emits `player_leveled` and
  stops. Every stat still comes from `StatsComponent`, still carries the id of
  the building that granted it, and is still refused without one.
- **So the bar answers "how far along am I", not "what did I earn".** The
  answer to the second question is still a walk through Ambry looking at what
  is standing.

Kills fill it — `EnemyData.xp_value`, which had been sitting unread since M1.
What a level is eventually *for* is deliberately unanswered; the honest options
are a title, a story beat, or a gate on which projects Ambry will attempt. What
it must not become is a stat, and `_test_experience` asserts exactly that, so
the day someone adds the convenient exception the suite says so.

**The risk, stated plainly:** a progress bar that pays out nothing is a bar
players will eventually resent. This is a placeholder for a decision, not the
decision.

### A10 — A level buys a skill point (amends A8)

**Was (A8):** "a level grants nothing", with `_test_experience` asserting it.
**Now:** a level grants one point, and points buy skills.

A8 named the risk it was taking in the same breath as the rule: *"a progress
bar that pays out nothing is a bar players will eventually resent. This is a
placeholder for a decision, not the decision."* This is the decision, so the
guard it left behind is retired rather than worked around — the test now asserts
the new rule instead of being deleted.

**What survives from A7, and it is the part that mattered:** nothing moves a
number anonymously. Skills write to `StatsComponent` under `skill:<id>`, exactly
as buildings write under their building id and gear writes under its slot. Every
number on the character sheet can still name what granted it, and a refund
removes precisely what it added.

**What is given up, stated plainly:** the village is no longer the *only* thing
that raises a stat. It is still the majority of them — six skills against eight
projects — and it remains the only source of **capabilities**. A player who
never rebuilds anything still cannot open the north gate, still has no map, and
still has no forge. The town is the progression; skills are the seasoning.

**Six skills, three branches, two deep.** Blade (damage, then reach), Body
(a heart, then carry), Wind (stamina, then recovery). Small on purpose: six
choices a player can hold in their head beats twenty they scroll past, and every
modifier is a stat that already exists and is already tested.

### A9 — Equipment exists, and it names itself (amends A7)

**Was (A7):** every stat modifier carries the id of the **building** that
granted it, and the village is the only thing that writes to a number.
**Now:** worn gear writes stats too, under a source named for the slot.

Three slots and no more: a **weapon**, a piece of **armour**, and which of the
four keys is in your hand. The tool slot is already §6's design; the other two
are new, and §2 says nothing about equipment, so this is an addition to the
scope contract rather than an interpretation of it. A wardrobe — helm, chest,
gloves, boots, two rings — is a §2 conversation and the answer is no.

**What survives from A7, and it is the part that mattered:** nothing moves a
number anonymously. `StatsComponent.apply()` still refuses a modifier with no
source, and the player can still point at exactly what is doing it. What gave is
the "and every source is a building" clause.

**Sources are named for the slot, not the item.** Keyed by item, swapping one
sword for another would apply the new one and leave the old one's bonus in place
forever — which does not read as a bug, it reads as the second sword being
unusually good. Keyed by slot, equipping replaces, which is what equipping
means. `_test_equipment` asserts it.

**The player starts with a worn sword.** §4 hands them nothing — the opening is
an escape from an execution — but the opening is M6 work, and until it exists an
unarmed character cannot test the combat the whole of M1 is about. It is one
line in `player.tscn` when the intro lands.

**The risk, stated plainly:** equipment is the standard way an RPG's numbers
stop meaning anything, because it is the easiest content to add. A4's whole
point was that capability is a *place you rebuilt*, and every stat that comes
from a sword instead is one the village did not give you. Three slots is the
brake. If it ever needs a fourth, that is the moment to reread A4.

---

*Living document. Revisit §2 monthly.*
