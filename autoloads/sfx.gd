extends Node
## Placeholder SFX playback with pitch randomisation (GDD §9, BUILD-PLAN week 3).
##
## Every hit gets a swing sound *and* an impact sound — they are separate calls
## on purpose so the layering is audible while tuning.

const POOL_SIZE: int = 16
const DEFAULT_PITCH_VARIANCE: float = 0.1

const STREAMS: Dictionary = {
	&"swing_light": preload("res://audio/sfx/swing_light.wav"),
	&"swing_heavy": preload("res://audio/sfx/swing_heavy.wav"),
	&"impact_light": preload("res://audio/sfx/impact_light.wav"),
	&"impact_heavy": preload("res://audio/sfx/impact_heavy.wav"),
	&"dodge": preload("res://audio/sfx/dodge.wav"),
	&"player_hurt": preload("res://audio/sfx/player_hurt.wav"),
	&"enemy_telegraph": preload("res://audio/sfx/enemy_telegraph.wav"),
	&"enemy_death": preload("res://audio/sfx/enemy_death.wav"),
	# Dialogue. Three blips cycled per speaker (ui/dialogue_box.gd).
	&"voice_a": preload("res://audio/sfx/voice_a.wav"),
	&"voice_b": preload("res://audio/sfx/voice_b.wav"),
	&"voice_c": preload("res://audio/sfx/voice_c.wav"),
	&"ui_move": preload("res://audio/sfx/ui_move.wav"),
	&"ui_select": preload("res://audio/sfx/ui_select.wav"),
}

## The voice blips, in cycle order. Named here rather than built from a prefix
## so a typo is a missing constant instead of a silent miss at runtime.
const VOICES: Array[StringName] = [&"voice_a", &"voice_b", &"voice_c"]

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		# Hitstop sets time_scale to 0; audio should keep playing through it.
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool.append(player)


## Play a placeholder sound, pitch-randomised. Two lines of code, infinite
## footsteps (GDD §9).
func play(id: StringName, volume_db: float = 0.0, pitch_variance: float = DEFAULT_PITCH_VARIANCE) -> void:
	var stream: AudioStream = STREAMS.get(id)
	if stream == null:
		push_warning("Sfx.play: unknown id '%s'" % id)
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = Rng.pitch(pitch_variance)
	player.play()


## The same, around a chosen pitch rather than around 1.0.
##
## A speaking voice needs both: a fixed offset so a character sounds like
## themselves from one line to the next, and jitter on top so a sentence does
## not sound like a dial tone.
func play_at(id: StringName, pitch: float, volume_db: float = 0.0,
		pitch_variance: float = DEFAULT_PITCH_VARIANCE) -> void:
	var stream: AudioStream = STREAMS.get(id)
	if stream == null:
		push_warning("Sfx.play_at: unknown id '%s'" % id)
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch * Rng.pitch(pitch_variance), 0.05)
	player.play()
