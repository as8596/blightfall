class_name State
extends Node
## Base class for a single state. One script per state (GDD §10, pattern 2).
##
## `actor` and `state_machine` are injected by the StateMachine before the first
## `enter()`, so states never reach up the tree themselves.

var state_machine: StateMachine
var actor: Node


## Called once when the state becomes current. `msg` carries hand-off data,
## e.g. {"combo_index": 1}.
func enter(_msg: Dictionary = {}) -> void:
	pass


## Called once when the state stops being current.
func exit() -> void:
	pass


## Per-frame, scaled by time_scale (so hitstop freezes it).
func update(_delta: float) -> void:
	pass


## Per-physics-tick. Movement and frame data live here.
func physics_update(_delta: float) -> void:
	pass


## The name other states transition to. Matches the node name.
func state_name() -> StringName:
	return name
