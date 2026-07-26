extends Node2D
## The one hand-placed box room M1 is allowed to have (BUILD-PLAN: no tilemaps).
##
## Its whole job is to put a player and some enemies in a space and get out of
## the way. The spawn controls exist for the week 4 question — "spawn 3–5
## enemies in the room; does fighting a group work, or does it collapse?" — and
## that question is much easier to answer if you can add a body mid-fight.

@export var enemy_scene: PackedScene
## Week 4 asks for 3–5. Start at 1 so week 3's "one enemy" test stays available.
@export var initial_enemy_count: int = 1
@export var max_enemies: int = 12
## Don't drop an enemy in the player's lap.
@export var min_spawn_distance: float = 48.0

@export_group("References")
@export var player_path: NodePath = ^"Player"
@export var spawn_points_path: NodePath = ^"SpawnPoints"

@onready var _player: Player = get_node_or_null(player_path) as Player
@onready var _spawn_points: Node2D = get_node_or_null(spawn_points_path) as Node2D


func _ready() -> void:
	spawn_enemies(initial_enemy_count)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F4:
			spawn_enemies(1)
			get_viewport().set_input_as_handled()
		KEY_F5:
			reset()
			get_viewport().set_input_as_handled()


func spawn_enemies(count: int) -> void:
	if enemy_scene == null:
		push_error("PrototypeRoom: no enemy_scene set.")
		return
	for i in count:
		if get_tree().get_nodes_in_group(Targeting.ENEMY_GROUP).size() >= max_enemies:
			return
		var enemy := enemy_scene.instantiate() as Node2D
		enemy.global_position = _pick_spawn_position()
		add_child(enemy)


## Furthest-from-the-player marker, so repeated spawns spread out instead of
## piling onto whichever one the RNG likes.
func _pick_spawn_position() -> Vector2:
	var markers := _markers()
	if markers.is_empty():
		return global_position
	var viable: Array[Marker2D] = []
	for marker in markers:
		if _player == null or marker.global_position.distance_to(_player.global_position) >= min_spawn_distance:
			viable.append(marker)
	if viable.is_empty():
		viable = markers
	return viable[Rng.randi_range(0, viable.size() - 1)].global_position


func _markers() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	if _spawn_points == null:
		return result
	for child in _spawn_points.get_children():
		var marker := child as Marker2D
		if marker != null:
			result.append(marker)
	return result


## Soft reset: heal the player, clear the field, repopulate. Faster than
## reloading the scene, which matters when you do it two hundred times a night.
func reset() -> void:
	# By children rather than by group: an enemy mid-death has already left the
	# group, and leaving its corpse fading through the reset looks like a bug.
	for child in get_children():
		if child is BaseEnemy:
			child.queue_free()
	if _player != null:
		_player.respawn()
	# Enemies free at the end of the frame; spawn after that so the count is
	# right and the new arrivals don't inherit the old ones' separation.
	await get_tree().process_frame
	spawn_enemies(initial_enemy_count)
