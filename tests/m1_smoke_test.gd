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
	# Built inside a SubViewport at the world's real size, because that is how
	# the game runs it now (`ui/world_view.gd`). Left as a plain child, anything
	# asking `get_viewport_rect()` gets the *window* — 64x64 under a headless
	# display server — and every on-screen check answers a question nobody asked.
	var view := SubViewport.new()
	view.size = WorldView.BASE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)

	_world = Node2D.new()
	view.add_child(_world)

	_build_room()
	_player = PLAYER_SCENE.instantiate()
	_player.global_position = Vector2(800, 800)
	_world.add_child(_player)
	await _ticks(4)

	print("\n=== Blightfall M1 smoke test ===\n")
	await _test_project_configuration()
	_test_type_scale()
	await _test_movement()
	await _test_attack_frame_data()
	await _test_weapon_arc()
	await _test_combo_chain()
	await _test_dodge()
	await _test_stamina()
	await _test_damage_and_death()
	await _test_enemy_behaviour()
	await _test_animation()
	await _test_experience()
	await _test_equipment()
	await _test_save_load()
	await _test_haul()
	await _test_village()
	await _test_world_objects()
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


## The rebuild ledger.
##
## The map carries the eight plots and what each costs; it is regenerated
## wholesale by a build script, so it cannot also be where "the forge is
## standing" lives. `Village` is that, and the reason it is an autoload is that
## the state has to survive walking out of the south gate — which is the entire
## point of going out.
func _test_village_state(level: Level) -> void:
	print("\nVillage state (GDD §15 A4: the town is the progress bar)")
	Village.reset()
	_check("a new game starts with a ruined town", Village.count() == 0)

	var projects := level.rebuild_projects()
	_check("the map still carries the projects", projects.size() == 8,
		"%d" % projects.size())
	if projects.is_empty():
		return

	var by_id := {}
	for entry in projects:
		by_id[String(entry.get("id", ""))] = entry
	var home: Dictionary = by_id.get("home", {})
	var archive: Dictionary = by_id.get("archive", {})

	# The chain is data — the archive waits on the breach — and the check for it
	# lives here because this is where the record of what is built is.
	_check("your home needs nothing first", Village.can_build(home))
	_check("the archive does", not Village.can_build(archive))

	var announced: Array[StringName] = []
	var listener := func(id: StringName) -> void: announced.append(id)
	Events.village_built.connect(listener)
	_check("building the home works", Village.build(home))
	_check("and it is announced once", announced.size() == 1 and announced[0] == &"home",
		str(announced))
	_check("it cannot be built twice", not Village.build(home))
	Events.village_built.disconnect(listener)

	# A satchel that cannot pay must not leave a building half-finished.
	var breach: Dictionary = by_id.get("breach", {})
	var purse := InventoryComponent.new()
	add_child(purse)
	purse.capacity = 99
	# The map authors a tier; Village turns it into materials. The breach is one
	# of the two "high" projects, so this also pins that the mapping happens at
	# all — a tier read as a literal dictionary silently costs nothing, which is
	# a rebuild economy anyone can skip.
	var cost := Village.cost_of(breach)
	_check("the breach costs materials, not a tier name",
		cost.has(&"timber") and int(cost[&"timber"]) > 0, str(cost))
	_check("and the expensive tiers want ironwork", cost.has(&"ironwork"), str(cost))
	_check("a trivial project is cheaper than a high one",
		int(Village.cost_of(home).get(&"timber", 0)) < int(cost[&"timber"]))
	_check("an empty satchel cannot build it", not Village.build(breach, purse))
	_check("and nothing was spent trying", purse.total() == 0, "%d" % purse.total())
	for material in cost:
		purse.add(StringName(material), int(cost[material]))
	_check("a full one can", Village.build(breach, purse))
	_check("and the materials are gone", purse.total() == 0, "%d" % purse.total())
	purse.queue_free()

	var saved := Village.save_data()
	Village.reset()
	_check("a reset town is ruined again", Village.count() == 0)
	Village.load_data(saved)
	_check("and a loaded one remembers what stood",
		Village.is_built(&"home") and Village.is_built(&"breach"), str(Village.completed()))
	Village.reset()


## Props and shrines: the two things a piece of drawn scenery becomes.
##
## The assertions here are all about *anchoring*, because that is the failure
## mode. A prop sorted by its centre rather than its base is a tree the player
## walks behind while standing well in front of it, and it looks like a
## y-sorting bug rather than like an offset.
func _test_world_objects() -> void:
	print("\nWorld objects (props sort by their base; shrines remember)")
	var art: Texture2D = load("res://art/sprites/player/player_idle_down.png")

	var prop: Prop = load("res://world/prop.tscn").instantiate()
	add_child(prop)
	prop.texture = art
	prop.footprint = Vector2(28, 16)
	await _ticks(2)
	_check("a prop shares the player's z_index", prop.z_index == 0, str(prop.z_index))
	_check("a prop y-sorts", prop.y_sort_enabled)
	var sprite := prop.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		for child in prop.get_children():
			if child is Sprite2D:
				sprite = child
	_check("the base of the picture sits on the origin",
		sprite != null and is_equal_approx(sprite.offset.y, -art.get_height() * 0.5),
		str(sprite.offset if sprite != null else Vector2.ZERO))

	var body: StaticBody2D = null
	for child in prop.get_children():
		if child is StaticBody2D:
			body = child
	_check("a solid prop blocks on the World layer",
		body != null and body.collision_layer == 1)
	# The canopy is not the trunk. A collider matching the drawn silhouette makes
	# a wood into a maze of walls you can see straight through.
	var shape := body.get_child(0) as CollisionShape2D if body != null else null
	_check("and its footprint is far smaller than its picture",
		shape != null and (shape.shape as RectangleShape2D).size.y < art.get_height() * 0.25,
		str((shape.shape as RectangleShape2D).size) if shape != null else "none")
	prop.solid = false
	await _ticks(2)
	_check("a non-solid prop stops blocking", shape.disabled)
	prop.queue_free()

	var shrine: Shrine = load("res://world/shrine.tscn").instantiate()
	shrine.id = &"test_waystone"
	shrine.dormant = art
	shrine.kindled = art
	add_child(shrine)
	await _ticks(2)
	_check("a shrine starts dormant", not shrine.is_lit)
	_check("and is in the saveable group", shrine.is_in_group(SaveGame.GROUP))
	_check("its save id is stable and not a node path",
		String(shrine.save_id()) == "shrine:test_waystone", String(shrine.save_id()))

	var announced: Array[StringName] = []
	var listener := func(id: StringName) -> void: announced.append(id)
	Events.shrine_lit.connect(listener)
	shrine.interact(_player)
	await _ticks(2)
	_check("resting lights it", shrine.is_lit)
	_check("and announces it once on the bus",
		announced.size() == 1 and announced[0] == &"test_waystone", str(announced))
	shrine.interact(_player)
	await _ticks(2)
	_check("resting again does not re-announce", announced.size() == 1, str(announced.size()))
	Events.shrine_lit.disconnect(listener)

	var state := shrine.save_data()
	shrine.load_data({"lit": false})
	_check("a shrine can be un-lit by a load", not shrine.is_lit)
	shrine.load_data(state)
	_check("and a saved shrine comes back lit", shrine.is_lit)
	shrine.queue_free()


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(
		label,
		absf(actual - expected) <= tolerance,
		"got %.4f, want %.4f +/- %.4f" % [actual, expected, tolerance]
	)


## Every clip's three strips must be three different pictures.
##
## Cheap to check and impossible to notice otherwise: a `_up` strip that is
## secretly the front view satisfies "facing north uses the up strip" perfectly.
## Circling, in the data. The behaviour itself is a state machine transition
## asserted by `_test_enemy_behaviour`; what this pins is that the numbers make
## sense, because both of them have a way of being quietly wrong.
func _check_circling() -> void:
	var wolf: EnemyData = load("res://resources/enemy_data/forest_wolf.tres")
	var villager: EnemyData = load("res://resources/enemy_data/blighted_villager.tres")
	for data in [wolf, villager]:
		if data.circle_time_max <= 0.0:
			continue
		# Below 1.0 the enemy circles *inside* its own attack range, which is
		# not a circle — it is standing on top of you with extra steps, and it
		# eats the recovery window the player is owed.
		_check("%s circles outside its own reach" % data.display_name,
			data.circle_radius_scale > 1.0, "%.2f" % data.circle_radius_scale)
		_check("and does not circle forever", data.circle_time_max <= 2.0,
			"%.2fs" % data.circle_time_max)


## A sprite that is not flashing must not be going through the flash shader.
##
## This is not tidiness. In the Compatibility renderer a canvas item carrying a
## custom shader takes a different colour path from one without, and leaving the
## material attached at `flash_amount = 0.0` — which reads as a no-op — squared
## every colour the actor drew: the player's `#d9c48d` linen reached the screen
## as `#b9974e`. It looked like the art was wrong, and no test was watching,
## because every assertion here is about positions and states rather than about
## what colour came out.
func _check_flash_is_off_by_default() -> void:
	var flash: FlashComponent = _player.get_node_or_null("FlashComponent")
	if flash == null:
		for child in _player.get_children():
			if child is FlashComponent:
				flash = child
	_check("the player has a flash component", flash != null)
	if flash == null:
		return
	var visual := _player.get_node_or_null("Visual") as CanvasItem
	_check("and its sprite carries no material while nothing is hitting it",
		visual != null and visual.material == null,
		str(visual.material) if visual != null else "no Visual")

	flash.flash()
	await _ticks(1)
	_check("a hit attaches the shader", visual.material != null)
	# 0.08s at 60Hz, plus a frame for the component to notice.
	await _ticks(8)
	_check("and it comes off again when the flash ends", visual.material == null,
		str(visual.material))


## Eight-way facing: the octant snap, the deadband that stops it flickering, and
## the fallback chain that lets three-strip and eight-strip actors share one
## component.
##
## The mirroring assertions are the load-bearing ones. An actor wearing a sword
## on one hip is *wrong* when mirrored, and the failure is subtle enough to ship:
## the scabbard swaps sides as you turn, which reads as an animation glitch
## rather than as a missing file.
func _check_eight_way(set: ActorAnimationSet) -> void:
	const F := AnimationComponent.Facing
	var compass := {
		F.RIGHT: Vector2.RIGHT, F.LEFT: Vector2.LEFT,
		F.DOWN: Vector2.DOWN, F.UP: Vector2.UP,
		F.DOWN_RIGHT: Vector2(1, 1), F.DOWN_LEFT: Vector2(-1, 1),
		F.UP_RIGHT: Vector2(1, -1), F.UP_LEFT: Vector2(-1, -1),
	}
	var wrong: Array[String] = []
	for expected in compass:
		# From the opposite facing, so nothing is decided by hysteresis.
		var got := AnimationComponent.facing_for(compass[expected], F.DOWN if expected != F.DOWN else F.UP)
		if got != expected:
			wrong.append("%s -> %d, wanted %d" % [compass[expected], got, expected])
	_check("all eight directions snap to their own octant", wrong.is_empty(), ", ".join(wrong))

	# A stick resting on a boundary must not switch strips every frame.
	var boundary := Vector2.RIGHT.rotated(deg_to_rad(23.0))
	_check("a facing just inside the deadband holds its strip",
		AnimationComponent.facing_for(boundary, F.RIGHT) == F.RIGHT)
	_check("and past it, commits",
		AnimationComponent.facing_for(Vector2.RIGHT.rotated(deg_to_rad(40.0)), F.RIGHT)
			== F.DOWN_RIGHT)
	_check("zero input keeps the last facing",
		AnimationComponent.facing_for(Vector2.ZERO, F.UP_LEFT) == F.UP_LEFT)

	# Three-strip set (what the placeholder is): the west half is mirrored, and
	# the diagonals resolve onto the nearest drawn strip.
	var clip: SpriteAnimation = set.idle
	_check("three-strip set: east is the side strip, unmirrored",
		clip.resolve(F.RIGHT)["texture"] == clip.side and not clip.resolve(F.RIGHT)["flip"])
	_check("three-strip set: west mirrors it",
		clip.resolve(F.LEFT)["texture"] == clip.side and clip.resolve(F.LEFT)["flip"])
	_check("three-strip set: south-east falls back to a drawn strip",
		clip.resolve(F.DOWN_RIGHT)["texture"] != null)
	_check("a three-strip set reports three directions",
		clip.direction_count() == 3, str(clip.direction_count()))

	# Eight-strip set: nothing is mirrored, because mirroring is the bug.
	var full := SpriteAnimation.new()
	full.down = clip.down
	full.up = clip.up
	full.side = clip.side
	full.down_side = clip.down
	full.up_side = clip.up
	full.side_west = clip.up          # distinct texture, so "not mirrored" is provable
	full.down_side_west = clip.down
	full.up_side_west = clip.side
	full.frames = clip.frames
	_check("eight-strip set reports eight directions",
		full.direction_count() == 8, str(full.direction_count()))
	var mirrored: Array[String] = []
	for facing in compass:
		if full.resolve(facing)["flip"]:
			mirrored.append(str(facing))
	_check("an eight-strip set mirrors nothing", mirrored.is_empty(), ", ".join(mirrored))
	_check("and the west strip is its own picture, not the east one flipped",
		full.resolve(F.LEFT)["texture"] == full.side_west)


func _check_distinct_directions(set: ActorAnimationSet) -> void:
	var clips := {
		"idle": set.idle, "walk": set.walk, "attack_1": set.attack_1,
		"dodge": set.dodge, "hurt": set.hurt, "death": set.death,
	}
	var same: Array[String] = []
	for label in clips:
		var clip: SpriteAnimation = clips[label]
		if clip == null:
			continue
		var pairs := [["down", clip.down, "up", clip.up],
			["down", clip.down, "side", clip.side],
			["up", clip.up, "side", clip.side]]
		for pair in pairs:
			var a: Texture2D = pair[1]
			var b: Texture2D = pair[3]
			if a == null or b == null:
				continue
			if a.get_image().get_data() == b.get_image().get_data():
				same.append("%s %s==%s" % [label, pair[0], pair[2]])
	_check("north, south and east are three different pictures", same.is_empty(),
		", ".join(same))


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
	for action in [&"move_up", &"move_down", &"move_left", &"move_right", &"attack",
			&"dodge", &"tool", &"interact"]:
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
	# Attacks aim at the cursor now, and a headless run has one at (0, 0). Every
	# combat assertion below is about frame data rather than about aiming, so
	# the aim is pinned rather than left to the pointer.
	_player.aim_override = Vector2.RIGHT
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
	# Stretch is off: the world is scaled by its own SubViewport
	# (`ui/world_view.gd`) and the UI is laid out at the window's real
	# resolution. Letting the engine stretch both would put 720p text on a 1440p
	# monitor, which is the thing the split exists to stop.
	_check(
		"engine stretch is off; the world scales itself",
		ProjectSettings.get_setting("display/window/stretch/mode") == "disabled"
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

	# You aim the swing with the cursor (`Player.aim_direction`), so the swing
	# belongs on the button under the hand already holding the cursor. J stays —
	# a keyboard-only player should not have to move their right hand — but left
	# click is the one people will reach for first.
	#
	# Safe because every surface that wants a left click for its own purposes
	# pauses the tree first: the dialogue box, the game menu and the pause menu
	# all set `paused = true`, and the player's state machine does not run while
	# paused. The HUD is not clickable at all. Without that, clicking a dialogue
	# reply would also swing a sword.
	var attack_mouse: Array[int] = []
	var attack_keys: Array[int] = []
	for event in InputMap.action_get_events(&"attack"):
		var click := event as InputEventMouseButton
		if click != null:
			attack_mouse.append(click.button_index)
		var pressed := event as InputEventKey
		if pressed != null:
			attack_keys.append(pressed.physical_keycode)
	_check("attack is on left click", attack_mouse.has(MOUSE_BUTTON_LEFT), "%s" % [attack_mouse])
	_check("and still on the keyboard", attack_keys.has(KEY_J), "%s" % [attack_keys])
	# That the click-consuming surfaces pause is asserted where they are opened —
	# `dialogue_test` checks `get_tree().paused` while a conversation is up, and
	# the menu tests do the same. Restating it here would be a second copy of a
	# fact rather than a second check of it.


## The type scale, checked against the font actually shipped.
##
## **This replaced a grid assertion.** The old one proved every allowed size was
## a whole multiple of 16 and that 20 was measurably *not* — which was the right
## check while the body face was a 16-unit pixel font and the scale existed to
## police that divisor. It is the wrong check now: the interface is a separate
## layer from the pixel-art world, the scale is chosen to read well rather than
## to divide cleanly, and Perfect DOS VGA 437 measures linearly at every size,
## so the old negative case could never fire again.
##
## What is worth asserting instead is the thing a scale is actually for: that
## the sizes are distinct on screen, in order, and all render.
func _test_type_scale() -> void:
	print("\nType scale (ui/type_scale.gd)")
	var font: Font = ThemeDB.fallback_font
	_check("the UI has a font", font != null)
	if font == null:
		return

	const SAMPLE := "Hamburgefonstiv 0123"
	var widths: Array[float] = []
	var dead: Array[String] = []
	for size in TypeScale.ALL:
		var w := font.get_string_size(SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		if w <= 0.0:
			dead.append("%d renders nothing" % size)
		widths.append(w)
	_check("every size in the scale renders", dead.is_empty(), ", ".join(dead))

	await _drawn_text_is_ascii()

	# Ordered and distinct. A scale with two steps that measure the same is a
	# scale with a step nobody can see, which is how 16 and 20 would look if the
	# font ever went back to snapping onto a grid.
	var muddled: Array[String] = []
	for i in range(1, widths.size()):
		if widths[i] <= widths[i - 1]:
			muddled.append("%d is not wider than %d" % [TypeScale.ALL[i], TypeScale.ALL[i - 1]])
	_check("and each is visibly bigger than the last", muddled.is_empty(),
		", ".join(muddled))
	# The step this whole change was made for. Under the old scale there was
	# nothing between body and heading, so a sub-heading had to be the same size
	# as the sentence under it.
	_check("there is a step between body and heading",
		TypeScale.SMALL < TypeScale.MEDIUM and TypeScale.MEDIUM < TypeScale.HEADING,
		"%d < %d < %d" % [TypeScale.SMALL, TypeScale.MEDIUM, TypeScale.HEADING])

	# `snap` picks the nearest step rather than rounding onto a divisor, so
	# nothing can invent a size that is not in the scale.
	_check("snap() lands on a real step",
		TypeScale.ALL.has(TypeScale.snap(21)) and TypeScale.ALL.has(TypeScale.snap(1))
		and TypeScale.snap(19) == TypeScale.MEDIUM and TypeScale.snap(1) == TypeScale.TINY,
		"21->%d, 19->%d, 1->%d" % [TypeScale.snap(21), TypeScale.snap(19), TypeScale.snap(1)])

	# ...and nothing anywhere gets a weight invented for it.
	#
	# Asked for a bold it does not have, Godot *emboldens* — smearing every glyph
	# sideways by a fraction of a pixel; asked for an italic, it *shears* them off
	# the grid. Both are fine on a vector typeface and both turn a pixel font to
	# mush, and it was the item description pane where it showed up.
	#
	# The rule is not "every slot is the same face" — that was the old rule, from
	# when no face in the project had a bold. Pixel Operator ships a drawn one, so
	# bold is now a *different* file and that is the point of it. The rule is that
	# every slot resolves to a real file:
	#
	#   bold          -> a drawn bold, not the regular smeared
	#   italic        -> the regular, because no pixel font here has an italic
	#   bold italic   -> the drawn bold, for the same reason
	#
	# What would fail is a slot resolving to nothing, which is when Godot falls
	# back to synthesising.
	var rich := RichTextLabel.new()
	add_child(rich)
	var normal := rich.get_theme_font(&"normal_font")
	var faked: Array[String] = []
	for slot in [&"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		if rich.get_theme_font(slot) == null:
			faked.append(String(slot))
	_check("rich text has a font at all", normal != null)
	_check("every weight resolves to a real face rather than a synthesised one",
		faked.is_empty(),
		", ".join(faked))
	_check("italic is the regular face, because no pixel font here has one",
		rich.get_theme_font(&"italics_font") == normal)
	_check("and bold is a drawn bold rather than the regular",
		rich.get_theme_font(&"bold_font") != normal)
	rich.queue_free()


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


## The swing you can see, and the swing that can hurt you, running off one clock.
##
## Worth pinning because the failure is quiet: a blade that renders nothing at
## all still passes every frame-data check above, and the hitbox keeps working
## while the game stops telling anyone a hundredth of a second before it lands.
func _test_weapon_arc() -> void:
	print("\nWeapon arc (GDD §5: the streak is what makes 0.10s legible)")
	await _reset_player()

	var arc := _player.weapon_arc
	_check("player carries a weapon arc", arc != null)
	if arc == null:
		return
	_check("arc is hidden at rest", not arc.visible)

	await _press(&"attack")
	if not await _await_state(&"Attack"):
		_check("arc test could not start", false)
		return

	_check("arc appears on the swing", arc.visible)
	_check("arc aims where the player faces",
		absf(angle_difference(arc.centre_angle(), _player.facing.angle())) < 0.01,
		"arc %.2f vs facing %.2f" % [arc.centre_angle(), _player.facing.angle()])

	# Still up while the hitbox is live: a streak that finishes before the
	# dangerous frames do is a streak that lies about when you are safe.
	var seen_with_hitbox := false
	for i in 60:
		await get_tree().physics_frame
		if _player.hitbox.is_active() and arc.visible:
			seen_with_hitbox = true
		if not _player.state_machine.is_in(&"Attack"):
			break
	_check("arc is still drawn during the active frames", seen_with_hitbox)
	_check("arc clears when the swing ends", not arc.visible)


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
	print("\nStamina (GDD §6 as amended: dodge only, 4 dodges, 6s refill)")
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

	# Regen waits `regen_delay` before it starts, then takes `full_regen_time`.
	# Read off the component rather than hard-coded: this number is explicitly a
	# tuning knob (GDD §6 asks for it to be validated by hand), and a test that
	# pins it to a literal turns every tuning pass into a test edit.
	var refill: float = _player.stamina.full_regen_time
	var settle: int = int((_player.stamina.regen_delay + refill) / TICK) + 20
	await _ticks(settle)
	_check_near("refills in full_regen_time after the delay", _player.stamina.current, 4.0, 0.05)
	# The number itself, so a slip back to something that refills instantly is
	# caught rather than absorbed.
	_check("and that is slow enough for the pool to mean something", refill >= 4.0,
		"%.1fs" % refill)
	_check("and the delay is real", _player.stamina.regen_delay > 0.0,
		"%.2fs" % _player.stamina.regen_delay)

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


	# Sprinting: hold the dash key while moving. This is the first thing in the
	# game that makes the stamina pool bind at all — the cooldown was already
	# doing the anti-panic-roll job on its own (docs/M1-NOTES.md).
	await _reset_player()
	_player.stamina.refill()
	_hold(&"move_right")
	await _ticks(20)
	var walk := _player.motion_velocity.length()
	_hold(&"dodge")
	await _ticks(2)
	# The tap becomes a dodge; wait it out, then the hold becomes a sprint.
	await _ticks(40)
	var sprint := _player.motion_velocity.length()
	_check("holding dash sprints", _player.sprinting and sprint > walk * 1.2,
		"walk %.0f -> sprint %.0f" % [walk, sprint])
	var fuel := _player.stamina.current
	await _ticks(30)
	_check("and it costs stamina", _player.stamina.current < fuel,
		"%.2f -> %.2f" % [fuel, _player.stamina.current])
	# Run it dry and the sprint has to end rather than become free movement.
	for i in 12:
		await _ticks(30)
		if not _player.sprinting:
			break
	_check("an empty pool ends the sprint", not _player.sprinting,
		"stamina %.2f" % _player.stamina.current)
	_release_all()
	await _reset_player()
	_player.stamina.refill()


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

	# Measured with nothing equipped, so this stays a check on GDD §5's frame
	# data rather than on whatever sword the player happens to start with. The
	# weapon's contribution is asserted immediately below, and in
	# `_test_equipment`.
	var sword := _player.equipment.unequip(ItemData.Slot.WEAPON)
	await _ticks(2)
	await _press(&"attack")
	await _await_state(&"Attack")
	await _ticks(30)
	var bare := before - enemy.health.current
	_check("hit 1 deals 4 damage", bare == 4, "%d → %d" % [before, enemy.health.current])

	# One activation must not tick twice over its 0.10s active window.
	_check("no double-hit within one swing", enemy.health.current == before - 4)

	# ...and the weapon reaches the hitbox. Damage and reach were both being
	# computed, shown on the character sheet, and then thrown away — so a forge
	# and a sword were decoration: the numbers moved and nothing died faster.
	if sword != null:
		@warning_ignore("return_value_discarded")
		_player.equipment.equip(sword)
		await _ticks(2)
		var armed := enemy.health.current
		await _press(&"attack")
		await _await_state(&"Attack")
		await _ticks(30)
		var with_sword := armed - enemy.health.current
		_check("and an equipped weapon adds its damage to the swing",
			with_sword == bare + int(sword.modifiers.get(&"damage", 0)),
			"%d bare vs %d armed" % [bare, with_sword])

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
	_check("enemy is on screen", enemy.is_on_screen(),)

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
		# Run a little past Recover now, to see where it goes next.
		if seen.has(&"Circle"):
			break

	_check("enemy chases", seen.has(&"Chase"))
	_check("enemy telegraphs before attacking", seen.has(&"Telegraph"))
	_check("enemy lunges", seen.has(&"Lunge"))
	_check("enemy recovers, giving the player a turn", seen.has(&"Recover"))
	# ...and then gives ground rather than walking straight back in. Without
	# this a pack arrives in single file: separation shoves the second and third
	# apart, chase pulls them back onto the same line, and three wolves are one
	# wolf three times.
	_check("and then circles instead of re-engaging on the spot", seen.has(&"Circle"),
		str(seen.keys()))

	# The circle has to sit outside the reach it is waiting on, or it is not a
	# retreat and the player's window closes early.
	var circling := enemy.state_machine.get_node_or_null("Circle") as EnemyState
	_check("the circle state exists", circling != null)
	_check("and holds further out than the attack range",
		enemy.data.attack_range * enemy.data.circle_radius_scale > enemy.data.attack_range)

	# The bar appears when you hurt something, and not before.
	var bar := enemy.get_node_or_null("HealthBar") as EnemyHealthBar
	_check("an enemy carries a health bar", bar != null)
	if bar != null:
		_check("which stays hidden until the player earns it", not bar.is_showing())
		enemy.health.take_damage(1, _player)
		await _ticks(2)
		_check("and shows once it is hurt", bar.is_showing())
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

	# Picking the right strip is worth nothing if the strips are the same
	# picture. They were: the generator composited the front-facing body into
	# every direction, so the character walked north facing the camera and every
	# check above still passed. Compare the pixels.
	_check_distinct_directions(set)
	_check_eight_way(set)
	await _check_flash_is_off_by_default()

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


## Experience, and the guard rail that comes with it.
##
## The last check is the important one. GDD §15 A7 said there was no XP; there
## is now, and the thing A7 was really protecting is that a level hands out
## nothing — the village is still the only route to a bigger number. That is a
## rule that decays the moment someone adds a convenient exception, so it is
## asserted rather than written down.
func _test_experience() -> void:
	print("\nExperience (GDD §15 A10: levels exist and they buy a point)")
	await _reset_player()

	var xp := _player.experience
	_check("player carries an experience component", xp != null)
	if xp == null:
		return

	xp.current = 0
	xp.level = 1
	var need := xp.needed()
	_check("a fresh character is level 1 with nothing banked", xp.level == 1 and xp.current == 0)

	var seen: Array = []
	var on_changed := func(current: int, needed: int, level: int) -> void:
		seen.append([current, needed, level])
	xp.changed.connect(on_changed)

	xp.grant(need - 1)
	_check("points accumulate", xp.current == need - 1 and xp.level == 1,
		"%d/%d at level %d" % [xp.current, xp.needed(), xp.level])
	_check("granting announces itself", seen.size() == 1)

	xp.grant(1)
	_check("crossing the threshold levels up", xp.level == 2, "level %d" % xp.level)
	_check("the remainder carries, it does not reset", xp.current == 0, str(xp.current))
	_check("the next level costs more", xp.needed() > need,
		"%d vs %d" % [xp.needed(), need])

	# A single fat award must not be quietly capped at one level.
	var before := xp.level
	xp.grant(xp.needed() * 4)
	_check("one large award can cross several levels", xp.level > before + 1,
		"level %d from %d" % [xp.level, before])

	xp.grant(-50)
	_check("a negative award does nothing", xp.current >= 0)
	xp.changed.disconnect(on_changed)

	# A8 asserted that levelling grants nothing, and named the risk of that in
	# the same breath. A10 takes the risk's side: a level now grants a point.
	# The guard is retired by being *rewritten*, not deleted — the rule it was
	# really protecting is the one below it, and that one still holds.
	Skills.reset()
	var stats_before := _player.stat_block().duplicate()
	var points_before := Skills.points()
	xp.grant(xp.needed())
	await _ticks(2)
	_check("levelling grants a skill point", Skills.points() > points_before,
		"%d -> %d" % [points_before, Skills.points()])
	_check("but the point alone moves no stat", _player.stat_block() == stats_before,
		"a point is a currency, not a stat — spending it is a separate act")

	# ...and the rule A7 actually existed to protect, which survives every
	# amendment: nothing moves a number without saying what moved it.
	_check("a modifier still needs a source", not _player.stats.apply(&"", {"damage": 5}))
	await _test_skill_tree()


## Skills: what a point buys, and the accounting around it.
func _test_skill_tree() -> void:
	print("\nSkills (GDD §15 A10: a level buys a point, a point buys a skill)")
	Skills.reset()
	Skills.apply_all(_player.stats)

	var tree := Skills.all()
	_check("there is a tree to spend in", tree.size() >= 6, "%d skills" % tree.size())

	var broken: Array[String] = []
	for skill in tree:
		var entry: SkillData = skill
		if entry.requires != &"" and Skills.get_skill(entry.requires) == null:
			broken.append("%s needs missing '%s'" % [entry.id, entry.requires])
	_check("every prerequisite names a skill that exists", broken.is_empty(),
		", ".join(broken))

	# The tab draws icons, so a skill without one is a blank frame in the tree.
	# This is what a renamed def left behind: `recovery.tres` outlived its
	# rename to `steady`, kept being scanned, and drew a tenth, icon-less node
	# in a branch that should fork two ways. Nothing here talked about shape, so
	# nothing caught it — every other assertion in this function asks `Skills`
	# about one id it already knows the name of.
	var iconless: Array[String] = []
	var names: Dictionary = {}
	var duplicate_names: Array[String] = []
	var roots: Dictionary = {}
	for skill in tree:
		var entry: SkillData = skill
		if entry.icon == null:
			iconless.append(String(entry.id))
		if names.has(entry.display_name):
			duplicate_names.append("%s and %s are both '%s'"
				% [names[entry.display_name], entry.id, entry.display_name])
		names[entry.display_name] = String(entry.id)
		if entry.requires == &"":
			roots[entry.branch] = roots.get(entry.branch, 0) + 1
	_check("every skill has an icon to draw", iconless.is_empty(),
		", ".join(iconless))

	# Two skills sharing a name is the signature of a def that was renamed by
	# copy rather than by move — the old file is still there.
	_check("no two skills share a display name", duplicate_names.is_empty(),
		", ".join(duplicate_names))

	# A branch is drawn top-down from a single root. Two roots in one branch
	# would render as two unjoined trees stacked in one column.
	var multi_rooted: Array[String] = []
	for branch in roots:
		if roots[branch] != 1:
			multi_rooted.append("branch %d has %d roots" % [branch, roots[branch]])
	_check("each branch grows from exactly one root", multi_rooted.is_empty(),
		", ".join(multi_rooted))

	# Nothing is free.
	_check("a skill cannot be taken with no points", not Skills.can_unlock(&"edge"))
	Skills.grant(1)
	_check("a point makes the first tier available", Skills.can_unlock(&"edge"))
	_check("but not the second", not Skills.can_unlock(&"long_arm"),
		"long_arm requires edge")

	var damage_before: int = _player.stats.bonus(StatsComponent.DAMAGE)
	_check("taking it works", Skills.unlock(&"edge", _player.stats))
	_check("the point is spent", Skills.points() == 0, "%d" % Skills.points())
	_check("and the stat moved", _player.stats.bonus(StatsComponent.DAMAGE) > damage_before,
		"%d -> %d" % [damage_before, _player.stats.bonus(StatsComponent.DAMAGE)])
	# The rule that survives A7: every number names what granted it.
	_check("under a source that names the skill",
		_player.stats.sources().has(StringName("skill:edge")),
		str(_player.stats.sources()))
	_check("it cannot be taken twice", not Skills.unlock(&"edge", _player.stats))

	Skills.grant(1)
	_check("the prerequisite now unlocks the next tier", Skills.can_unlock(&"long_arm"))

	# Survives a save, and survives being re-pushed into a fresh component —
	# which is what happens every time the player walks into another scene.
	var saved := Skills.save_data()
	Skills.reset()
	_check("a reset forgets them", not Skills.is_unlocked(&"edge"))
	Skills.load_data(saved)
	_check("a load remembers them", Skills.is_unlocked(&"edge"))
	Skills.apply_all(_player.stats)
	_check("and re-applies them to a fresh sheet",
		_player.stats.sources().has(StringName("skill:edge")))

	Skills.reset()
	Skills.apply_all(_player.stats)
	_check("clearing the tree takes the stat back with it",
		not _player.stats.sources().has(StringName("skill:edge")),
		str(_player.stats.sources()))


## Worn gear, and the rule that keeps GDD §15 A7 alive through the amendment
## that let equipment write stats at all (A9).
func _test_equipment() -> void:
	print("\nEquipment (GDD §15 A9: worn gear writes stats, and always names itself)")
	await _reset_player()
	var gear := _player.equipment

	_check("the player starts with something to swing",
		gear.item_in(ItemData.Slot.WEAPON) != null,
		String(gear.item_in(ItemData.Slot.WEAPON).id) if gear.item_in(ItemData.Slot.WEAPON) != null else "-")

	# The library is scanned, not listed, so the only thing that can go wrong is
	# a `.tres` that loads but is not a usable item — which `Items` warns about
	# and then skips, quietly, leaving a hole nobody notices until an id fails
	# to resolve out of somebody's save file.
	var broken: Array[String] = []
	var edible := 0
	for id in Items.all():
		var item: ItemData = Items.get_item(id)
		if item == null or not item.is_valid() or item.icon == null:
			broken.append(String(id))
			continue
		if item.kind == ItemData.Kind.CONSUMABLE and item.heals > 0:
			edible += 1
	_check("every item in the library is usable and has an icon", broken.is_empty(),
		", ".join(broken))

	# **And every def on disk actually made it into the library.**
	#
	# The check above iterates what loaded, so it is structurally blind to a def
	# that did not — `Items._scan` pushes a warning and skips it, and a warning
	# in a headless run is a line nobody reads. `wolf_fang` sat like that for two
	# commits: its `.tres` pointed at an icon filename that the art import had
	# spelled differently, so the resource failed to parse, the item vanished,
	# and the wolf's loot table quietly referenced something that did not exist.
	#
	# Counting the files is the only way to see a hole where an item should be.
	var on_disk := 0
	var defs := DirAccess.open("res://resources/items/defs")
	if defs != null:
		for file in defs.get_files():
			var trimmed := file.trim_suffix(".remap")
			if trimmed.ends_with(".tres") or trimmed.ends_with(".res"):
				on_disk += 1
	_check("and no item def failed to load on the way in",
		on_disk > 0 and Items.count() == on_disk,
		"%d on disk, %d in the library" % [on_disk, Items.count()])
	_check("and there is a decent spread of things to eat", edible >= 20, "%d" % edible)
	# GDD §5: 6 hearts to start. A single meal that fills the bar is not a
	# decision, so nothing may heal more than half of it.
	var too_strong: Array[String] = []
	for id in Items.all():
		var item: ItemData = Items.get_item(id)
		if item != null and item.heals > 3:
			too_strong.append("%s heals %d" % [id, item.heals])
	_check("no single meal is worth more than half a starting health bar",
		too_strong.is_empty(), ", ".join(too_strong))

	var hood: ItemData = Items.get_item(&"leather_hood")
	_check("there is a piece of armour to test with", hood != null)
	if hood == null:
		return

	var before := _player.health.max_health
	@warning_ignore("return_value_discarded")
	gear.equip(hood)
	await _ticks(2)
	_check("wearing it moves the stat it says it moves",
		_player.health.max_health == before + int(hood.modifiers.get(&"max_health", 0)),
		"%d -> %d" % [before, _player.health.max_health])
	_check("and the modifier names its slot, not nothing",
		_player.stats.has_source(StringName(EquipmentComponent.SOURCE_PREFIX
			+ str(ItemData.Slot.ARMOUR))))

	# The bug this guards is swapping: sourced by item rather than by slot, the
	# first hood's bonus would stay applied forever and the second would look
	# unusually good.
	var sources := _player.stats.sources().size()
	@warning_ignore("return_value_discarded")
	gear.equip(hood)
	_check("re-equipping does not stack a second source",
		_player.stats.sources().size() == sources, "%d sources" % _player.stats.sources().size())

	@warning_ignore("return_value_discarded")
	gear.unequip(ItemData.Slot.ARMOUR)
	await _ticks(2)
	_check("taking it off takes the stat off with it",
		_player.health.max_health == before, "%d" % _player.health.max_health)
	_check("and revokes the source", not _player.stats.has_source(
		StringName(EquipmentComponent.SOURCE_PREFIX + str(ItemData.Slot.ARMOUR))))

	# A9 amends A7's "every source is a building"; it does **not** amend the
	# rule underneath it, which is that nothing moves a number anonymously.
	_check("an anonymous modifier is still refused", not _player.stats.apply(&"", {"damage": 5}))


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
	_player.experience.grant(17)
	var saved_position := _player.global_position
	var saved_health := _player.health.current
	var saved_xp := _player.experience.current
	var saved_level := _player.experience.level

	_check("save writes", SaveGame.save_slot(SLOT), SaveGame.last_error())
	_check("slot now exists", SaveGame.has_save(SLOT))

	_player.global_position = Vector2(10, 10)
	_player.facing = Vector2.DOWN
	_player.health.heal(99)
	_player.experience.current = 0
	_player.experience.level = 99

	_check("load reads back", SaveGame.load_slot(SLOT), SaveGame.last_error())
	_check("position restored", _player.global_position.is_equal_approx(saved_position),
		str(_player.global_position))
	_check("facing restored", _player.facing.is_equal_approx(Vector2.LEFT))
	_check("health restored", _player.health.current == saved_health,
		"%d vs %d" % [_player.health.current, saved_health])
	_check("experience restored", _player.experience.current == saved_xp
		and _player.experience.level == saved_level,
		"%d at level %d" % [_player.experience.current, _player.experience.level])
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
	# A floor rather than an equality. This pinned 20 and broke the day the
	# general store was added — which is the assertion doing nothing useful and
	# charging for it: what matters is that the village is populated, not that
	# it has exactly the number of buildings it had on the day this was written.
	_check("the village is full of places", plots.size() + pois.size() >= 20,
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
	_test_village_state(level)
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
	for child in level.world.get_children():
		var door := child as Doorway
		if door != null:
			doors.append(door)
	# A floor and a uniqueness check rather than a pinned count. The literal 4
	# broke when the general store was added, which is an assertion that fires
	# on *content* rather than on breakage. Two doors pointing at the same
	# interior is the real bug here — it is what a copy-pasted table entry looks
	# like, and it would send you into somebody else's house.
	_check("every interior is reachable", doors.size() >= 4, "%d" % doors.size())
	var seen_targets := {}
	var duplicated: Array[String] = []
	for door in doors:
		if seen_targets.has(door.target_scene):
			duplicated.append(door.target_scene)
		seen_targets[door.target_scene] = true
	_check("and no two doors lead to the same room", duplicated.is_empty(),
		", ".join(duplicated))
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
	_check("the world renders into its own 1280x720 viewport",
		level.world.get_viewport() is SubViewport
			and level.world.get_viewport().size == WorldView.BASE,
		"%s" % [level.world.get_viewport().size if level.world.get_viewport() else null])
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
	# Wraps within the hotbar row, not the whole forty-slot pack — the wheel is a
	# bar control and should not walk off the end of the visible row.
	_check("and wraps within the hotbar rather than into the pack",
		kit.selected == ItemsComponent.HOTBAR_SLOTS - 2, "slot %d" % kit.selected)
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

	# Tab, and the two menus not fighting over who owns time.
	GameMenu.open()
	await _ticks(1)
	_check("tab opens the character menu", GameMenu.is_open() and get_tree().paused)
	_check("the sheet was pushed to it, not fetched",
		not GameMenu.stats.is_empty() and int(GameMenu.stats.get("max_health", 0)) > 0,
		"%s" % [GameMenu.stats.get("max_health", 0)])
	PauseMenu.open()
	_check("escape does not stack a second menu on top", not PauseMenu.is_open())
	GameMenu.close()
	await _ticks(1)
	_check("and closing it gives time back", not get_tree().paused and Hud.enabled)

	# UI scale is whole-number only. A 1.5x interface duplicates every other row
	# of pixels, which is the softness the viewport split exists to remove.
	var was := UiScale.factor
	UiScale.factor = 99.0
	_check("ui scale is clamped, not trusted",
		is_equal_approx(UiScale.factor, UiScale.MAX_FACTOR), "%.1f" % UiScale.factor)
	UiScale.factor = 1.37
	_check("and snapped to a step, not honoured",
		is_equal_approx(UiScale.factor, 1.5), "%.2f" % UiScale.factor)
	UiScale.factor = 1.5
	await _ticks(1)
	_check("and it scales the layers it was given",
		Hud.scale.is_equal_approx(Vector2(1.5, 1.5)), "%s" % Hud.scale)
	UiScale.factor = was
	await _ticks(1)

	# The inventory grid describes what you point at, and falls back to the
	# selected slot so the pane is never blank on a pad.
	level.player.items.add(Items.get_item(&"stew"), 2)
	# Found rather than assumed. This asserted slot 1 until the starting kit
	# gained a second entry and pushed the stew along one — the check is about
	# hovering describing what is there, not about where the kit happens to put
	# things.
	var stew_slot := -1
	for i in level.player.items.items.size():
		if level.player.items.item_at(i) != null and level.player.items.item_at(i).id == &"stew":
			stew_slot = i
			break
	GameMenu.open()
	await _ticks(1)
	GameMenu._on_slot_hover(stew_slot, true)
	_check("hovering a slot describes it", GameMenu._detail.text.contains("Meat stew"),
		"slot %d: %s" % [stew_slot, GameMenu._detail.text.strip_edges().substr(0, 40)])
	GameMenu._on_slot_hover(stew_slot, false)
	level.player.items.select(0)
	GameMenu._on_slot_hover(-1, false)
	_check("and with nothing hovered it falls back to the selected slot",
		GameMenu._detail.text.contains("loaf"),
		GameMenu._detail.text.strip_edges().substr(0, 40))
	GameMenu.close()
	await _ticks(1)

	# GDD §15 A7: the village is the only thing that writes to the sheet.
	var sheet: StatsComponent = level.player.stats
	_check("a modifier with no source is refused",
		not sheet.apply(&"", {StatsComponent.DAMAGE: 99}))
	var before_carry := level.player.inventory.capacity
	sheet.apply(&"market", {StatsComponent.CARRY: 6})
	await _ticks(1)
	_check("a building raises the number it grants",
		level.player.inventory.capacity == before_carry + 6,
		"%d -> %d" % [before_carry, level.player.inventory.capacity])
	_check("and the sheet says which building",
		GameMenu.stats.get("granted_by", []).has(&"market"))
	sheet.apply(&"market", {StatsComponent.CARRY: 6})
	await _ticks(1)
	_check("applying it twice does not stack",
		level.player.inventory.capacity == before_carry + 6,
		"%d" % level.player.inventory.capacity)
	# Recovery is upgradeable, and applied as a ratio so it cannot compound.
	var delay_before := level.player.stamina.regen_delay
	sheet.apply(&"apothecary", {StatsComponent.STAMINA_REGEN: 100})
	await _ticks(1)
	_check("a building can speed stamina recovery",
		is_equal_approx(level.player.stamina.regen_delay, delay_before * 0.5),
		"%.2fs -> %.2fs" % [delay_before, level.player.stamina.regen_delay])
	sheet.apply(&"apothecary", {StatsComponent.STAMINA_REGEN: 100})
	await _ticks(1)
	_check("and re-applying it does not compound",
		is_equal_approx(level.player.stamina.regen_delay, delay_before * 0.5),
		"%.2fs" % level.player.stamina.regen_delay)
	sheet.revoke(&"apothecary")
	await _ticks(1)

	sheet.revoke(&"market")
	await _ticks(1)
	_check("un-building it takes exactly that back",
		level.player.inventory.capacity == before_carry)
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
	_check("overhead is above both", overhead != null
		and overhead.z_index > level.player.z_index)
	# It carries the roofs now. Without them a building is an open-topped box
	# and the village reads as a floor plan.
	_check("and it carries the roofs", overhead != null
		and overhead.get_used_rect().size != Vector2i.ZERO)
	# The other half of that: overhead draws above the actors unconditionally, so
	# a tile of it over ground the player can stand on erases them from the waist
	# down. `tools/build_greybox.gd` refuses to write one; this checks the tile
	# the player is actually standing on, which is the case that matters.
	_check("and none of it is over the tile the player is standing on",
		overhead != null and overhead.get_cell_atlas_coords(
			overhead.local_to_map(overhead.to_local(level.player.global_position))
		) == Vector2i(-1, -1))

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

	_check_circling()
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


## **Nothing drawn on screen may contain a character above ASCII.**
##
## The body font is Perfect DOS VGA 437, and it is a CP437 face wearing CP1252
## labels: glyph id is the CP1252 byte minus one, and the picture at that index
## is whatever CP437 draws there. So the cmap cheerfully reports U+2014 as
## present — and renders it as `ù`, because CP437 0x97 is `ù`. Middle dot comes
## out as a piece of box-drawing. The font does not fail; it substitutes, which
## is much worse, because it never says a word about it.
##
## This shipped twice before it got a check: an em-dash in the level-up banner,
## and then an em-dash and two middle dots in the inventory and the shop. Both
## were found by looking at a screenshot, which is not a method.
##
## Scoped to `ui/`, which is exactly the layer that draws things. Tools and tests
## print to a console in whatever font the terminal has and are none of this
## check's business. Comments are skipped: this is about what the player sees.
func _drawn_text_is_ascii() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	var dir := DirAccess.open("res://ui")
	if dir == null:
		# Source is not readable from an exported build. Nothing to check rather
		# than a failure — this runs from the repo, which is where it matters.
		_check("the drawn strings could be read", true, "no res://ui to scan")
		return
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var handle := FileAccess.open("res://ui/%s" % file, FileAccess.READ)
		if handle == null:
			continue
		var line_number := 0
		while not handle.eof_reached():
			var line := handle.get_line()
			line_number += 1
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue
			for literal in _string_literals(line):
				scanned += 1
				for i in literal.length():
					if literal.unicode_at(i) > 0x7E:
						offenders.append("%s:%d %s" % [file, line_number,
							literal.substr(0, 32)])
						break
		handle.close()
	_check("every string the UI draws is ASCII, which is all the font has",
		offenders.is_empty(), "; ".join(offenders))
	_check("and there were strings to check", scanned > 50, "%d literals" % scanned)


## Double-quoted literals in one line of GDScript. Crude on purpose: it does not
## understand escapes or `"""`, and a false positive here costs one apostrophe.
static func _string_literals(line: String) -> Array[String]:
	var out: Array[String] = []
	var inside := false
	var start := 0
	for i in line.length():
		if line.unicode_at(i) != 0x22:
			continue
		if i > 0 and line.unicode_at(i - 1) == 0x5C:
			continue
		if inside:
			out.append(line.substr(start, i - start))
			inside = false
		else:
			inside = true
			start = i + 1
	return out
