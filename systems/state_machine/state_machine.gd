class_name StateMachine
extends Node
## Generic finite state machine. The player uses it; so does every enemy
## (BUILD-PLAN week 1: "generic, reusable — enemies use it too").
##
## States are child nodes. The machine does not start on its own: the actor
## calls `start()` from its own `_ready()`. Godot readies children before
## parents, so auto-starting would run `enter()` before the actor had finished
## wiring itself up.

signal state_changed(from: StringName, to: StringName)

## Name of the child node to begin in.
@export var initial_state: StringName = &"Idle"

## Defaults to the scene root (`owner`). Override only for nested rigs.
@export var actor_override: Node

var current_state: State
var previous_state_name: StringName = &""
var time_in_state: float = 0.0

var _states: Dictionary = {}
var _actor: Node
var _started: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_actor = actor_override if actor_override != null else owner
	for child in get_children():
		var state := child as State
		if state == null:
			push_warning("StateMachine: child '%s' is not a State." % child.name)
			continue
		state.state_machine = self
		state.actor = _actor
		_states[StringName(child.name)] = state


## Called by the actor once it is fully initialised.
func start(msg: Dictionary = {}) -> void:
	if _started:
		return
	_started = true
	set_process(true)
	set_physics_process(true)
	_enter_state(initial_state, msg)


func _process(delta: float) -> void:
	if current_state == null:
		return
	time_in_state += delta
	current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state == null:
		return
	current_state.physics_update(delta)


func transition_to(to: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(to):
		push_error("StateMachine: no state named '%s' on %s." % [to, _actor])
		return
	if current_state != null:
		previous_state_name = current_state.state_name()
		current_state.exit()
	_enter_state(to, msg)
	state_changed.emit(previous_state_name, to)


func _enter_state(to: StringName, msg: Dictionary) -> void:
	current_state = _states[to]
	time_in_state = 0.0
	current_state.enter(msg)


func current_state_name() -> StringName:
	return current_state.state_name() if current_state != null else &"<none>"


func has_state(state: StringName) -> bool:
	return _states.has(state)


func is_in(state: StringName) -> bool:
	return current_state != null and current_state.state_name() == state
