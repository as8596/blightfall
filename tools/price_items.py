#!/usr/bin/env python3
"""Write a `value` into every item def.

    python3 tools/price_items.py [--check]

Prices are **derived**, not typed. Thirty-four hand-picked numbers are thirty-four
chances to make a fish worth more than the sword, and no amount of care survives
the thirty-fifth item being added six weeks later. So a price comes from what an
item *does*, through one rate per category, and re-running this after a balance
change re-prices everything that change touched.

`--check` prints what would change and writes nothing; the smoke test uses it to
catch a def whose price no longer matches its effect.

## The scale

A heart is the unit. Everything a consumable is worth is a multiple of what one
heart of healing costs, and the category decides the rate:

- **Fish** are the cheap end because you catch them. They are what the player
  *sells*, so the rate is low enough that fishing is pocket money and not an
  income that replaces expeditions.
- **Meals** cost what somebody's work costs.
- **Medicine** is dearest per heart, and should be: it is the thing you reach
  for mid-fight, and paying over the odds for reliability is the trade.

Gear is priced from its modifiers instead, since it heals nothing. Movement is
scored at a lower weight than damage or health because a boot's speed number is
large and its effect is not — the rate is what keeps a 12-point boot from
out-pricing the sword.

## What is deliberately worth nothing

Keys. `ItemData.is_tradeable()` refuses a zero, so a key cannot be sold at all —
by construction, rather than by a confirmation dialog nobody reads. Selling the
thing that opens a door is a soft lock with a coin attached.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFS = os.path.join(ROOT, "resources", "items", "defs")

# Gold per heart restored, by what the thing is.
FISH = 4
MEAL = 9
MEDICINE = 14

# Anything not listed is a meal. Being wrong about a category costs a few gold;
# being wrong about the default costs nothing at all, because the default is the
# middle rate.
CATEGORY = {
    "bass": FISH, "brook_trout": FISH, "carp": FISH, "catfish": FISH,
    "crappie": FISH, "grayling": FISH, "perch": FISH, "river_trout": FISH,
    "sunfish": FISH, "walleye": FISH,
    "salve": MEDICINE, "tonic": MEDICINE, "elixir": MEDICINE,
    # Foraged rather than cooked. Cheap, and the first thing a player sells.
    "honey": FISH, "bread": FISH,
}

# What a point of each stat is worth. Move speed is scored low on purpose: the
# numbers on a boot are an order of magnitude bigger than the numbers on a
# sword, and at an equal rate a pair of riding boots would be worth more than
# every weapon in the game.
STAT_VALUE = {
    "damage": 60,
    "max_health": 45,
    "stamina": 30,
    "move_speed": 3,
    "reach": 4,
    "stamina_regen": 2,
}

# A floor, so a modifier the table has never heard of still prices somewhere
# sane rather than at zero — which would silently make it unsellable.
GEAR_FLOOR = 20

KIND_CONSUMABLE, KIND_TOOL, KIND_KEY, KIND_GEAR = 0, 1, 2, 3


def field(text, name, default=""):
    hit = re.search(r"^%s = (.*)$" % re.escape(name), text, re.M)
    return hit.group(1).strip() if hit else default


def modifiers_of(text):
    """The {stat: n} block, whether it was written inline or across lines."""
    hit = re.search(r"^modifiers = \{(.*?)\}", text, re.M | re.S)
    if not hit:
        return {}
    return {m.group(1): int(m.group(2))
            for m in re.finditer(r'&"(\w+)"\s*:\s*(-?\d+)', hit.group(1))}


def price_of(item_id, text):
    kind = int(field(text, "kind", "0") or 0)
    if kind == KIND_KEY:
        return 0
    if kind == KIND_GEAR:
        # Negative modifiers are a real cost and are allowed to pull the price
        # down — a hood that slows you is worth less than one that does not.
        total = sum(STAT_VALUE.get(stat, 10) * n
                    for stat, n in modifiers_of(text).items())
        return max(int(total), GEAR_FLOOR)
    if kind == KIND_TOOL:
        return 40
    heals = int(field(text, "heals", "0") or 0)
    if heals <= 0:
        return 0
    # Superlinear: one slot doing three hearts of work is worth more than three
    # slots doing one, and the pack is the scarce thing.
    return int(round(CATEGORY.get(item_id, MEAL) * heals * (1.0 + 0.15 * (heals - 1))))


def main() -> None:
    check = "--check" in sys.argv
    changed, listed = 0, []
    for name in sorted(os.listdir(DEFS)):
        if not name.endswith(".tres"):
            continue
        path = os.path.join(DEFS, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        item_id = field(text, "id").strip('&"')
        want = price_of(item_id, text)
        have = field(text, "value")
        if have != "" and int(have) == want:
            continue
        changed += 1
        listed.append("  %-20s %s -> %d" % (item_id, have or "unset", want))
        if check:
            continue
        if have != "":
            text = re.sub(r"^value = .*$", "value = %d" % want, text, flags=re.M)
        else:
            # After stack_size, which is where the export sits in the class, so
            # a diff of the .tres reads in the same order as the script.
            text = re.sub(r"^(stack_size = .*)$", r"\1\nvalue = %d" % want,
                          text, flags=re.M)
            if "\nvalue = " not in text:
                text = re.sub(r"^(kind = .*)$", r"\1\nvalue = %d" % want,
                              text, flags=re.M)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    print("\n".join(listed) if listed else "  every price already matches")
    if check and changed:
        print("%d out of date. Run tools/price_items.py." % changed)
        sys.exit(1)
    print("%d priced." % changed)


if __name__ == "__main__":
    main()
