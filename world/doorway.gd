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

## One transition at a time, across every doorway in the tree. Two overlapping
## `change_scene_to_file` calls leave the tree in a state nothing here can
## reason about.
static var _travelling: bool = false


func _ready() -> void:
	if prompt == "Examine":
		prompt = "Enter"
	super()


func can_interact(actor: Node) -> bool:
	return super(actor) and not _travelling and not target_scene.is_empty()


func interact(actor: Node) -> void:
	if not can_interact(actor):
		return
	# Claimed here rather than inside travel(): two doorways can be in range at
	# once, and the second must find the door already taken.
	_travelling = true
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
## coroutine suspended on an object that no longer exists. `_travel_claimed` is
## static, so it belongs to the script rather than to any doorway, and it
## finishes on its own.
func _open() -> void:
	@warning_ignore("return_value_discarded")
	_travel_claimed(get_tree(), target_scene, target_spawn)


## Change scene, carrying the run across, behind a fade.
##
## The save system already knows how to collect everything a node owns and hand
## it back — that is the whole point of the `saveable` group — so a threshold
## does not need a second, parallel notion of "what the player is carrying".
## Walking into the inn with a full satchel and walking out empty would be a bug
## nobody would think to look for here.
static func travel(tree: SceneTree, scene_path: String, spawn: String = "") -> bool:
	if _travelling:
		return false
	_travelling = true
	return await _travel_claimed(tree, scene_path, spawn)


static func _travel_claimed(tree: SceneTree, scene_path: String, spawn: String) -> bool:
	if not ResourceLoader.exists(scene_path):
		_travelling = false
		push_error("Doorway: no scene at %s" % scene_path)
		return false

	# Black first. Everything below happens where the player cannot see it,
	# which is the point: the loaded scene gets a frame to place the player
	# before anyone looks at it.
	await ScreenFade.fade_out()

	var carried := SaveGame.capture()
	var error := tree.change_scene_to_file(scene_path)
	if error != OK:
		_travelling = false
		push_error("Doorway: could not open %s (%d)" % [scene_path, error])
		await ScreenFade.fade_in()
		return false

	# change_scene_to_file is deferred; the new tree is not up until the next
	# idle frame, and applying into the old one would silently do nothing.
	await tree.tree_changed
	await tree.process_frame

	SaveGame.apply(carried)
	# `apply` restores the player's previous *position* along with everything
	# else, so placement has to happen after it rather than before — otherwise
	# every door drops you back where you were standing in the last scene.
	var scene := tree.current_scene
	if scene != null and not spawn.is_empty() and scene.has_method(&"place_player_at"):
		scene.call(&"place_player_at", spawn)

	# One more frame so the camera has snapped to the player before the fade
	# lifts. Without it the first frame the player sees is the camera still
	# sliding into place.
	await tree.process_frame

	_travelling = false
	Events.doorway_used.emit(scene_path, spawn)
	await ScreenFade.fade_in()
	return true
