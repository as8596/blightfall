class_name Doorway
extends Interactable
## A threshold between two scenes — a building's door, and the way back out.
##
## **Pressed, not walked through.** Doors used to trigger on contact, which is
## cheaper for the player, but a transition that fades the screen must never
## fire by accident: brushing a doorway on the way past would blank the view and
## move you somewhere you did not choose to go. Once there is a fade, the
## deliberate press *is* the safety, not a tax.
##
## Placed by `Level` from `Doorways` markers in the map, so
## `tools/build_greybox.gd` can stay a thing that emits data rather than a thing
## that builds nodes.

signal used(target_scene: String, target_spawn: String)

## Where this leads.
@export_file("*.tscn") var target_scene: String = ""

## Which marker in the target scene to arrive at. The interiors put their
## `PlayerSpawn` two tiles in from the door; Ambry has a `Door_<id>` marker one
## tile outside each one. Either way you never arrive standing in a doorway.
@export var target_spawn: String = "PlayerSpawn"


func _ready() -> void:
	if prompt == "Examine":
		prompt = "Enter"
	super()


func can_interact(actor: Node) -> bool:
	return super(actor) and not Transition.is_busy() and not target_scene.is_empty()


func interact(actor: Node) -> void:
	if not can_interact(actor):
		return
	set_highlighted(false)
	used.emit(target_scene, target_spawn)
	super(actor)
	# Out of the physics callback before changing scene. Swapping scenes frees
	# the collision objects this callback is running inside, which the engine
	# refuses to do mid-step — and the refusal is a warning, not a crash, so the
	# damage would be a doorway that works nine times out of ten.
	_open.call_deferred()


## Deliberately not awaited. The transition outlives this node — the scene
## holding it is freed halfway through — and an `await` here would leave a
## coroutine suspended on an object that no longer exists. `Transition` is an
## autoload, so it finishes on its own.
##
## The run is carried across by `SaveGame.capture()`: the save system already
## knows how to collect everything a node owns and hand it back, so a threshold
## does not need a second, parallel notion of "what the player is carrying".
## Walking into the inn with a full satchel and walking out empty would be a bug
## nobody would think to look for here.
func _open() -> void:
	@warning_ignore("return_value_discarded")
	Transition.go(target_scene, target_spawn, SaveGame.capture())
	Events.doorway_used.emit(target_scene, target_spawn)
