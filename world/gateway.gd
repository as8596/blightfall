class_name Gateway
extends Area2D
## The edge of an outdoor area — walk off it and you are somewhere else.
##
## The counterpart to `world/doorway.gd`, and deliberately the opposite rule.
##
## **Doors are pressed. Edges are walked.** A door is a threshold you choose:
## brushing past one on the way somewhere else must never blank the screen and
## move you, so the press *is* the safety. An edge is not a threshold, it is the
## end of the ground — the path runs off the screen and the only thing you can
## do there is keep going. Asking for a keypress to continue walking in the
## direction you were already walking is a tax on the one input that needs none.
##
## Both use the same fade, because arriving should feel the same wherever you
## came from.
##
## Placed by `Level` from `Gateways` markers, so the map generators stay things
## that emit data rather than things that build nodes.

signal used(target_scene: String, target_spawn: String)

## Physics layer 2, named "Player" in project.godot. The gateway watches for the
## body; nothing watches for the gateway.
const PLAYER_LAYER: int = 2

@export_file("*.tscn") var target_scene: String = ""

## Which marker in the target area to arrive at. By convention an exit heading
## north lands on the neighbour's `Edge_south` — you come in through the edge
## that faces back the way you came.
@export var target_spawn: String = "PlayerSpawn"

## Which way off the map this leads. Sets the shape's long axis, and is what the
## build tools check when they verify that A-exits-north matches B-exits-south.
@export_enum("north", "south", "east", "west") var facing: String = "north"

## How many tiles wide the opening is. A one-tile gap in a hedge is a door with
## extra steps; a road's worth of opening is something you can walk into without
## lining yourself up.
@export var span: int = 4

## False until the player has been clear of the shape for one physics frame.
##
## Arriving *inside* a gateway is not hypothetical — every arrival marker sits a
## couple of tiles in from an edge, and a level that ever placed one too close
## would bounce the player between two areas forever, fading, with no input
## accepted. So the gateway refuses to fire until it has seen open ground.
var _armed: bool = false

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitoring = true
	monitorable = false
	_fit()


## Size the trigger to the opening. Long across the way you walk out, one tile
## deep, so it cannot be clipped diagonally by someone walking along the edge.
func _fit() -> void:
	var rect := RectangleShape2D.new()
	var thickness := float(GreyboxMap.TILE)
	var width := float(maxi(span, 1)) * GreyboxMap.TILE
	rect.size = Vector2(width, thickness) if facing in ["north", "south"] \
		else Vector2(thickness, width)
	_shape.shape = rect


func _physics_process(_delta: float) -> void:
	var touching := _player_inside()
	if not _armed:
		# One frame of daylight between arriving and being allowed to leave.
		_armed = not touching
		return
	if touching:
		_cross()


func _player_inside() -> bool:
	for body in get_overlapping_bodies():
		if body is Player:
			return true
	return false


func _cross() -> void:
	if Transition.is_busy() or target_scene.is_empty():
		return
	# Disarmed rather than freed: the scene is about to go anyway, and a gateway
	# that fires twice in the frame before it does would start two transitions.
	_armed = false
	set_physics_process(false)
	used.emit(target_scene, target_spawn)
	# Out of the physics step before changing scene, for the same reason
	# `Doorway` defers: swapping scenes frees the collision objects this callback
	# is running inside, and the engine's refusal to do that mid-step is a
	# warning rather than a crash — so the damage would be an edge that works
	# nine times out of ten.
	_open.call_deferred()


## Deliberately not awaited — see `Doorway._open`. The run is carried across by
## `SaveGame.capture()`, so walking out of the valley with a full satchel and
## arriving empty is not a bug anyone has to remember to avoid.
func _open() -> void:
	@warning_ignore("return_value_discarded")
	Transition.go(target_scene, target_spawn, SaveGame.capture())
	Events.doorway_used.emit(target_scene, target_spawn)
