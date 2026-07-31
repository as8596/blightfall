class_name EnemyMemory
extends RefCounted
## Where the enemies in a level were, and which of them are dead.
##
## Without this, every level rebuilds its enemies from the map's markers, so
## stepping into a shop and back out puts the wolf you were fighting back at its
## spawn point at full health — and the fight you were losing is one you can
## simply walk away from. It also means a cleared area is never cleared.
##
## ## A static table rather than an autoload
##
## Everything else that outlives a scene here is an autoload, and this could
## have been one. It is not, because an autoload is a thing other code can reach
## for: `Village`, `Skills` and `Quests` all exist to be *asked questions* from
## anywhere. Nothing should ever ask this anything. It is written by `Level` on
## the way out and read by `Level` on the way in, and a static table keeps that
## contract visible — there is exactly one file that mentions it.
##
## ## Per session, not per save
##
## Deliberately not written to disk. A save records where the player is and what
## they own; recording the health of every wolf in the valley would make a save
## file a snapshot of the world's bookkeeping, and the first schema change would
## invalidate it. Loading a save is a fresh start for the valley, which is also
## what makes death a reset rather than a resume.

## {scene_path: {enemy_name: {"position": Vector2, "health": int, "dead": bool}}}
static var _levels: Dictionary = {}


## Remember every enemy currently in `world`, under this level's scene path.
##
## Called on the way out of a level. Anything already recorded as dead stays
## dead: the node is gone by then, so its absence is the only evidence left.
static func remember(scene_path: String, enemies: Array) -> void:
	if scene_path == "":
		return
	var here: Dictionary = _levels.get(scene_path, {})
	for node in enemies:
		var enemy := node as Node2D
		if enemy == null:
			continue
		var health: HealthComponent = enemy.get("health")
		here[enemy.name] = {
			"position": enemy.global_position,
			"health": health.current if health != null else -1,
			"dead": false,
		}
	_levels[scene_path] = here


## What is known about one enemy, or an empty dictionary.
static func recall(scene_path: String, enemy_name: String) -> Dictionary:
	return (_levels.get(scene_path, {}) as Dictionary).get(enemy_name, {})


## Mark one as killed, so it does not come back when the level is re-entered.
static func killed(scene_path: String, enemy_name: String) -> void:
	if scene_path == "":
		return
	var here: Dictionary = _levels.get(scene_path, {})
	here[enemy_name] = {"dead": true}
	_levels[scene_path] = here


static func is_dead(scene_path: String, enemy_name: String) -> bool:
	return bool(recall(scene_path, enemy_name).get("dead", false))


## Wipe everything. Death and loading a save both call this — see the docstring
## for why the valley resets rather than resumes.
static func forget_all() -> void:
	_levels.clear()
