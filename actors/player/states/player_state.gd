class_name PlayerState
extends State
## Shared behaviour for every player state.
##
## `try_common_transitions()` holds the two interrupts almost every state
## allows — attack and dodge — so the priority between them is decided once
## instead of drifting apart across six files.

var player: Player:
	get:
		return actor as Player


## Returns true if a transition was taken; callers must return immediately.
func try_common_transitions(allow_attack: bool = true, allow_dodge: bool = true) -> bool:
	if allow_dodge and player.can_dodge() and player.input.consume_dodge():
		state_machine.transition_to(&"Dodge")
		return true
	if allow_attack and player.input.consume_attack():
		state_machine.transition_to(&"Attack", {"combo_index": player.next_combo_index})
		return true
	return false


## Idle or Move, whichever matches the stick right now. Saves every state
## having to decide what "back to normal" means.
func return_to_locomotion() -> void:
	if player.input.intent.move == Vector2.ZERO:
		state_machine.transition_to(&"Idle")
	else:
		state_machine.transition_to(&"Move")
