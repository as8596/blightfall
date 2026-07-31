class_name PlayerComboData
extends Resource
## The player's whole light combo in one tunable file (GDD §5).
##
## Three named slots rather than an array: the design says three hits, the
## third is the committed finisher, and naming them keeps that legible in the
## inspector.

@export var hit_1: ComboStepData
@export var hit_2: ComboStepData
@export var hit_3: ComboStepData

## The charged swing. Not part of the chain — it is what holding the button
## turns into, and it ends a chain rather than continuing one.
##
## A fourth named slot rather than a flag on `hit_3`, because it is a different
## attack with its own frame data: slower to start, worth committing to, and the
## only one whose windup the player controls.
@export var heavy: ComboStepData

## GDD §5: "combo window closes 0.25s after recovery begins." Note this can
## outlast the hit itself — hit 1's recovery ends at 0.34s but its window stays
## open until 0.43s, so the chain survives a brief step back into Move.
@export var combo_window_after_recovery: float = 0.25


func steps() -> Array[ComboStepData]:
	var result: Array[ComboStepData] = []
	for step in [hit_1, hit_2, hit_3]:
		if step != null:
			result.append(step)
	return result


func step(index: int) -> ComboStepData:
	var all := steps()
	if index < 0 or index >= all.size():
		return null
	return all[index]


func length() -> int:
	return steps().size()
