extends Node
## Moving between scenes — through a door, or back to your last save after dying.
##
## One place, because the ordering is fiddly and getting it wrong is silent.
## There are two callers now and there will be more (zone exits, the intro,
## loading from a menu), and every one of them needs the same five steps in the
## same order:
##
##   fade to black → swap the scene → restore state → place the player → fade in
##
## Also an autoload, and for the same reason `ScreenFade` is: a transition has to
## **outlive the scene that started it**. The doorway you pressed and the player
## who died are both freed halfway through the thing they asked for.

signal started(scene_path: String)
signal arrived(scene_path: String)

## A beat of lying there before the screen starts to go. Cutting to black on the
## same frame you die reads as a bug rather than as a death.
@export var death_pause: float = 0.9

## Whether dying reloads. Off for tests, which kill the player deliberately and
## repeatedly and would otherwise reload the scene out from under themselves.
@export var auto_retry: bool = true

var _busy: bool = false

## The haul dropped by the death currently being handled: {items, where, scene}.
## Restored on the far side of the swap — see `_restore_cache`.
var _cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.player_died.connect(_on_player_died)


## A transition is in flight. Doors check this so two cannot overlap.
func is_busy() -> bool:
	return _busy


## Swap to `scene_path`, restore `payload` (a `SaveGame.capture()`), and put the
## player on the marker named `spawn`. Returns false if it could not start.
func go(scene_path: String, spawn: String = "", payload: Dictionary = {}) -> bool:
	if _busy:
		return false
	_busy = true
	var ok := await _swap(scene_path, spawn, payload)
	_busy = false
	return ok


# ------------------------------------------------------------------- dying

## Death is not a rewind.
##
## You come back at your last rest; the world does not un-happen. In particular
## the haul you dropped where you fell is still lying there — GDD §15 A4 is
## explicit that nothing is destroyed, only displaced, and a death that restored
## a save from *before* the drop would quietly delete the entire stake. So the
## cache is carried across the reload and put back where you left it.
func _on_player_died(_player: Node) -> void:
	if not auto_retry or _busy:
		return
	# Out of whatever callback killed the player before touching the tree.
	_retry.call_deferred()


func _retry() -> void:
	if _busy:
		return
	_busy = true

	await get_tree().create_timer(death_pause, true, false, true).timeout

	var here := _current_scene_path()
	_cache = _capture_cache(here)

	# Where the run resumes: the last save if there is one, otherwise this scene
	# from the top. There is no save *point* in the world yet, so the fallback is
	# the path that actually runs today — and it must never be "nothing happens",
	# which is what dying used to do everywhere except the prototype room.
	var payload := {}
	var scene_path := here
	if SaveGame.has_save(SaveGame.current_slot):
		var data := SaveGame.read_slot(SaveGame.current_slot)
		if not data.is_empty():
			payload = data
			var saved := String(data.get("scene", ""))
			if not saved.is_empty() and ResourceLoader.exists(saved):
				scene_path = saved

	@warning_ignore("return_value_discarded")
	await _swap(scene_path, "", payload)
	_busy = false


func _capture_cache(scene_path: String) -> Dictionary:
	for node in get_tree().get_nodes_in_group(HaulCache.GROUP):
		var cache := node as HaulCache
		if cache == null or cache.contents.is_empty():
			continue
		return {
			"items": cache.contents.duplicate(),
			"where": cache.global_position,
			"scene": scene_path,
		}
	return {}


## Put the dropped haul back, on the far side of the swap and before the fade
## lifts, so it is simply *there* rather than popping into an empty street.
##
## Only when the run resumes in the scene the player died in. Dying in a zone
## and resuming at a bed in Ambry would otherwise drop the cache in the village,
## which is the opposite of the point. Zones do not exist yet; when they do, the
## cache needs to persist per-scene rather than in one variable, and this is
## where that starts.
func _restore_cache() -> void:
	if _cache.is_empty():
		return
	var landed := _current_scene_path()
	if String(_cache.get("scene", "")) != landed:
		_cache = {}
		return

	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("Player") as Player if scene != null else null
	if player != null and player.haul_cache_scene != null:
		@warning_ignore("return_value_discarded")
		HaulCache.drop(get_tree(), player.haul_cache_scene, player.get_parent(),
			_cache["where"], _cache["items"])
	_cache = {}


# ------------------------------------------------------------------ the swap

func _swap(scene_path: String, spawn: String, payload: Dictionary) -> bool:
	if not ResourceLoader.exists(scene_path):
		push_error("Transition: no scene at %s" % scene_path)
		_cache = {}
		return false

	started.emit(scene_path)

	# Black first. Everything below happens where the player cannot see it,
	# which is the point: the loaded scene gets a frame to arrange itself.
	await ScreenFade.fade_out()

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Transition: could not open %s (%d)" % [scene_path, error])
		_cache = {}
		await ScreenFade.fade_in()
		return false

	# change_scene_to_file is deferred; the new tree is not up until the next
	# idle frame, and applying into the old one would silently do nothing.
	await get_tree().tree_changed
	await get_tree().process_frame

	if not payload.is_empty():
		SaveGame.apply(payload)

	# `apply` restores the player's previous *position* along with everything
	# else, so placement has to happen after it rather than before — otherwise
	# every door drops you back where you were standing in the last scene.
	var scene := get_tree().current_scene
	if scene != null and not spawn.is_empty() and scene.has_method(&"place_player_at"):
		scene.call(&"place_player_at", spawn)
	# A retry passes no spawn on purpose — you resume exactly where you saved.
	# But a save carries a bare coordinate with no idea which map it is landing
	# in, so the arrival still has to be checked before the fade lifts.
	if scene != null and scene.has_method(&"ensure_player_inside"):
		scene.call(&"ensure_player_inside")

	_restore_cache()

	# One more frame so the camera has snapped to the player before the fade
	# lifts. Without it the first thing anyone sees is the camera still sliding
	# into place.
	await get_tree().process_frame

	arrived.emit(scene_path)
	await ScreenFade.fade_in()
	return true


func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""
