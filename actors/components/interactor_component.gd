class_name InteractorComponent
extends Area2D
## Finds the nearest thing the player could act on, and acts on it.
##
## Lives on the player as a component so nothing global has to know where the
## player is (GDD §12, rule 1). The Interactables are inert — they sit on their
## layer and wait to be found.

signal target_changed(interactable: Interactable)

## Off during cutscenes, and while a transition is in flight.
@export var enabled: bool = true

var _target: Interactable
var _actor: Node


func _ready() -> void:
	_actor = get_parent()
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = Interactable.LAYER


func _physics_process(_delta: float) -> void:
	var best := _nearest() if enabled else null
	if best == _target:
		return
	if _target != null and is_instance_valid(_target):
		_target.set_highlighted(false)
	_target = best
	if _target != null:
		_target.set_highlighted(true)
	target_changed.emit(_target)


## What the player would act on right now, or null.
func target() -> Interactable:
	return _target


## Act on it. Returns whether anything happened, so a caller can fall through to
## another verb when there is nothing here.
func try_interact() -> bool:
	if not enabled or _target == null or not is_instance_valid(_target):
		return false
	if not _target.can_interact(_actor):
		return false
	_target.interact(_actor)
	return true


## Nearest by distance. Deliberately not "whatever is most in line with the way
## you are facing": a door you are standing on but facing away from should still
## be the thing the button opens, because the player already walked to it.
func _nearest() -> Interactable:
	var best: Interactable = null
	var best_distance := INF
	for area in get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.can_interact(_actor):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Drop the current target and hide its prompt. Used when control is taken away
## mid-transition, so a prompt is not left lit on a scene that no longer exists.
func clear() -> void:
	if _target != null and is_instance_valid(_target):
		_target.set_highlighted(false)
	_target = null
