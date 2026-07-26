class_name InputIntent
extends RefCounted
## What the player *wants* this frame, with no knowledge of hardware.
##
## The InputComponent fills it in; states read it. This indirection is GDD §12
## rule 3, and it is also what makes replays, AI-driven players and remapping
## cheap later.

## Snapped movement direction, unit length or zero.
var move: Vector2 = Vector2.ZERO

## Un-snapped stick/key vector, for debugging and future analog use.
var raw_move: Vector2 = Vector2.ZERO

## True while an attack sits in the buffer.
var attack_buffered: bool = false
var dodge_buffered: bool = false
var tool_buffered: bool = false

## Held state, for future charge attacks.
var attack_held: bool = false
