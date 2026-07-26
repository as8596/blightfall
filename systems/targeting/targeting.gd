class_name Targeting
## The single place that answers "who do I attack?" (GDD §12, rule 2).
##
## Enemy code must never call `get_first_node_in_group("player")`. It asks this
## helper for its nearest valid target instead. The day a second player exists,
## this file changes and nothing else does.

## Anything an enemy is allowed to attack joins this group. Today that is one
## player; the group is what keeps it from being *the* player.
const TARGET_GROUP: StringName = &"enemy_targets"

## Anything a player is allowed to attack.
const ENEMY_GROUP: StringName = &"enemies"


## Nearest live target to `from`, or null. `max_range` <= 0 means unlimited.
static func nearest_target(from: Node2D, max_range: float = 0.0) -> Node2D:
	return _nearest_in_group(from, TARGET_GROUP, max_range)


## Nearest live enemy to `from`, or null.
static func nearest_enemy(from: Node2D, max_range: float = 0.0) -> Node2D:
	return _nearest_in_group(from, ENEMY_GROUP, max_range)


static func _nearest_in_group(from: Node2D, group: StringName, max_range: float) -> Node2D:
	if from == null or not from.is_inside_tree():
		return null
	var best: Node2D = null
	var best_distance_sq: float = INF
	var limit_sq: float = max_range * max_range
	for node in from.get_tree().get_nodes_in_group(group):
		var candidate := node as Node2D
		if candidate == null or candidate == from or not candidate.is_inside_tree():
			continue
		if not _is_valid(candidate):
			continue
		var distance_sq := from.global_position.distance_squared_to(candidate.global_position)
		if max_range > 0.0 and distance_sq > limit_sq:
			continue
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


## A target is valid while it is alive. Actors that expose `is_targetable()`
## get the final say (dead actors opt out during their death animation).
static func _is_valid(candidate: Node2D) -> bool:
	if candidate.has_method(&"is_targetable"):
		return candidate.call(&"is_targetable")
	return true


## Everything in `group` within `radius` of `from`, excluding `from` itself.
## Used for enemy separation so a pack doesn't stack into one rectangle.
static func neighbours(from: Node2D, group: StringName, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if from == null or not from.is_inside_tree():
		return result
	var radius_sq := radius * radius
	for node in from.get_tree().get_nodes_in_group(group):
		var other := node as Node2D
		if other == null or other == from or not other.is_inside_tree():
			continue
		if from.global_position.distance_squared_to(other.global_position) <= radius_sq:
			result.append(other)
	return result
