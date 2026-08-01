extends Node
## Does the interface fit on the screen it is being drawn on.
##
##     godot --headless --path . tests/ui_fit_test.tscn
##
## Its own scene rather than a section of `m1_smoke_test`, because every check
## in here works by moving the content rect out from under the whole UI — and a
## test that resizes the world halfway through is a bad neighbour to the ones
## measuring hitboxes.
##
## **Two real bugs, one report.** A screenshot came back at high resolution with
## the inventory running off the bottom of the screen and "a lot of text
## misaligned". They turned out to be unrelated:
##
## - `UiScale.suggested()` snaps to the *nearest* half step, so it rounds up. A
##   1600x900 window measures 1.25 and was handed 1.5, which left the menu a
##   1066x600 box to lay 1229x702 of inventory out in. 1366x768 and 1440x900
##   round up the same way. 1080p and 1440p land exactly on a step, which is why
##   this went unnoticed for so long — the two resolutions anyone tests at are
##   the two it happens to get right.
## - The vitals block padded its values across with spaces to a fourteen-
##   character field. The column is 176px of usable width and the DOS VGA face
##   advances 9px a character, so nineteen characters fit and the rows ran to
##   twenty-five. Four of the seven wrapped.
##
## Both are the same *kind* of mistake — a size assumed rather than measured —
## so both are checked the same way here: lay it out, then ask the layout.

const MENU_SIZES: Array[Vector2] = [
	Vector2(1280, 720),    # the box the menus are drawn in, exactly
	Vector2(1366, 768),    # rounds up to 1.5 under the old rule
	Vector2(1440, 900),    # ditto
	Vector2(1600, 900),    # ditto, and the one in the report
	Vector2(1920, 1080),
	Vector2(1920, 1200),
	Vector2(2560, 1080),   # wide and short: the height is the binding axis
	Vector2(2560, 1440),
	Vector2(3440, 1440),   # ultrawide: the width is not
	Vector2(3840, 2160),
]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	Engine.max_fps = 250
	_run.call_deferred()


func _run() -> void:
	print("\n=== Blightfall UI fit test ===\n")
	await _test_menu_scale()
	await _test_menus_fit()
	await _test_vitals_do_not_wrap()
	print("\n%d checks, %d failed\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])


## Point the whole interface at a window of this size and let it settle.
func _at(size: Vector2) -> void:
	UiScale.set_content_rect(Rect2(Vector2.ZERO, size))
	await get_tree().process_frame
	await get_tree().process_frame


# ------------------------------------------------------------------ the scale

## The invariant, stated once: **a menu layer's root is never smaller than the
## box the menus are laid out in.** Everything else about the scale is taste;
## this one is the difference between a menu and a menu with its bottom row off
## the screen.
func _test_menu_scale() -> void:
	print("-- menu scale")
	for size in MENU_SIZES:
		await _at(size)
		var used := UiScale.menu_scale()
		var box := size / used
		_check("%.0fx%.0f leaves room for the menu box" % [size.x, size.y],
			box.x >= UiScale.MENU_DESIGN.x and box.y >= UiScale.MENU_DESIGN.y,
			"%.1fx -> %.0fx%.0f" % [used, box.x, box.y])

	# The step is worth having and this is the check that keeps it: floor to a
	# half, never a fit that lands on 1.37.
	await _at(Vector2(2560, 1440))
	_check("a 1440p window gets a whole 2x", is_equal_approx(UiScale.menu_scale(), 2.0),
		"%.2f" % UiScale.menu_scale())
	await _at(Vector2(1920, 1080))
	_check("a 1080p window gets 1.5x", is_equal_approx(UiScale.menu_scale(), 1.5),
		"%.2f" % UiScale.menu_scale())

	# Below the design box there is no honest step, so it stops stepping. Better
	# a slightly soft menu that fits than a crisp one with its buttons off-screen.
	await _at(Vector2(1024, 600))
	var small := UiScale.menu_scale()
	_check("a window under the design box shrinks to fit rather than snapping",
		small < 1.0 and small >= UiScale.MENU_MIN_FACTOR, "%.2f" % small)


# ------------------------------------------------------------------ the layout

## The scale being right is a claim about arithmetic. This is the claim about
## pixels: open the menu, on every page, and look for anything hanging over an
## edge.
func _test_menus_fit() -> void:
	print("\n-- the character menu on screen")
	GameMenu.stats = _stats()
	for size in MENU_SIZES:
		await _at(size)
		GameMenu.open()
		await get_tree().process_frame
		var root := _root_of(GameMenu)
		var tabs := _tabs_of(root)
		var spills: Array[String] = []
		for page in tabs.get_tab_count():
			tabs.current_tab = page
			await get_tree().process_frame
			await get_tree().process_frame
			for child in root.get_children():
				if child is not Control or child is ColorRect:
					continue
				spills.append_array(_spill(tabs.get_tab_title(page), child as Control, root.size))
		GameMenu.close()
		await get_tree().process_frame
		_check("%.0fx%.0f: nothing hangs off an edge" % [size.x, size.y],
			spills.is_empty(), ", ".join(spills))


## Which edges `control` runs past, and by how much, named one at a time.
##
## Its **minimum** size rather than its laid-out one: a Control squeezed into a
## box too small for it reports the box, not the space it needed, so measuring
## what it got would agree with any window at all.
func _spill(page: String, control: Control, room: Vector2) -> Array[String]:
	var need := control.size.max(control.get_combined_minimum_size())
	var at := control.position
	var out: Array[String] = []
	for edge in [
		["left", -at.x], ["top", -at.y],
		["right", at.x + need.x - room.x], ["bottom", at.y + need.y - room.y],
	]:
		if float(edge[1]) > 0.0:
			out.append("%s/%s %s by %.0f" % [page, control.name, edge[0], edge[1]])
	return out


# ------------------------------------------------------------------ the vitals

## The left column is the tightest text in the game, so it is the one that
## proves the rule: a block of labels has to fit the column it was given, and
## the way to know is to ask the column rather than to count characters.
func _test_vitals_do_not_wrap() -> void:
	print("\n-- the vitals column")
	await _at(Vector2(2560, 1440))
	GameMenu.stats = _stats()
	GameMenu.show_page(1)
	for _i in 5:
		await get_tree().process_frame

	# Against the column's *budget*, not against whatever width it ended up at.
	# A container grows to fit its contents, so "does it fit inside itself" is a
	# question that cannot fail — and the failure being guarded here is the row
	# of columns quietly widening past the 1280 the page is laid out in.
	var grid: GridContainer = GameMenu._vitals
	var budget := float(GameMenu.COLUMN_LEFT) - 2.0 * UiKit.FRAME_MARGIN
	_check("the vitals fit the character column's budget",
		grid.get_combined_minimum_size().x <= budget,
		"needs %.0f of %.0f" % [grid.get_combined_minimum_size().x, budget])

	# Labels do not wrap by default — they overflow — so "it fits" has to be
	# measured against each value's own width, not against the block's.
	var tight := ""
	for row in GameMenu._vital_values:
		var value: Label = GameMenu._vital_values[row]
		if value.get_combined_minimum_size().x > value.size.x:
			tight = String(row)
	_check("and no value is wider than its cell", tight.is_empty(), tight)

	# The values are a column, not a ragged edge. This is what the old
	# space-padded version was trying to do and could only approximate.
	var right := -1.0
	var ragged := false
	for row in GameMenu._vital_values:
		var value: Label = GameMenu._vital_values[row]
		var edge: float = value.position.x + value.size.x
		if right >= 0.0 and not is_equal_approx(edge, right):
			ragged = true
		right = edge
	_check("and they all end on the same pixel", not ragged, "%.0f" % right)

	GameMenu.close()
	await get_tree().process_frame


# ------------------------------------------------------------------ plumbing

func _stats() -> Dictionary:
	# Deliberately the long end of every field: the widest damage string the
	# combo can produce, a four-digit reach, a speed with units on it. A column
	# that fits the *typical* numbers is a column that breaks on a good sword.
	return {
		"health": 6, "max_health": 6, "max_stamina": 4.0, "capacity": 20,
		"move_speed": 240.0, "damage": "12 / 12 / 24", "reach": "144 px",
		"dodge_distance": 160.0, "regen_time": 6.0, "regen_delay": 0.7,
		"granted_by": [],
	}


func _root_of(layer: CanvasLayer) -> Control:
	for child in layer.get_children():
		if child is Control:
			return child
	return null


func _tabs_of(root: Control) -> TabContainer:
	for child in root.get_children():
		if child is TabContainer:
			return child
	return null
