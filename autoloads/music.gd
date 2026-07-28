extends Node
## One music track at a time, with a crossfade between them.
##
## An autoload for the same reason `ScreenFade` is: music has to survive
## `change_scene_to_file`. A track owned by a level restarts from the top every
## time the player walks through a door, which turns a score into a stutter.
##
## Two players, not one, so a change can crossfade rather than cut. Cutting is
## available (`fade` of 0) and is the right call for a hard scene break; a
## crossfade is the right call for everything else.

const BUS := "Master"
const DEFAULT_FADE: float = 1.2

## Tracks by id, so callers name a piece of music rather than a file path.
const TRACKS := {
	&"main_menu": "res://audio/music/the_beginning.wav",
}

var current: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _tween: Tween


func _ready() -> void:
	# Music keeps playing while the tree is paused — a menu that silences the
	# score is a menu that feels like a crash.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


## Start `id`, crossfading from whatever is playing. Playing the track that is
## already playing does nothing, so a level that asks for its own music on every
## load does not restart it.
func play(id: StringName, fade: float = DEFAULT_FADE, volume_db: float = -6.0) -> void:
	if id == current:
		return
	if not TRACKS.has(id):
		push_warning("Music: no track named '%s'." % id)
		return
	var stream := load(TRACKS[id]) as AudioStream
	if stream == null:
		push_warning("Music: could not load %s." % TRACKS[id])
		return

	var outgoing := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	current = id
	_crossfade(outgoing, incoming, volume_db, fade)


func stop(fade: float = DEFAULT_FADE) -> void:
	current = &""
	_crossfade(_players[_active], null, 0.0, fade)


func is_playing() -> bool:
	return _players[_active].playing


func _crossfade(out_player: AudioStreamPlayer, in_player: AudioStreamPlayer,
		volume_db: float, fade: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if fade <= 0.0:
		if out_player != null:
			out_player.stop()
		if in_player != null:
			in_player.volume_db = volume_db
		return

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ignore_time_scale(true)
	if in_player != null:
		_tween.tween_property(in_player, "volume_db", volume_db, fade)
	if out_player != null and out_player.playing:
		_tween.tween_property(out_player, "volume_db", -80.0, fade)
		_tween.chain().tween_callback(out_player.stop)
