extends Node
## Global event bus (GDD §10, core pattern 4).
##
## Systems that are far apart in the tree talk through here instead of through
## node paths. Nothing in this file holds a reference to an actor — in
## particular there is no `player` property, because that would be a player
## singleton (GDD §12, rule 1).

## Emitted by the player's HealthComponent when it hits zero.
signal player_died(player: Node)

## Emitted whenever the player's health changes. UI listens; nothing else should.
signal player_health_changed(current: int, max_health: int)

## Emitted whenever the player's stamina changes.
signal player_stamina_changed(current: float, max_stamina: float)

## Emitted after an enemy's death animation starts.
signal enemy_died(enemy: Node)

## Emitted by a Hitbox the moment it connects, before hitstop is applied.
signal hit_landed(attacker: Node, target: Node, damage: int)

## The player's satchel changed. Carries totals rather than a delta, because
## every listener wants "how full am I", not "what just happened".
signal player_inventory_changed(carried: int, capacity: int)

## The player's carried items changed — contents, counts, or which slot.
signal player_items_changed(items: Array, counts: Array)

## Everything a character sheet needs, as one dictionary. Pushed rather than
## fetched: the moment a UI panel knows how to find the player, so does
## everything else (GDD §12 rule 1).
signal player_stats_changed(stats: Dictionary)

## Progress toward the next level: points into this level, points it needs, and
## the level itself.
signal player_xp_changed(current: int, needed: int, level: int)

## A level was just crossed. Nothing grants a stat off this — the village does
## that (GDD §15 A7) — but it is the hook for the moment being *marked*.
signal player_leveled(level: int)

## What the player is wearing changed. {slot: ItemData} — see
## `actors/components/equipment_component.gd`.
signal player_equipment_changed(worn: Dictionary)

## Which hotbar slot the tool verb will use.
signal player_hotbar_selected(slot: int)

## A slot was pressed and nothing happened. The HUD flashes it.
signal player_item_refused(slot: int)

## A material was picked up.
signal material_collected(id: StringName, amount: int)

## The player died carrying a haul; it is now on the ground at `where`.
signal haul_dropped(items: Dictionary, where: Vector2)

## A dropped haul was picked back up in full.
signal haul_recovered

## The player crossed a threshold — a door, or the way back out of one. Emitted
## after the new scene is up and the player has been placed in it.
signal doorway_used(scene_path: String, spawn: String)

## A rebuild project was completed. Carries the id; listeners ask `Village` for
## anything more, because the bus carries facts and not state.
signal village_built(id: StringName)

## A waystone was lit for the first time. The id is stable across scenes, so a
## fast-travel network can key on it — see `world/shrine.gd`.
signal shrine_lit(id: StringName)

## Requested by hitboxes, consumed by the camera rig. Keeps camera logic out of
## the player (GDD §12, rule 4).
signal screen_shake_requested(amount: float, duration: float)
