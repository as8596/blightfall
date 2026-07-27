extends CanvasLayer
## The overlay from BUILD-PLAN week 1, rule 2: "build it in week one and never
## turn it off."
##
## Shows state name, stamina, i-frames, active hitbox and combo index at all
## times — the exact list the plan asks for, plus the handful of numbers that
## turned out to matter while tuning. Without this, tuning frame data is
## guesswork: you cannot see a 0.10s active window, you can only feel that
## something is off.

## Set in the level scene. The overlay is handed a player; it does not look one
## up (GDD §12, rule 1).
@export var player_path: NodePath

@onready var _label: Label = $Panel/Label
@onready var _panel: Panel = $Panel
@onready var _stamina_back: ColorRect = $Panel/StaminaBack
@onready var _stamina_fill: ColorRect = $Panel/StaminaFill

const STAMINA_BAR_WIDTH: float = 180.0

var _player: Player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as Player
	DebugSettings.changed.connect(_refresh_visibility)
	get_viewport().size_changed.connect(_update_scale)
	_update_scale()
	_refresh_visibility()


## Counter-scale out of the 320×180 stretch so the overlay draws at native
## window resolution.
##
## Everything else in the game is 320×180 and scaled up 4×, which is correct for
## the game and wrong for text: legible debug text at 320×180 is 8px tall, and
## twelve lines of it cover half the play area. An overlay that hides the thing
## it describes is an overlay you turn off, and BUILD-PLAN week 1 is explicit
## that this one never gets turned off. So this layer alone opts out of the
## stretch, and its child nodes are laid out in window pixels.
func _update_scale() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	if viewport_size.x <= 0.0 or window_size.x <= 0.0:
		return
	var stretch := window_size.x / viewport_size.x
	if stretch <= 0.0:
		return
	scale = Vector2.ONE / stretch


func _refresh_visibility() -> void:
	visible = DebugSettings.show_overlay


func _process(_delta: float) -> void:
	if not visible:
		return
	_label.text = _build_text()
	_update_stamina_bar()


func _build_text() -> String:
	var lines: PackedStringArray = []
	var hitstop_note := ""
	if HitStop.is_active():
		hitstop_note = "  [HITSTOP %.2f]" % HitStop.time_remaining()
	lines.append("FPS %d   scale %.2f%s" % [
		Engine.get_frames_per_second(), Engine.time_scale, hitstop_note,
	])

	if _player == null or not is_instance_valid(_player):
		lines.append("no player")
		lines.append(_hint_line())
		return "\n".join(lines)

	var machine := _player.state_machine
	lines.append("state   %s  %.2fs" % [machine.current_state_name(), machine.time_in_state])
	lines.append("hp      %d/%d      stamina %.2f/%.2f" % [
		_player.health.current, _player.health.max_health,
		_player.stamina.current, _player.stamina.max_stamina,
	])
	lines.append("vel     %4.0f,%4.0f  kb %3.0f,%3.0f" % [
		_player.motion_velocity.x, _player.motion_velocity.y,
		_player.knockback.velocity.x, _player.knockback.velocity.y,
	])
	lines.append("facing  %s   pos %d,%d" % [
		_facing_name(_player.facing), int(_player.global_position.x), int(_player.global_position.y),
	])

	var iframes: PackedStringArray = []
	if _player.hurtbox.dodge_invulnerable:
		iframes.append("DODGE")
	if _player.hurtbox.damage_invulnerable:
		iframes.append("DMG %.2f" % _player.hurtbox.iframes_remaining())
	lines.append("iframes %-12s hitbox %s" % [
		" ".join(iframes) if not iframes.is_empty() else "-",
		"ACTIVE" if _player.hitbox.is_active() else "-",
	])

	lines.append(_combo_line(machine))
	lines.append("buffer  %.2f   dodge cd %.2f" % [
		_player.input.buffer_remaining(), _player.dodge_cooldown_remaining,
	])

	lines.append(_enemy_line())
	lines.append(_hint_line())
	return "\n".join(lines)


func _combo_line(machine: StateMachine) -> String:
	var attack := machine.current_state as PlayerAttackState
	if attack != null:
		return "combo   hit %d  t %.3f  (window %.2f)" % [
			attack.combo_index() + 1, attack.step_time(), _player.combo_window_remaining,
		]
	if _player.combo_window_remaining > 0.0:
		return "combo   next hit %d  window %.2f" % [
			_player.next_combo_index + 1, _player.combo_window_remaining,
		]
	return "combo   -"


func _enemy_line() -> String:
	var enemies := get_tree().get_nodes_in_group(Targeting.ENEMY_GROUP)
	if enemies.is_empty():
		return "enemies 0"
	var nearest := Targeting.nearest_enemy(_player) as BaseEnemy
	if nearest == null:
		return "enemies %d" % enemies.size()
	return "enemies %d   nearest %s hp %d/%d @%dpx" % [
		enemies.size(),
		nearest.state_machine.current_state_name(),
		nearest.health.current,
		nearest.health.max_health,
		int(_player.global_position.distance_to(nearest.global_position)),
	]


func _hint_line() -> String:
	return "F1 overlay  F2 boxes  F3 slowmo%s  F4 spawn  F5 reset  F6/F7 save/load%s" % [
		" ON" if DebugSettings.slow_motion else "",
		"  [slot 1]" if SaveGame.has_save(1) else "",
	]


func _update_stamina_bar() -> void:
	if _player == null or not is_instance_valid(_player):
		_stamina_back.visible = false
		_stamina_fill.visible = false
		return
	_stamina_back.visible = true
	_stamina_fill.visible = true
	var fraction := _player.stamina.fraction()
	_stamina_fill.size.x = roundf(STAMINA_BAR_WIDTH * fraction)
	# Red once there isn't a full dodge left — the number you actually care
	# about is "can I roll", not "how full is the bar".
	var has_dodge := _player.stamina.can_spend(1.0)
	_stamina_fill.color = Color(0.55, 0.85, 0.95) if has_dodge else Color(0.85, 0.35, 0.35)


static func _facing_name(facing: Vector2) -> String:
	var index := int(roundf(facing.angle() / (PI / 4.0))) % 8
	if index < 0:
		index += 8
	return ["E", "SE", "S", "SW", "W", "NW", "N", "NE"][index]
