# Ambry — locations and points of interest

The hub. Everything here serves three jobs at once, and a POI that serves none
of them shouldn't exist:

1. **Warmth.** The zones are grim; this is the refuge. The player's body should
   register safety before they read a word (GDD §7).
2. **Progression.** The rebuild state of Ambry *is* the character sheet
   (GDD §15 A4). Every capability comes from a building brought back.
3. **The return.** It is where a haul stops being at risk. That is the whole
   emotional payload of walking home with a full satchel.

---

## The shape of the town

```
                    N  ── the blight, always visible from the square
        ┌───────────────────────────────────┐
        │  graves          .          .     │
        │   ┌────────┐  ┌──────────┐        │
        │   │APOTHEC.│  │MAGISTRATE│  │CHAPEL│
        │   │ ruined │  │   hall   │  │ruined│
        │   └────────┘  └──────────┘  └──────┘
        │                                   │
        │  ┌────┐      ╔═══════════╗   ┌────┐
        │  │INN │      ║  SQUARE   ║   │FORGE│
        │  │    │      ║ well hearth║  │     │
        │  └────┘      ║ stockpile ║   └────┘
        │              ╚═══════════╝        │
        │  ┌──────┐   ┌─────────┐    ┌──────┐
        │  │MARKET│   │ hidden  │    │WATCH-│
        │  │empty │   │  case   │    │POST  │
        │  └──────┘   └─────────┘    └──────┘
        │              ▓ GALLOWS ▓          │
        └──────────────┤  GATE   ├──────────┘
                    S  └─────────┘  ── to the valley
```

Three things about this are load-bearing:

**The gate is south and the blight is north.** You always arrive from the valley
with the thing you're fighting on the far side of town, visible over the
rooftops from the square. The one place that's meant to feel safe never quite
lets you forget.

**The square is on the way, not off it.** Walking from the gate to anywhere
takes you past the hearth, the well and the stockpile. The warmth pillar wants a
place the player returns to without being sent.

**The gallows stands between the gate and the town.** You pass it going out and
coming back, every single run. Nobody made you look at it; it's just where the
road goes.

---

## Functional POIs

Permanent. Never rebuilt, never lost.

| POI | What the player does | Why it exists |
|---|---|---|
| **The gate** | Leave for the valley; return | The only exit. One threshold, so leaving is always a decision |
| **The hearth** | Rest: save, restore health | The save point. Light is hearths, not glare |
| **The stockpile** | Bank the haul — deposit materials | Where a haul stops being at risk. The exhale at the end of a run |
| **The well** | Nothing, mechanically | Where the child plays. Domesticity persisting |

**Hearth and stockpile sit together** on purpose. Banking and saving are one
trip, one animation, one exhale — a run should end in a single gesture rather
than a lap of errands.

---

## Rebuild projects

Seven. The progression system (GDD §15 A4). Each is a plot you walk to and
build at — no menu, no board; you stand where the thing will be.

| Project | Start state | Gives | Cost weight |
|---|---|---|---|
| **The apothecary** | ruined | Healing you can carry *into* a zone | low |
| **The archive** (chapel) | ruined | Reveals blight spread; extends the fox's range | medium |
| **The market** | empty plot | Convert materials between types; buy supplies | medium |
| **The watchpost** | empty plot | The road out is guarded — safer, faster departures | medium |
| **The wall** | damaged | Pushes the blight edge back. The north tiles visibly recede | high |
| **The forge** | standing, cold | Weapon damage, then reach | high |
| **The gallows** | standing | **Nothing** | low |

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

### Costs

Two or three material types, not ten (A4). Suggested:

- **Timber** — common, from Orchardfall
- **Stone** — common, from Stillwater's drowned buildings
- **Ironwork** — scarce, salvaged, gates the high-cost projects

The wall and the forge should each want a full satchel's worth, so they read as
expeditions rather than errands.

---

## Narrative POIs

No service. They exist because the town has to have a history you can stand in.

| POI | What's there |
|---|---|
| **The magistrate's hall** | The ledger your name was wrongly on. Still open on the desk |
| **The graves** | North edge, nearest the blight. The Liar is here. So is whoever the town lost most recently — the list grows if you're slow |
| **The hidden case's house** | Door shut, curtain drawn. Nothing to interact with for most of the game, and that *is* the interaction |
| **The fox's spot** | On the well's edge. Player-initiated only; never interrupts (GDD §7) |

The graves growing over time is the cheapest possible pressure mechanic: no
timer, no fail state, just a list that gets longer if the player takes their
time. It costs one array and one line of dialogue per entry.

---

## Where the cast stands

Nine NPCs (§2 budget), each anchored to a POI so the player learns the town by
learning where people are.

| NPC | Anchor | Warmth expressed as |
|---|---|---|
| The magistrate | His hall | Doing things for you unasked, never mentioning it |
| The smith | The forge | Work. Refuses payment, changes the subject |
| The innkeeper | The inn | A made bed and hot food, every time |
| The child | The well | Treating you as ordinary |
| The apothecary | **The inn**, until her building is rebuilt | Taking you seriously |
| The reluctant guard | The gate | Practical protection |
| The unrepentant | The gallows | None — and that's the point |
| The hidden case | Their own doorway | Warmth curdling into dread |
| The fox | The well's edge | Unambiguous gentleness |

**The apothecary works out of the inn** until you rebuild her shop. It costs
nothing to author, and it means rebuilding visibly *moves a person* rather than
unlocking a menu — which is the difference between a village and a hub.

---

## How the town changes

Two forces, opposed. This is what makes Ambry a readout rather than a backdrop.

**Drift (down).** §7's original design: after each zone, more refugees, fewer
shops open, walls further reinforced against something that keeps getting
closer. This happens on its own.

**Rebuild (up).** The player pushes back, one project at a time.

The same handful of NPCs get *more* screen time as things worsen, not less.
Nobody thanks the player until late — earned gratitude lands, free gratitude is
noise.

### States per POI

Three is enough for everything:

| State | Reads as |
|---|---|
| `ruined` | Walkable rubble. You can stand in it and be told what used to be here |
| `plot` | Marked, cleared, waiting. Someone believes it's worth rebuilding |
| `built` | Standing, lit, occupied |

`ruined → plot` should be a real step for the two lost buildings. Clearing the
apothecary before rebuilding it is one extra beat that makes the rebuild feel
like labour rather than a purchase.

---

## Build status

| | State |
|---|---|
| Layout, tiles, collision | **Built** — `levels/ambry/ambry.tscn` |
| Building plots as markers with id + state | **Built** — `Level.building_plots()` |
| NPC markers | **Built** — `Level.npc_markers()`, all nine placed |
| Stockpile, gallows, graves, fox spot | **Not placed** — this document's additions |
| Interact verb | **Not built.** Blocks every POI that isn't walked over |
| Rebuild transaction (spend → change state) | **Not built** |
| Dialogue | **Not built.** NPCs are markers |
| Village state in saves | **Not built** — the save system takes it with no changes; a `village` node joins the `saveable` group |

**The interact verb is the bottleneck.** Talking, building, resting, banking and
reading the ledger are all the same button, and none of them exist. It is small,
and it unblocks everything above.
