# Ambry — locations and points of interest

The hub. Everything here serves three jobs at once, and a POI that serves none
of them shouldn't exist:

1. **Warmth.** The zones are grim; this is the refuge. The player's body should
   register safety before they read a word (GDD §7).
2. **Progression.** The rebuild state of Ambry *is* the character sheet
   (GDD §15 A4). Every capability comes from a building brought back.
3. **The return.** It is where a haul stops being at risk. That is the whole
   emotional payload of walking home with a full satchel.

Twenty locations, across two districts. **South is where you start. North is
what you earn.**

---

## The shape of the town

```
 N ███ the blight ███                        ← 48 × 42 tiles
   ┌──────────────────── north road ↗ ──────────────────┐
   │  NORTH DISTRICT — sealed                           │
   │    graves      ARCHIVE (ruin)          old shrine  │
   │                                    creep, unpushed │
   ╞════════════════ THE WALL ══╣breach╠════════════════╡  ← rebuild #5
   │  SOUTH DISTRICT — open           material piles    │
   │    APOTHECARY (ruin)   allotment      MAGISTRATE   │
   │                                                    │
   │    YOUR HOME       ╔═════════════╗                 │
   │    (derelict)      ║ bell   well ║  lean-  FORGE   │
   │                    ║   hearth    ║   tos            │
   │    INN    MARKET   ╚═════════════╝  hidden  WATCH- │
   │           (plot)                     case   POST   │
   │                        ▓ gallows ▓                 │
   └──────────────────────┤  GATE  ├────────────────────┘
 S                      to the valley
```

Four things about this are load-bearing:

**The gate is south and the blight is north.** You always arrive from the valley
with the thing you're fighting on the far side of town. The one place that's
meant to feel safe never quite lets you forget.

**The wall is a gate, not a stat.** Ambry lost its northern half early. The
breach was packed with rubble and everything behind it abandoned. Repairing it
does not abstractly "push the blight back" — it opens a district, and that is
why it is the most expensive project in the game.

**The square is on the way, not off it.** Walking from the gate to anywhere
takes you between the well and the hearth. The warmth pillar wants a place the
player returns to without being sent.

**The gallows stands between the gate and the town.** You pass it going out and
coming back, every single run. Nobody made you look at it; it's just where the
road goes.

---

## The twenty

### South district — open from the start (15)

| POI | What the player does |
|---|---|
| **The south gate** | Leave for the valley; return. One threshold, so leaving is a decision |
| **The gallows** | Nothing, for a long time. Then a choice — see below |
| **Your home** ⭐ | **The first build.** Chest and bed. Interior |
| **The inn** | Sleep here until your home is yours. Interior |
| **The forge** | Weapon damage, then reach. Interior |
| **The magistrate's hall** | The ledger your name was wrongly on. Interior |
| **The well** | Nothing, mechanically. Where the child plays and the fox sits |
| **The hearth** | The town's fire. Social, not mechanical |
| **The bell** | Rang three times the morning they nearly hanged you (GDD §4, beat 0) |
| **The apothecary** | Ruined → rebuild. Healing you can carry *into* a zone |
| **The market** | Empty plot → rebuild. Convert materials; buy supplies |
| **The watchpost** | Empty plot → rebuild. Safer, faster departures |
| **The hidden case's house** | Door shut, curtain drawn. Not interacting *is* the interaction |
| **The allotment** | Kitchen garden. Where the food comes from |
| **The refugee lean-tos** | Grows after each zone. The visible cost of losing |

### North district — behind the wall (5)

| POI | What the player does |
|---|---|
| **The breach** ⭐ | **The unlock.** Worked on from the south side; counted here because it is what opens the rest |
| **The graves** | The Liar is buried here. You could not reach him before |
| **The archive** (old chapel) | Ruined → rebuild. Blight tracking; extends the fox's range |
| **The old shrine** | Older than the town. Pre-blight. The fox relocates here |
| **The north road** | A second way out, and a shorter one to Orchardfall |

---

## Your home — the tutorial build

### Why you have one

**The magistrate put a derelict's deed in your name and never mentioned it.**

That is exactly his characterisation (GDD §7: *doing things for you unasked,
never mentioning it*), and it ties the game's first mechanical lesson to its
most loaded relationship. You don't learn it from him — you learn it from the
carpenter, who was told to expect you and assumes you already knew.

### Why it teaches well

- **Cheap.** A handful of timber, gathered just outside the south gate. No zone
  run required, so the lesson lands before the player has anything to lose.
- **Guided.** The carpenter walks you through it. This is the *only* build
  anyone explains; every one after it, you do alone.
- **Immediate, personal payoff.** A chest and a bed, both of which you use for
  the rest of the game.

### What it changes

| | Before the home | After |
|---|---|---|
| Save / rest | The inn — the innkeeper's made bed | Your own bed |
| Storage | **None.** The satchel is all you have | The chest |

**Having no storage at all before the home is the point.** It is the reason to
build, it makes the payoff concrete, and it means the first zone run is
genuinely all-or-nothing in a way nothing later is.

Sleeping at the inn first also gives the innkeeper her best beat — a made bed
and hot food, every time — and gives the home a second payoff: you stop
imposing on her.

### The carpenter

A tenth NPC (GDD §15 A6 amends §2's cast of nine). **He stands at whatever you
can build next**, which makes him the quest marker without a quest log: you
learn where to go by noticing where he is, and when there is nothing to build
he is back at your house doing something unnecessary to it.

---

## Rebuild projects — eight

A4's ceiling. Each is a plot you walk to and build at — no menu, no board; you
stand where the thing will be.

| # | Project | Start state | Gives | Cost |
|---|---|---|---|---|
| 1 | **Your home** | derelict | Chest and bed. Teaches the mechanic | trivial |
| 2 | The apothecary | ruined | Healing carried into a zone | low |
| 3 | The market | plot | Convert materials; buy supplies | medium |
| 4 | The watchpost | plot | Safer, faster departures | medium |
| 5 | **The north wall** | breached | **Opens the north district** | high |
| 6 | The archive | ruined | Blight tracking; extends the fox's range | medium — *needs 5* |
| 7 | The forge | cold | Weapon damage, then reach | high |
| 8 | The gallows | standing | **Nothing** | low |

Materials stay at three types — **timber**, **stone**, **ironwork** — with
ironwork scarce and gating #5 and #7. A second weight axis would turn the haul
into arithmetic (see `InventoryComponent`).

### The wall is the mid-game

The payoff is the largest in the game: four POIs become reachable, a second
route out shortens the trip to Orchardfall, and the creep along the north edge
visibly recedes. It also puts one project behind another, which gives the
rebuild system a shape beyond a flat shopping list.

### The gallows is the important one

It costs materials and gives no mechanical benefit at all. What it gives is the
town's reaction.

You were sentenced on it. It is still standing when you come back, because
nobody in Ambry has been able to decide what to do about it. Dismantling it is
optional, cheap, and contested — **the unrepentant objects**, on the grounds
that the danger was real and the sentence was lawful. He isn't entirely wrong,
which is the point. The magistrate says nothing either way, which is worse.

Every other project makes you stronger. This one is the only one that is purely
about what the town is, and it's the reason the rebuild loop is a story rather
than a shop.

**Design note:** if the player never dismantles it, that has to be as readable
an ending as dismantling it. It is not a good/evil switch, and nothing should
score it.

---

## Where the cast stands — ten

| NPC | Anchor | Warmth expressed as |
|---|---|---|
| **The carpenter** | Wherever the next build is | Showing up, and assuming you knew |
| The magistrate | Inside his hall | Doing things for you unasked, never mentioning it |
| The smith | Inside the forge | Work. Refuses payment, changes the subject |
| The innkeeper | Inside the inn | A made bed and hot food, every time |
| The apothecary | Inside the inn, until #2 is rebuilt | Taking you seriously |
| The child | The well | Treating you as ordinary |
| The reluctant guard | The gate | Practical protection |
| The unrepentant | The gallows | None — and that's the point |
| The hidden case | Their own doorway | Warmth curdling into dread |
| The fox | The well's edge → **the old shrine** once the north opens | Unambiguous gentleness |

**The apothecary works out of the inn** until you rebuild her shop, which means
rebuilding visibly *moves a person* rather than unlocking a menu — the
difference between a village and a hub.

Four of the cast are indoors, so the square has fewer bodies in it than it used
to. If that reads as empty, the answer is mute idle villagers: §2 caps NPCs with
*dialogue*, not people.

---

## How the town changes

Two forces, opposed. This is what makes Ambry a readout rather than a backdrop.

**Drift (down).** §7's original design: after each zone, more refugees, fewer
shops open, walls further reinforced against something that keeps getting
closer. This happens on its own — the lean-tos and the graves are both arrays
that grow.

**Rebuild (up).** The player pushes back, one project at a time.

The same handful of NPCs get *more* screen time as things worsen, not less.
Nobody thanks the player until late — earned gratitude lands, free gratitude is
noise.

### States per POI

| State | Reads as |
|---|---|
| `ruined` | Walkable rubble. You can stand in it and be told what used to be here |
| `plot` | Marked, cleared, waiting. Someone believes it's worth rebuilding |
| `derelict` | Four walls and a door frame, no roof. Only your home starts here |
| `built` | Standing, lit, occupied |

`derelict` exists so the first build is a building you *finish* rather than a
plot you conjure. That is most of the difference between "your home" and "a
construction site".

---

## Interiors

Four rooms: `levels/ambry/interiors/{home,inn,forge,magistrate_hall}.tscn`, each
wrapped by a `*_level.tscn` that composes it with a player and a camera exactly
the way `ambry_level.tscn` does.

Doors are **pressed, not walked through**, behind a 0.22s fade. They were
contact-triggered at first, on the reasoning that a button press hundreds of
times a run is a tax — and that was right up until the transition acquired a
fade. A door that blanks the screen and moves you somewhere must never fire
because you brushed past it on the way to the square. Once there is a fade, the
deliberate press *is* the safety rather than the tax.

**The door tile is solid.** A door you can walk through makes the interact verb
decoration and every building open — so the tile collides, and the assertions
check that the *doorstep* is reachable rather than the doorway itself.

`world/doorway.gd` extends `world/interactable.gd` and carries the run across
the threshold using `SaveGame.capture()` / `apply()`, so walking into the inn
with a full satchel and walking out empty is a bug that cannot happen quietly.

Three orderings inside it are load-bearing and all three have tests:

- The screen goes **fully black before anything moves**, and only lifts a frame
  after the camera has snapped to the arrived player. Without that last frame,
  the first thing the player sees is the camera still sliding into place.

- The carried payload includes the player's **position**, so it has to be
  applied *before* the level places them, or every door drops you back where you
  were standing in the scene you just left.
- The scene change is **deferred out of the physics callback**. Swapping scenes
  frees the collision objects the `body_entered` callback is running inside, and
  the engine's refusal to do that is a warning, not a crash — the damage would
  be a doorway that works nine times out of ten.

The home's interior is authored in its **finished** state. Showing the derelict
version until it is built belongs with the rebuild transaction, which does not
exist yet.

---

## Draw order

Three layers, and the rule that makes them work:

| Layer | z_index | |
|---|---|---|
| Ground | −1 | grass, roads, floors. Never in front of anything |
| Objects | **0** | walls, props, and **the same z_index as the player**. Y-sorted |
| Overhead | 1 | above everything, no collision. Currently empty |

**Objects has to share the player's z_index.** Godot checks `z_index` before it
y-sorts, so a props layer one above the player draws over them from every
position — walk up to a wall and you vanish behind it entirely. It looks like a
sprite or camera bug and is neither. The smoke test pins all three values.

Tile `y_sort_origin` is deliberately left at the default (the tile's centre).
Moving it to the tile's base is tempting and wrong: a tile at row N would then
sort at exactly the feet of a player standing on row N+1 — the one position
players actually occupy when walking along a wall — and ties resolve by tree
order, so it would work by accident rather than by rule.

**Overhead is empty on purpose.** It used to carry a roof eave, one row above
each building's north wall, and for most buildings that row is walkable ground:
the inn's landed on the ring road, and walking past it erased the player from
the waist down. An eave you can walk under is a good effect, but it has to fade
when something is beneath it — a shader and a proximity test, not a tile. The
build script now refuses to place anything opaque over a walkable cell.

---

## Build status

| | State |
|---|---|
| Layout, tiles, collision | **Built** — `levels/ambry/ambry.tscn`, 48×42 |
| Two districts, north sealed | **Built** — asserted both ways in `tools/build_greybox.gd` |
| Building plots with id, state, district, project cost | **Built** — `Level.building_plots()` |
| POIs and NPC markers | **Built** — `Level.points_of_interest()`, `npc_markers()`, all ten placed |
| Four interiors, doors that work both ways | **Built** — `world/doorway.gd`, `tests/doorway_test.tscn` |
| Interact verb | **Built** — `world/interactable.gd`, `actors/components/interactor_component.gd`, bound to E |
| Fade transitions | **Built** — `autoloads/screen_fade.gd`, `autoloads/transition.gd` |
| Dying | **Built** — reloads the last save, or restarts the level if there isn't one |
| Prompts on anything but doors | **Not built.** The base class is there; nothing else uses it yet |
| Rebuild transaction (spend → change state) | **Not built** |
| Dialogue | **Not built.** NPCs are markers |
| Village state in saves | **Not built** — the save system takes it with no changes; a `village` node joins the `saveable` group |

**The interact verb exists now, and doors are its first user.** Talking,
building, resting, opening the chest and reading the ledger are the same button
and the same base class — `Interactable`, with `can_interact()` and
`interact()` to override. Each of those is now its own small piece of work
rather than all of them waiting on one missing verb.

The bottleneck moved: **the haul loop has no source and no sink.** No `Pickup`
is placed in any level, and nothing reads `building_plots()` outside the tests,
so the satchel can be neither filled nor spent. Closing that — gather outside
the gate, carry back, build your home — is the slice that actually tests A4.

### What the build script asserts

`godot --headless --path . --script res://tools/build_greybox.gd` refuses to
write a village that fails any of these:

- every solid tile in the atlas has a collision polygon
- the atlas is big enough for the tile list (a stale import silently drops the
  last row)
- the spine from the gate is clear
- every south door and POI is reachable on foot from the spawn
- the north district is **not** reachable — and **is**, once the breach is
  opened
- nothing on the Overhead layer sits over ground the player can stand on

The last two matter because a village that fails them looks completely correct
in a screenshot. So did the one whose walls had no collision at all.
