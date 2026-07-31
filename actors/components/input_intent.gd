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

## True while an interact sits in the buffer. Buffered like the rest so pressing
## it a frame before you finish walking into range still opens the door.
var interact_buffered: bool = false

## True while a weapon swap sits in the buffer. Buffered like the rest: the swap
## is something you press *while* backing out of a swing, and an unbuffered one
## would be eaten by the recovery frames you pressed it during.
var swap_buffered: bool = false

## Held state, for future charge attacks.
var attack_held: bool = false

## Right stick deflection, for aiming without a pointer. Zero when the player is
## on mouse and keyboard.
var aim_stick: Vector2 = Vector2.ZERO

## The dash key is still down. Tapping it dashes; keeping it down afterwards
## sprints — see `PlayerMoveState`.
var dodge_held: bool = false
