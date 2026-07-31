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
##
## MP3 rather than WAV: the first track shipped as a 27MB wav, which is most of
## a repository for three minutes of music. These five together are under 14MB.
const TRACKS := {
	# Held for the prologue chapter and deliberately not used anywhere else —
	# it is the first thing the game plays and should not be worn out on a menu.
	&"prologue": "res://audio/music/the_beginning.mp3",
	&"ambry_day": "res://audio/music/ambry_day.mp3",
	&"ambry_night": "res://audio/music/ambry_night.mp3",
	&"market": "res://audio/music/market.mp3",
	&"wilds": "res://audio/music/the_wilds.mp3",
}

## Which track a level asks for, by scene path fragment. Matched on a substring
## so every Orchardfall area gets the valley's music without listing six scenes,
## and so a new area is silent-by-omission rather than silent-by-bug.
const BY_SCENE := {
	"levels/ambry/interiors/sundries": &"market",
	"levels/ambry": &"ambry_day",
	"levels/orchardfall": &"wilds",
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


## Play whatever suits a scene, and do nothing if it is already playing.
##
## Called on every level change. The "already playing" check is the whole point:
## walking from one Orchardfall area to the next must not restart the valley
## theme, or the music resets every time you cross an edge and never gets past
## its first bar.
func play_for_scene(scene_path: String, fade: float = DEFAULT_FADE) -> void:
	for fragment in BY_SCENE:
		if scene_path.contains(fragment):
			var wanted: StringName = BY_SCENE[fragment]
			if current != wanted:
				play(wanted, fade)
			return


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
