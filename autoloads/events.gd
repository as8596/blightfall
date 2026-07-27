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

## A material was picked up.
signal material_collected(id: StringName, amount: int)

## The player died carrying a haul; it is now on the ground at `where`.
signal haul_dropped(items: Dictionary, where: Vector2)

## A dropped haul was picked back up in full.
signal haul_recovered

## Requested by hitboxes, consumed by the camera rig. Keeps camera logic out of
## the player (GDD §12, rule 4).
signal screen_shake_requested(amount: float, duration: float)
