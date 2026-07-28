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
	# This test kills the player four times on purpose. Dying now reloads the
	# last save, which would tear down the test scene mid-run.
	Transition.auto_retry = false
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
	await _test_save_load()
	await _test_haul()
	await _test_village()
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

	var dodge_keys: Array[int] = []
	for event in InputMap.action_get_events(&"dodge"):
		var key := event as InputEventKey
		if key != null:
			dodge_keys.append(key.physical_keycode)
	_check("dash is on shift", dodge_keys.has(KEY_SHIFT), "%s" % [dodge_keys])
	_check("and still on space", dodge_keys.has(KEY_SPACE))


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

	# The player ships with art now, and it has to be showing from the first
	# frame — the initial state is entered without a transition, so an actor
	# that only picks up its sprite on the *next* state change is invisible
	# until it moves.
	var set: ActorAnimationSet = load("res://resources/animation/player_placeholder.tres")
	_check("placeholder animation set loads", set != null and set.idle != null)
	if set == null:
		return
	_check("the player has art assigned", anim.has_art())
	_check("and is showing it while merely standing there",
		anim.sprite.texture != null and _player.state_machine.is_in(&"Idle"),
		"texture=%s state=%s" % [anim.sprite.texture, _player.state_machine.current_state_name()])
	_check("feet sit on the node origin", anim.sprite.offset.is_equal_approx(Vector2(0, -48)),
		str(anim.sprite.offset))

	# An actor with no art at all still has to run — that is what keeps a
	# grey-box enemy working while its sprites are being drawn.
	anim.animations = null
	await _ticks(2)
	_check("an actor with no art falls back to a box",
		not anim.has_art() and anim.sprite.texture != null)
	_check("and the box is body-sized",
		anim.sprite.texture.get_size() == Vector2(64, 96),
		str(anim.sprite.texture.get_size()))

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


func _test_save_load() -> void:
	print("\nSave/load (JSON, versioned, atomic)")
	const SLOT := 9
	SaveGame.delete_save(SLOT)
	await _reset_player()

	_check("player is registered as saveable", _player.is_in_group(SaveGame.GROUP))
	_check("empty slot reports no save", not SaveGame.has_save(SLOT))
	_check("loading an empty slot fails cleanly", not SaveGame.load_slot(SLOT))

	# Put the player in a distinctive state, save, disturb it, load it back.
	_player.global_position = Vector2(1234, 567)
	_player.facing = Vector2.LEFT
	_player.health.take_damage(2)
	var saved_position := _player.global_position
	var saved_health := _player.health.current

	_check("save writes", SaveGame.save_slot(SLOT), SaveGame.last_error())
	_check("slot now exists", SaveGame.has_save(SLOT))

	_player.global_position = Vector2(10, 10)
	_player.facing = Vector2.DOWN
	_player.health.heal(99)

	_check("load reads back", SaveGame.load_slot(SLOT), SaveGame.last_error())
	_check("position restored", _player.global_position.is_equal_approx(saved_position),
		str(_player.global_position))
	_check("facing restored", _player.facing.is_equal_approx(Vector2.LEFT))
	_check("health restored", _player.health.current == saved_health,
		"%d vs %d" % [_player.health.current, saved_health])
	_check("player is idle after loading", _player.state_machine.is_in(&"Idle"))

	# The file is data, and readable data at that.
	var raw := FileAccess.open(SaveGame.slot_path(SLOT), FileAccess.READ)
	var text := raw.get_as_text() if raw != null else ""
	if raw != null:
		raw.close()
	var parsed: Variant = JSON.parse_string(text)
	_check("file is valid JSON", parsed is Dictionary)
	_check("file carries a schema version",
		parsed is Dictionary and int((parsed as Dictionary).get("version", -1)) == SaveGame.VERSION)
	_check("file records the scene", parsed is Dictionary
		and String((parsed as Dictionary).get("scene", "")) != "")
	_check("file contains no script reference", not text.contains("script"),
		"a save must never be able to name code")

	# A larger heart container must survive a round trip — the classic ordering
	# bug is restoring current health before raising the maximum.
	_player.health.set_max_health(12)
	_player.health.current = 11
	_check("save with a raised max", SaveGame.save_slot(SLOT), SaveGame.last_error())
	_player.health.set_max_health(6)
	SaveGame.load_slot(SLOT)
	_check("raised max health restored", _player.health.max_health == 12,
		str(_player.health.max_health))
	_check("current health not clamped to the old max", _player.health.current == 11,
		str(_player.health.current))

	# Corruption: a truncated or hand-edited file falls back to the backup
	# rather than losing the run.
	SaveGame.save_slot(SLOT)
	var vandal := FileAccess.open(SaveGame.slot_path(SLOT), FileAccess.WRITE)
	vandal.store_string("{ this is not json")
	vandal.close()
	var recovered := SaveGame.read_slot(SLOT)
	_check("corrupt save recovers from backup", not recovered.is_empty(), SaveGame.last_error())

	# A save from a future version is refused rather than half-applied.
	var future := FileAccess.open(SaveGame.slot_path(SLOT), FileAccess.WRITE)
	future.store_string(JSON.stringify({"version": SaveGame.VERSION + 5, "entries": {}}))
	future.close()
	_check("newer-version save is refused", SaveGame.read_slot(SLOT).is_empty())

	SaveGame.delete_save(SLOT)
	_check("delete removes the slot", not SaveGame.has_save(SLOT))
	await _reset_player()


func _test_haul() -> void:
	print("\nHaul (carry capacity, loss on death, recovery)")
	await _reset_player()
	var bag := _player.inventory
	bag.clear()

	_check("starts empty", bag.total() == 0)
	_check("capacity is finite", bag.capacity > 0, str(bag.capacity))

	bag.add(&"stone", 5)
	bag.add(&"timber", 3)
	_check("carries what it was given", bag.total() == 8 and bag.count_of(&"stone") == 5)

	# Partial pickup: walking over a pile with two slots free takes two, not
	# nothing. Refusing the whole pile would read as a bug to a player.
	var room := bag.space_left()
	var taken := bag.add(&"ore", room + 10)
	_check("fills to capacity and no further", taken == room and bag.is_full(),
		"took %d of %d" % [taken, room + 10])
	_check("a full bag takes nothing more", bag.add(&"ore", 1) == 0)

	# Spending is atomic — a half-paid building is worse than a refused one.
	bag.clear()
	bag.add(&"stone", 2)
	_check("cannot afford what it lacks", not bag.can_afford({&"stone": 2, &"timber": 1}))
	_check("a short spend changes nothing",
		not bag.spend({&"stone": 2, &"timber": 1}) and bag.count_of(&"stone") == 2)
	bag.add(&"timber", 1)
	_check("an affordable spend goes through",
		bag.spend({&"stone": 2, &"timber": 1}) and bag.total() == 0)

	# Death drops the haul where the player fell.
	bag.clear()
	bag.add(&"stone", 4)
	bag.add(&"ore", 2)
	var death_spot := _player.global_position
	_player.health.take_damage(999)
	await _ticks(4)

	_check("death empties the satchel", bag.total() == 0, str(bag.total()))
	var caches := get_tree().get_nodes_in_group(HaulCache.GROUP)
	_check("a cache is left behind", caches.size() == 1, "%d cache(s)" % caches.size())
	if caches.is_empty():
		return
	var cache: HaulCache = caches[0]
	_check("the cache holds the whole haul", cache.total() == 6, str(cache.total()))
	_check("dropped where the player fell",
		cache.global_position.distance_to(death_spot) < 8.0)

	# It must not be re-absorbed during the death animation.
	_check("cache is not armed immediately", cache.arm_delay > 0.0)

	# Recovery by walking back to it — the normal case.
	_player.respawn()
	_player.global_position = death_spot + Vector2(600, 0)
	await _ticks(3)
	cache.arm()
	_check("arming does not reach across the room", bag.total() == 0)
	_player.global_position = cache.global_position
	await _ticks(6)
	_check("walking back over it recovers the haul", bag.total() == 6, str(bag.total()))
	_check("the cache clears itself once empty", not is_instance_valid(cache))

	# Recovery while already standing on it. Dying and respawning on the spot
	# produces no entry event, so arming has to sweep or the haul is stranded
	# under the player's feet.
	bag.clear()
	bag.add(&"ore", 3)
	_player.health.take_damage(999)
	await _ticks(4)
	var stranded: Array = get_tree().get_nodes_in_group(HaulCache.GROUP)
	if not stranded.is_empty():
		var on_top: HaulCache = stranded[0]
		_player.respawn()
		_player.global_position = on_top.global_position
		await _ticks(3)
		on_top.arm()
		await _ticks(2)
		_check("a cache under the player is not stranded", bag.total() == 3, str(bag.total()))

	# A second death moves the pile rather than scattering the valley with them.
	bag.clear()
	bag.add(&"stone", 3)
	_player.health.take_damage(999)
	await _ticks(4)
	bag.add(&"timber", 2)
	_player.health.take_damage(999)
	await _ticks(4)
	_check("only ever one cache",
		get_tree().get_nodes_in_group(HaulCache.GROUP).size() == 1,
		"%d" % get_tree().get_nodes_in_group(HaulCache.GROUP).size())

	for node in get_tree().get_nodes_in_group(HaulCache.GROUP):
		node.queue_free()
	bag.clear()
	await _reset_player()


## Ambry, as built by `tools/build_greybox.gd`. See docs/AMBRY.md.
##
## The build script already asserts the layout is walkable and the north
## district is sealed; it does that against its own tile arrays. This checks the
## other half — that the scene it wrote still says the same things once the
## engine has loaded it, that the doors lead somewhere real, and that the walls
## physically stop a body. The last one is not paranoia: a tileset with no
## collision polygons at all rendered a screenshot of Ambry that looked
## completely correct, and every wall in it was walk-through.
func _test_village() -> void:
	print("\nAmbry (docs/AMBRY.md)")

	var level: Level = load("res://levels/ambry/ambry_level.tscn").instantiate()
	add_child(level)
	await _ticks(4)

	var plots := level.building_plots()
	var pois := level.points_of_interest()
	_check("twenty locations and POIs", plots.size() + pois.size() == 20,
		"%d plots + %d pois" % [plots.size(), pois.size()])

	var districts := {}
	for entry in plots + pois:
		var district := String(entry.get("district", ""))
		districts[district] = int(districts.get(district, 0)) + 1
	# Four are behind the wall and the fifth *is* the wall — you stand on the
	# south side to work on the breach, but it belongs to the group it opens.
	_check("five of them behind the wall",
		int(districts.get("north", 0)) + int(districts.get("wall", 0)) == 5,
		"%s" % [districts])

	# GDD §15 A4 caps the rebuild system at eight projects, and A6 makes the
	# archive the one that sits behind another project.
	var projects := level.rebuild_projects()
	var requires := {}
	for entry in projects:
		requires[String(entry["id"])] = String(entry.get("requires", ""))
	_check("eight rebuild projects", projects.size() == 8, "%d" % projects.size())
	_check("your home is the first build",
		level.district_of("home") == "south" and requires.get("home", "") == "")
	_check("the archive waits on the breach", requires.get("archive", "") == "breach",
		"requires '%s'" % requires.get("archive", ""))
	_check("the breach is worked on from the south side",
		level.district_of("breach") == "wall")

	# Ten NPCs (§2's nine plus the carpenter), spread across the village and the
	# four interiors. Four of the cast being indoors is the point — rebuilding
	# moves a person rather than unlocking a menu.
	var cast := {}
	for entry in level.npc_markers():
		cast[String(entry["id"])] = "ambry"
	var interiors := ["home", "inn", "forge", "magistrate_hall"]
	for id in interiors:
		var path := "res://levels/ambry/interiors/%s_level.tscn" % id
		_check("interior exists: %s" % id, ResourceLoader.exists(path))
		var interior: Level = load(path).instantiate()
		add_child(interior)
		await _ticks(2)
		for entry in interior.npc_markers():
			cast[String(entry["id"])] = id
		# The way back out has to land on a marker Ambry actually has, or the
		# player leaves a building and arrives in the middle of nowhere.
		var out := interior.map.find_child("Doorway_out", true, false) as Marker2D
		_check("%s: the way out points at Ambry" % id, out != null
			and level.find_marker(String(out.get_meta("target_spawn", ""))) != Vector2.INF,
			String(out.get_meta("target_spawn", "")) if out != null else "missing")
		interior.queue_free()
		await _ticks(2)
	_check("ten NPCs placed", cast.size() == 10, "%s" % [cast.size()])
	_check("the carpenter is in the village", cast.get("carpenter", "") == "ambry")
	_check("the magistrate is indoors", cast.get("magistrate", "") == "magistrate_hall")

	# Doorways are markers in the map; Level is what turns them into Area2Ds.
	var doors: Array[Doorway] = []
	for child in level.get_children():
		var door := child as Doorway
		if door != null:
			doors.append(door)
	_check("four doorways placed", doors.size() == 4, "%d" % doors.size())
	var targets_exist := true
	var prompts_are_verbs := true
	for door in doors:
		if not ResourceLoader.exists(door.target_scene):
			targets_exist = false
		if door.prompt != "Enter":
			prompts_are_verbs = false
	_check("every doorway leads to a scene that exists", targets_exist)
	_check("and offers a verb", prompts_are_verbs)

	# ---- the interact verb. Doors are pressed, not walked through: a
	# transition that blanks the screen must never fire by accident.
	_check("interact is bound", InputMap.has_action(&"interact"))
	_check("the player has an interactor", level.player.interactor != null)
	_check("which looks for the Interactable layer",
		level.player.interactor.collision_mask == Interactable.LAYER,
		"mask %d, layer %d" % [level.player.interactor.collision_mask, Interactable.LAYER])
	# Pickups share the layer but are walked over, so they must stay invisible to
	# a search. They manage that by never being monitorable — worth pinning,
	# because a stray `monitorable = true` would put a prompt on every twig.
	var pickup: Node = load("res://world/pickup.tscn").instantiate()
	add_child(pickup)
	await _ticks(2)
	_check("pickups are walked over, not prompted", not (pickup as Area2D).monitorable)
	pickup.queue_free()
	_check("doorways are interactable", doors.is_empty() or doors[0] is Interactable)
	_check("the fade starts clear", not ScreenFade.is_covered() and ScreenFade.alpha() == 0.0)

	# ---- the HUD. It holds no state; it hears the bus. The thing worth pinning
	# is that it hears the player's *opening* values — a listener that only ever
	# learns about changes shows zero hearts until you first take damage.
	_check("the HUD knows the health it was never told about directly",
		Hud.max_health > 0 and Hud.health > 0, "%d/%d" % [Hud.health, Hud.max_health])
	_check("and the satchel's capacity", Hud.capacity > 0, "%d" % Hud.capacity)
	# The hotbar selects; the tool verb uses. Skimming must never eat anything.
	var kit: ItemsComponent = level.player.items
	kit.select(0)
	var before := kit.count_at(0)
	kit.cycle(3)
	_check("the wheel moves the selection", kit.selected == 3, "slot %d" % kit.selected)
	kit.cycle(-5)
	_check("and wraps rather than stopping dead", kit.selected == kit.slots - 2,
		"slot %d" % kit.selected)
	_check("skimming past a slot does not use it", kit.count_at(0) == before)
	kit.select(0)
	_check("the tool verb is what uses the selected slot",
		Items.has(&"bread") and kit.item_at(0) != null)

	# Escape pauses, and the three things that must survive a pause do.
	_check("escape is bound", InputMap.has_action(&"ui_cancel"))
	PauseMenu.open()
	await _ticks(1)
	_check("the menu pauses the tree", PauseMenu.is_open() and get_tree().paused)
	_check("and hides the HUD", not Hud.enabled)
	_check("music keeps running while paused",
		Music.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("so does the fade, so a transition can finish",
		ScreenFade.process_mode == Node.PROCESS_MODE_ALWAYS)
	PauseMenu.close()
	await _ticks(1)
	_check("closing gives the game back",
		not PauseMenu.is_open() and not get_tree().paused and Hud.enabled)
	# A menu opening over a scene change would sit on top of a level the player
	# has not seen yet.
	Transition.auto_retry = false

	var wheel := level.player.get_node_or_null("StaminaWheel")
	_check("stamina is a ring on the character, not a bar in a corner", wheel != null)

	# The limiter only ever speaks when it says no. `depleted` is a different
	# moment — you can empty the pool on a dash that worked.
	var refused := [false]
	level.player.stamina.refused.connect(func(_a: float) -> void: refused[0] = true)
	level.player.stamina.current = 0.0
	_check("a dash you cannot afford is refused out loud",
		not level.player.stamina.spend(1.0) and refused[0])
	level.player.stamina.refill()

	# Death has to lead somewhere. It used to be terminal outside the prototype
	# room, which was fine when the prototype room was the only level and is not
	# fine now — see tests/death_test.tscn for the flow itself.
	_check("dying is wired to something",
		Events.player_died.get_connections().size() > 0,
		"%d listener(s)" % Events.player_died.get_connections().size())
	# `current_slot` is the slot death reloads, so it has to *follow* the slot
	# actually being used rather than being a constant somebody remembers to set
	# — otherwise a death in slot 3 quietly resumes somebody else's run.
	const SCRATCH := 9
	var previous_slot := SaveGame.current_slot
	SaveGame.current_slot = 1
	var wrote := SaveGame.save_slot(SCRATCH)
	_check("saving moves the run to that slot",
		wrote and SaveGame.current_slot == SCRATCH, "slot %d" % SaveGame.current_slot)
	SaveGame.delete_save(SCRATCH)
	SaveGame.current_slot = previous_slot

	# ---- draw order. z_index is checked *before* y-sorting, so a props layer
	# sitting one above the player draws over them from every position — walk up
	# to a wall and you disappear behind it. Nothing about the scene looks wrong
	# when this is broken; you just stop being able to see yourself.
	var objects := level.map.get_node_or_null("Objects") as TileMapLayer
	var overhead := level.map.get_node_or_null("Overhead") as TileMapLayer
	_check("props share the player's z_index",
		objects != null and objects.z_index == level.player.z_index,
		"objects z=%d, player z=%d" % [objects.z_index if objects != null else -99,
			level.player.z_index])
	_check("and are y-sorted, so walls sort by where the player stands",
		objects != null and objects.y_sort_enabled)
	_check("ground is below both", level.map.get_node_or_null("Ground") != null
		and (level.map.get_node("Ground") as TileMapLayer).z_index < level.player.z_index)
	_check("overhead is above both, and empty until eaves can fade",
		overhead != null and overhead.z_index > level.player.z_index
			and overhead.get_used_rect().size == Vector2i.ZERO)

	# ---- nobody starts outside the map.
	var bounds := level.world_bounds()
	_check("the spawn is inside the world",
		bounds.has_point(level.player.global_position),
		"%s in %s" % [level.player.global_position, bounds])
	_check("and it is the gate marker, not a fallback",
		level.player.global_position.distance_to(level.find_marker("PlayerSpawn")) < 1.0,
		"%s" % level.player.global_position)
	# A save restores a bare coordinate with no idea what map it lands in, so
	# arriving out of bounds has to be corrected rather than honoured.
	level.player.global_position = Vector2(-4000.0, -4000.0)
	level.ensure_player_inside()
	_check("a player left outside the world is put back",
		bounds.has_point(level.player.global_position),
		"%s" % level.player.global_position)

	# ---- the walls are real.
	var wall_player := level.player
	_check("the level placed a player", wall_player != null)
	if wall_player != null:
		# Two tiles south of the wall, on the spine, facing it.
		wall_player.global_position = Vector2(23.5 * 64.0, 18.0 * 64.0)
		await _ticks(2)
		var start_y := wall_player.global_position.y
		Input.action_press(&"move_up")
		await _ticks(90)
		Input.action_release(&"move_up")
		await _ticks(2)
		var stopped_at := wall_player.global_position.y
		# The wall occupies row 15, so its south face is at y = 16 * 64 = 1024,
		# and the player's body sits 32px above their origin.
		_check("the north wall stops a body", stopped_at > 1024.0,
			"walked from y=%.0f to y=%.0f, wall face at y=1056" % [start_y, stopped_at])
		_check("and it was actually walking", stopped_at < start_y - 32.0,
			"moved %.0fpx" % (start_y - stopped_at))

		# A door is a wall you open with a keypress. Walking into one has to stop
		# you, or the interact verb is decoration and every building is open.
		# The home's door is at tile (6, 30); its south face is y = 31 * 64.
		wall_player.global_position = Vector2(6.5 * 64.0, 33.0 * 64.0)
		await _ticks(2)
		Input.action_press(&"move_up")
		await _ticks(60)
		Input.action_release(&"move_up")
		await _ticks(2)
		_check("a door stops a body too", wall_player.global_position.y > 1984.0,
			"stopped at y=%.0f, door face at y=2016" % wall_player.global_position.y)

	level.queue_free()
	await _ticks(2)
	await _reset_player()


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
