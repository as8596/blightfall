extends Node
## Headless smoke test for the M1 systems.
##
## Not a substitute for playing it — the M1 gate is "is this fun", and no
## assertion answers that. What this does is stop the frame data in GDD §5 from
## silently drifting away from the frame data in the code, which is the failure
## mode that makes tuning sessions produce nonsense.
##
## Run:
##     godot --headless --path . tests/m1_smoke_test.tscn --quit-after 4000
##
## Exits non-zero if anything fails, so it works in CI as-is.

const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://actors/enemies/blighted_villager/blighted_villager.tscn")

const TICK: float = 1.0 / 60.0

var _world: Node2D
var _player: Player
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	# Headless runs unthrottled otherwise, which makes the physics accumulator
	# spike and the tick-counted assertions below meaningless.
	Engine.max_fps = 250
	_run.call_deferred()


func _run() -> void:
	_world = Node2D.new()
	add_child(_world)

	_build_room()
	_player = PLAYER_SCENE.instantiate()
	_player.global_position = Vector2(800, 800)
	_world.add_child(_player)
	await _ticks(4)

	print("\n=== Blightfall M1 smoke test ===\n")
	await _test_project_configuration()
	await _test_movement()
	await _test_attack_frame_data()
	await _test_combo_chain()
	await _test_dodge()
	await _test_stamina()
	await _test_damage_and_death()
	await _test_enemy_behaviour()
	await _test_animation()
	_test_design_rules()

	print("\n%d checks, %d failed\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- assertions

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(
		label,
		absf(actual - expected) <= tolerance,
		"got %.4f, want %.4f +/- %.4f" % [actual, expected, tolerance]
	)


# ------------------------------------------------------------------ harness

func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	# Held for one process frame so `is_action_just_pressed` sees the edge.
	await get_tree().process_frame
	Input.action_release(action)


func _hold(action: StringName) -> void:
	Input.action_press(action)


func _release_all() -> void:
	for action in [&"move_up", &"move_down", &"move_left", &"move_right", &"attack", &"dodge", &"tool"]:
		Input.action_release(action)


## Wait until the player enters `state`, up to `limit` ticks. Returns true if it
## got there.
func _await_state(state: StringName, limit: int = 30) -> bool:
	for i in limit:
		if _player.state_machine.is_in(state):
			return true
		await get_tree().physics_frame
	return _player.state_machine.is_in(state)


func _reset_player() -> void:
	_release_all()
	_player.respawn()
	_player.global_position = Vector2(800, 800)
	await _ticks(3)


func _build_room() -> void:
	# A box big enough that nothing under test touches a wall.
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	var geometry := [
		[Vector2(800, -16), Vector2(2400, 32)],
		[Vector2(800, 1616), Vector2(2400, 32)],
		[Vector2(-416, 800), Vector2(32, 1680)],
		[Vector2(2016, 800), Vector2(32, 1680)],
	]
	for entry in geometry:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = entry[1]
		shape.shape = rect
		shape.position = entry[0]
		walls.add_child(shape)
	_world.add_child(walls)


# -------------------------------------------------------------------- tests

func _test_project_configuration() -> void:
	print("Project configuration (GDD §10, BUILD-PLAN day 1)")
	_check(
		"viewport is 1280x720",
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
			and ProjectSettings.get_setting("display/window/size/viewport_height") == 720
	)
	_check(
		"stretch mode is canvas_items",
		ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
	)
	_check(
		"2D transforms snap to pixel",
		ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel") == true
	)
	_check(
		"default texture filter is Nearest",
		int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) == 0
	)

	var expected := ["World", "Player", "PlayerHitbox", "PlayerHurtbox",
		"Enemy", "EnemyHitbox", "EnemyHurtbox", "Interactable"]
	var layers_ok := true
	for i in expected.size():
		if ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % (i + 1)) != expected[i]:
			layers_ok = false
	_check("all eight physics layers named per GDD §10", layers_ok)

	for action in [&"move_up", &"move_down", &"move_left", &"move_right", &"attack", &"dodge", &"tool"]:
		_check("input action '%s' exists" % action, InputMap.has_action(action))


func _test_movement() -> void:
	print("\nMovement (328 px/s at 1280x720, full speed in 0.08s)")
	await _reset_player()

	_hold(&"move_right")
	# Long enough to be unambiguously at terminal velocity.
	await _ticks(30)
	_check_near("walk speed", _player.motion_velocity.length(), 328.0, 12.0)
	_check("state is Move while walking", _player.state_machine.is_in(&"Move"))
	_check("facing snapped east", _player.facing.is_equal_approx(Vector2.RIGHT))
	_release_all()

	# 8-directional snapping: diagonals stay unit length rather than 1.41x.
	_hold(&"move_right")
	_hold(&"move_up")
	await _ticks(30)
	_check_near("diagonal speed matches cardinal", _player.motion_velocity.length(), 328.0, 12.0)
	_release_all()
	await _ticks(20)

	# Acceleration: measured from the first tick the player actually moves, not
	# from the button press. Input is sampled in _process and consumed in
	# _physics_process, so a press costs up to a frame of latency before the
	# ramp begins — real, expected, and not what this check is about.
	_check_near("decelerates to rest", _player.motion_velocity.length(), 0.0, 8.0)
	_hold(&"move_right")
	var elapsed := -1.0
	for i in 40:
		await get_tree().physics_frame
		var speed := _player.motion_velocity.length()
		if speed <= 0.0:
			continue
		if elapsed < 0.0:
			elapsed = 0.0
		if speed >= 328.0 * 0.95:
			break
		elapsed += TICK
	_check("reaches full speed in ~0.08s", elapsed >= 0.0 and elapsed <= 0.09,
		"took %.3fs from first movement" % elapsed)
	_release_all()
	await _ticks(20)


func _test_attack_frame_data() -> void:
	print("\nAttack hit 1 (GDD §5: windup 0.08, active 0.10, recovery 0.16)")
	await _reset_player()

	await _press(&"attack")
	var entered := await _await_state(&"Attack")
	_check("attack input enters Attack state", entered)
	if not entered:
		return

	# Sample the hitbox once per tick from the tick the state was entered.
	var first_active := -1.0
	var last_active := -1.0
	var ended_at := -1.0
	for i in range(1, 60):
		await get_tree().physics_frame
		var t := float(i) * TICK
		if _player.hitbox.is_active():
			if first_active < 0.0:
				first_active = t
			last_active = t
		if not _player.state_machine.is_in(&"Attack"):
			ended_at = t
			break

	_check_near("hitbox turns on at windup", first_active, 0.08, 0.02)
	_check_near("active window length", last_active - first_active + TICK, 0.10, 0.02)
	_check_near("hit 1 total duration", ended_at, 0.08 + 0.10 + 0.16, 0.025)
	_check("returns to locomotion after recovery",
		_player.state_machine.is_in(&"Idle") or _player.state_machine.is_in(&"Move"))

	# The combo window outlives the state (GDD §5: closes 0.25s after recovery
	# begins, while hit 1's recovery is only 0.16s long).
	_check("combo window still open on exit", _player.combo_window_remaining > 0.0,
		"%.3fs left" % _player.combo_window_remaining)
	_check("next press continues at hit 2", _player.next_combo_index == 1)

	await _ticks(30)
	_check("combo window expires", _player.combo_window_remaining == 0.0 and _player.next_combo_index == 0)


func _test_combo_chain() -> void:
	print("\nCombo chaining (GDD §5: cancel into next from 0.12)")
	await _reset_player()

	await _press(&"attack")
	if not await _await_state(&"Attack"):
		_check("combo test could not start", false)
		return
	var attack_state := _player.state_machine.current_state as PlayerAttackState
	_check("starts at hit 1", attack_state.combo_index() == 0)

	# Press again during the active frames — before the chain opens. The buffer
	# should hold it rather than dropping it.
	await _ticks(3)
	await _press(&"attack")
	await _ticks(8)
	_check("chains into hit 2", _player.state_machine.is_in(&"Attack")
		and (_player.state_machine.current_state as PlayerAttackState).combo_index() == 1)

	await _ticks(6)
	await _press(&"attack")
	await _ticks(10)
	var still_attacking := _player.state_machine.is_in(&"Attack")
	_check("chains into hit 3", still_attacking
		and (_player.state_machine.current_state as PlayerAttackState).combo_index() == 2)

	# Hit 3 commits: no fourth hit exists, and the chain resets.
	await _ticks(45)
	_check("combo resets after the finisher", _player.next_combo_index == 0)


func _test_dodge() -> void:
	print("\nDodge (0.36s, 184px, i-frames 0.04→0.24)")
	await _reset_player()

	var start := _player.global_position
	await _press(&"dodge")
	if not await _await_state(&"Dodge"):
		_check("dodge input enters Dodge state", false)
		return
	_check("dodge input enters Dodge state", true)

	var iframes_first := -1.0
	var iframes_last := -1.0
	var duration := -1.0
	for i in range(1, 60):
		await get_tree().physics_frame
		var t := float(i) * TICK
		if _player.hurtbox.dodge_invulnerable:
			if iframes_first < 0.0:
				iframes_first = t
			iframes_last = t
		if not _player.state_machine.is_in(&"Dodge"):
			duration = t
			break

	_check_near("dodge duration", duration, 0.36, 0.025)
	_check_near("i-frames begin", iframes_first, 0.04, 0.025)
	_check_near("i-frames end", iframes_last + TICK, 0.24, 0.025)
	_check_near("dodge distance", start.distance_to(_player.global_position), 184.0, 8.0)
	_check("i-frames are off after the roll", not _player.hurtbox.dodge_invulnerable)
	_check_near("cooldown armed on exit", _player.dodge_cooldown_remaining, 0.12, 0.03)


func _test_stamina() -> void:
	print("\nStamina (GDD §6: dodge only, 4 dodges, ~1.5s refill)")
	await _reset_player()

	_check_near("starts full", _player.stamina.current, 4.0, 0.001)

	# Attacks are free. This is the decided design, and it is the rule most
	# likely to get quietly "fixed" into a stamina cost later.
	await _press(&"attack")
	await _await_state(&"Attack")
	await _ticks(25)
	_check("attacking costs no stamina", is_equal_approx(_player.stamina.current, 4.0),
		"%.2f" % _player.stamina.current)

	# The pool itself: four dodges' worth, and empty after four.
	await _reset_player()
	var spends := 0
	while _player.stamina.can_spend(1.0) and spends < 10:
		_player.stamina.spend(1.0)
		spends += 1
	_check("pool holds exactly four dodges", spends == 4, "spent %d" % spends)

	await _ticks(100)
	_check_near("refills in ~1.5s", _player.stamina.current, 4.0, 0.05)

	# Four consecutive dodges at the fastest rate the cooldown allows.
	await _reset_player()
	var dodges := 0
	for i in 4:
		if not _player.can_dodge():
			break
		await _press(&"dodge")
		if not await _await_state(&"Dodge", 10):
			break
		dodges += 1
		# Roll (0.36s) plus cooldown (0.12s), with a tick of slack.
		await _ticks(30)
	_check("four consecutive dodges", dodges == 4, "managed %d" % dodges)

	# Not an assertion — a finding. At the maximum dodge rate the cooldown
	# permits, regen outruns the cost, so the pool never actually binds. See
	# docs/M1-NOTES.md; this is a week 4 tuning decision, not a bug.
	var cycle: float = 0.36 + 0.12
	var regen_per_cycle: float = _player.stamina.regen_rate() * cycle
	print("  NOTE  %.2f stamina regenerates per %.2fs dodge cycle vs 1.00 spent%s"
		% [regen_per_cycle, cycle, " — pool never binds" if regen_per_cycle >= 1.0 else ""])


func _test_damage_and_death() -> void:
	print("\nDamage exchange (hitbox → hurtbox → health)")
	await _reset_player()

	var enemy: BaseEnemy = ENEMY_SCENE.instantiate()
	enemy.global_position = _player.global_position + Vector2(72, 0)
	_world.add_child(enemy)
	await _ticks(4)
	# Freeze it into a damage dummy: with target acquisition off it stays in
	# Idle forever. The state machine keeps running, because the death sequence
	# is a state and needs its ticks.
	enemy.set_process(false)
	enemy.set_physics_process(false)

	_check("enemy loads its EnemyData", enemy.data != null and enemy.health.max_health == 12)

	_player.facing = Vector2.RIGHT
	var before := enemy.health.current
	await _press(&"attack")
	await _await_state(&"Attack")
	await _ticks(30)
	_check("hit 1 deals 4 damage", enemy.health.current == before - 4,
		"%d → %d" % [before, enemy.health.current])

	# One activation must not tick twice over its 0.10s active window.
	_check("no double-hit within one swing", enemy.health.current == 8)

	# Kill it. The combo does 16 across three hits against 12 HP.
	var guard := 0
	while enemy.health.is_alive() and guard < 40:
		guard += 1
		await _press(&"attack")
		await _ticks(18)
	_check("enemy dies", not enemy.health.is_alive())
	_check("enemy leaves the target group when dead",
		not enemy.is_in_group(Targeting.ENEMY_GROUP))

	await _ticks(40)
	_check("dead enemy frees itself", not is_instance_valid(enemy))


func _test_enemy_behaviour() -> void:
	print("\nEnemy loop (approach → telegraph → lunge → recover)")
	await _reset_player()

	# The enemy will not attack off-screen (GDD §5, enemy rule 4), so the test
	# world needs a camera for the visibility notifier to have an opinion.
	var camera := Camera2D.new()
	camera.global_position = _player.global_position
	_world.add_child(camera)
	camera.make_current()

	var enemy: BaseEnemy = ENEMY_SCENE.instantiate()
	enemy.global_position = _player.global_position + Vector2(360, 0)
	_world.add_child(enemy)
	await _ticks(4)

	_check("enemy begins in Idle", enemy.state_machine.initial_state == &"Idle")
	_check("enemy is on screen", enemy.is_on_screen())

	# The player is a target the moment it exists; the enemy should notice.
	var seen: Dictionary = {}
	var telegraph_ticks := 0
	var hp_before := _player.health.current
	for i in 300:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		var state := enemy.state_machine.current_state_name()
		seen[state] = true
		if state == &"Telegraph":
			telegraph_ticks += 1
		if seen.has(&"Recover"):
			break

	_check("enemy chases", seen.has(&"Chase"))
	_check("enemy telegraphs before attacking", seen.has(&"Telegraph"))
	_check("enemy lunges", seen.has(&"Lunge"))
	_check("enemy recovers, giving the player a turn", seen.has(&"Recover"))
	_check_near("telegraph lasts 0.4s", float(telegraph_ticks) * TICK, 0.4, 0.03)
	_check("player took a hit from the lunge", _player.health.current < hp_before,
		"%d → %d" % [hp_before, _player.health.current])
	_check("player got i-frames from the hit", _player.hurtbox.iframes_remaining() > 0.0)

	# A hit does not interrupt a committed lunge (see EnemyState).
	var lunge := enemy.state_machine.get_node_or_null("Lunge") as EnemyState
	var telegraph := enemy.state_machine.get_node_or_null("Telegraph") as EnemyState
	_check("lunge cannot be staggered", lunge != null and not lunge.can_be_staggered())
	_check("telegraph can be staggered", telegraph != null and telegraph.can_be_staggered())

	if is_instance_valid(enemy):
		enemy.queue_free()
	camera.queue_free()
	await _ticks(2)


func _test_animation() -> void:
	print("\nAnimation (state → clip; attacks driven by frame data)")
	await _reset_player()
	var anim := _player.animation

	# With no art assigned the actor still runs, on a generated box.
	_check("runs with no art", not anim.has_art() and anim.sprite.texture != null)
	_check("placeholder is body-sized",
		anim.sprite.texture.get_size() == Vector2(64, 96),
		str(anim.sprite.texture.get_size()))
	_check("feet sit on the node origin", anim.sprite.offset.is_equal_approx(Vector2(0, -48)),
		str(anim.sprite.offset))

	var set: ActorAnimationSet = load("res://resources/animation/player_placeholder.tres")
	_check("placeholder animation set loads", set != null and set.idle != null)
	if set == null:
		return

	anim.animations = set
	await _ticks(2)
	# The placeholder carried its colour in modulate; real art must not inherit it.
	_check("assigning art clears the placeholder tint",
		anim.sprite.modulate.is_equal_approx(Color.WHITE), str(anim.sprite.modulate))
	_check("idle strip is sliced into frames", anim.sprite.hframes == 2, str(anim.sprite.hframes))

	# Facing picks the strip and the flip.
	_player.facing = Vector2.RIGHT
	await _ticks(2)
	_check("facing east uses the side strip, unflipped",
		anim.sprite.texture == set.idle.side and not anim.sprite.flip_h)
	_player.facing = Vector2.LEFT
	await _ticks(2)
	_check("facing west flips the side strip", anim.sprite.flip_h)
	_player.facing = Vector2.UP
	await _ticks(2)
	_check("facing north uses the up strip", anim.sprite.texture == set.idle.up)

	# The load-bearing one: attack frames track the combo's phase boundaries,
	# not a frame rate. Hit 1 is windup 0.08 / active 0.10 / recovery 0.16.
	_player.facing = Vector2.RIGHT
	await _press(&"attack")
	if not await _await_state(&"Attack"):
		_check("attack animation could not start", false)
		return
	_check("attack uses its own strip", anim.sprite.texture == set.attack_1.side)

	var seen_windup := false
	var seen_active := false
	var frame_when_hitbox_on := -1
	for i in range(1, 40):
		await get_tree().physics_frame
		var t := float(i) * TICK
		if t < 0.08:
			seen_windup = seen_windup or anim.current_frame() == 0
		if _player.hitbox.is_active() and frame_when_hitbox_on < 0:
			frame_when_hitbox_on = anim.current_frame()
		if t >= 0.08 and t < 0.18:
			seen_active = seen_active or anim.current_frame() == 1
		if not _player.state_machine.is_in(&"Attack"):
			break

	_check("frame 0 during windup", seen_windup)
	_check("frame 1 during the active window", seen_active)
	_check("the strike frame is showing exactly when the hitbox opens",
		frame_when_hitbox_on == 1, "frame %d" % frame_when_hitbox_on)

	anim.animations = null
	await _ticks(2)
	_check("clearing art restores the placeholder", not anim.has_art())


func _test_design_rules() -> void:
	print("\nDesign rules held in data (GDD §5)")
	var combo: PlayerComboData = load("res://resources/combat/player_combo.tres")
	var villager: EnemyData = load("res://resources/enemy_data/blighted_villager.tres")

	_check("combo is three hits", combo.length() == 3)
	_check("finisher commits (no chain out of hit 3)", not combo.hit_3.can_chain())
	_check("hit 3 stops movement", is_zero_approx(combo.hit_3.move_speed_scale))
	_check("hit 3 knockback in the scaled 48–80px band",
		combo.hit_3.knockback_distance >= 48.0 and combo.hit_3.knockback_distance <= 80.0,
		"%.0fpx" % combo.hit_3.knockback_distance)
	_check("screen shake on heavy hits only",
		is_zero_approx(combo.hit_1.screen_shake) and is_zero_approx(combo.hit_2.screen_shake)
			and combo.hit_3.screen_shake > 0.0)
	_check("hitstop 0.05 / 0.05 / 0.10",
		is_equal_approx(combo.hit_1.hitstop, 0.05) and is_equal_approx(combo.hit_2.hitstop, 0.05)
			and is_equal_approx(combo.hit_3.hitstop, 0.1))

	_check("telegraph is at least 0.4s", villager.telegraph_time >= 0.4,
		"%.2fs" % villager.telegraph_time)
	_check("telegraph changes colour", villager.telegraph_color != villager.base_color)
	_check("telegraph changes silhouette", villager.telegraph_scale != 1.0)

	var total := 0
	var hits := 0
	while total < villager.max_health and hits < 10:
		total += combo.step(hits % 3).damage
		hits += 1
	_check("killable in ≤5 hits at matched gear", hits <= 5, "%d hits" % hits)
