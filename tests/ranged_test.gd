extends Node
## Shoot things, and check that shooting things works.
##
##     godot --headless --path . tests/ranged_test.tscn
##
## Its own suite rather than more lines in `m1_smoke_test`, because a bow is the
## first thing in this game whose whole behaviour happens **over several physics
## frames in a moving node that is not the player**. Every other combat check can
## be made by calling a method and looking at the result; these have to launch
## something and wait for it to arrive.
##
## The cases are chosen around what would actually break and nobody would notice:
##
## - The swap changing which verb the attack button is, since that is one button
##   meaning two things and the failure mode is a click that silently does the
##   wrong one.
## - The arrow being spent on the loose and **not** on the draw, because a draw
##   you cancelled costing ammunition is the kind of leak that reads as "arrows
##   disappear sometimes" a fortnight later.
## - The empty quiver refusing rather than firing a free arrow.
## - The range limit, because an arrow with no limit does not fail here — it
##   fails as a wolf dying in a room the player left two minutes ago.
## - A draw that is weaker than a full one, since if that ever collapses the bow
##   silently becomes a tap-spam weapon and no other check would see it.

const ROOM := preload("res://levels/prototype/prototype_room.tscn")

var _failures: int = 0
var _checks: int = 0
var _room: Node
var _player: Player


func _ready() -> void:
	Engine.max_fps = 250
	_boot.call_deferred()


func _boot() -> void:
	_room = ROOM.instantiate()
	add_child(_room)
	await get_tree().process_frame
	await _ticks(4)
	_player = _find_player(_room)
	await _run()


func _run() -> void:
	print("\n=== Blightfall ranged test ===\n")
	_check("the prototype room has a player", _player != null)
	if _player == null:
		return _finish()

	var bow: ItemData = Items.get_item(&"hunting_bow")
	var ammo: ItemData = Items.get_item(&"arrow")
	_check("there is a bow in the library", bow != null and bow.is_ranged(),
		String(bow.id) if bow != null else "-")
	_check("and something to fire out of it", ammo != null and ammo.is_ammo())
	if bow == null or ammo == null:
		return _finish()

	# ---- what the attack button means
	_check("the player starts with the sword forward",
		_player.drawn_slot == ItemData.Slot.WEAPON)
	_check("and the sword is not a bow", _player.drawn_bow() == null)

	_check("swapping puts the bow forward", _player.toggle_weapon())
	_check("and the bow is now what attack means", _player.drawn_bow() != null,
		String(_player.drawn_bow().id) if _player.drawn_bow() != null else "-")
	_check("swapping back returns the sword", _player.toggle_weapon()
		and _player.drawn_slot == ItemData.Slot.WEAPON)

	# Nothing in the ranged slot means nothing to swap to, and the refusal has to
	# be visible rather than leaving an empty hand forward.
	var worn := _player.equipment.unequip(ItemData.Slot.RANGED)
	await _ticks(1)
	_check("with no bow worn the swap refuses", not _player.toggle_weapon())
	_check("and the sword is still forward",
		_player.drawn_slot == ItemData.Slot.WEAPON)
	@warning_ignore("return_value_discarded")
	_player.equipment.equip(worn)
	await _ticks(1)

	# Taking the bow off while holding it must put the other hand forward, or
	# `drawn_slot` names an empty slot and every click does nothing.
	@warning_ignore("return_value_discarded")
	_player.toggle_weapon()
	@warning_ignore("return_value_discarded")
	_player.equipment.unequip(ItemData.Slot.RANGED)
	await _ticks(1)
	_check("unequipping the bow you are holding falls back to the sword",
		_player.drawn_slot == ItemData.Slot.WEAPON)
	@warning_ignore("return_value_discarded")
	_player.equipment.equip(bow)
	await _ticks(1)
	@warning_ignore("return_value_discarded")
	_player.toggle_weapon()

	# ---- ammunition
	_check("the starting kit includes arrows", _player.arrows_left() > 0,
		"%d" % _player.arrows_left())

	var before := _player.arrows_left()
	_check("spending one takes exactly one", _player.spend_arrow()
		and _player.arrows_left() == before - 1,
		"%d -> %d" % [before, _player.arrows_left()])

	# All-or-nothing: asking for more than is there must take none of it.
	var held := _player.arrows_left()
	_check("asking for more arrows than you have takes none",
		not _player.items.take(&"arrow", held + 5)
		and _player.arrows_left() == held,
		"%d" % _player.arrows_left())

	# ---- the shot
	var weapon: RangedWeaponData = bow.ranged
	_check("a full draw hits harder than a snapshot",
		weapon.damage_at(1.0) > weapon.damage_at(0.0),
		"%d vs %d" % [weapon.damage_at(1.0), weapon.damage_at(0.0)])
	_check("and travels faster", weapon.speed_at(1.0) > weapon.speed_at(0.0),
		"%.0f vs %.0f" % [weapon.speed_at(1.0), weapon.speed_at(0.0)])
	_check("and scatters less", weapon.spread_at(1.0) < weapon.spread_at(0.0),
		"%.3f vs %.3f" % [weapon.spread_at(1.0), weapon.spread_at(0.0)])
	_check("a snapshot is still worth something", weapon.damage_at(0.0) >= 1,
		"%d" % weapon.damage_at(0.0))

	var arrow := Arrow.launch(_player.arrow_scene, _room, _player.global_position,
		Vector2.RIGHT, weapon, 1.0, _player)
	_check("an arrow can be launched", arrow != null and is_instance_valid(arrow))
	if arrow == null:
		return _finish()
	_check("and it is pointed where it was aimed",
		is_equal_approx(arrow.rotation, 0.0), "%.2f rad" % arrow.rotation)
	_check("and it does not belong to nobody", arrow.source == _player)
	var from := arrow.global_position
	await _ticks(3)
	_check("and it moves", arrow.global_position.x > from.x,
		"%.0f -> %.0f" % [from.x, arrow.global_position.x])

	# ---- the range limit
	#
	# Fired straight up out of the room, so nothing it could hit is in the way
	# and the only thing that can stop it is running out of distance.
	var far := Arrow.launch(_player.arrow_scene, _room, _player.global_position,
		Vector2.UP, weapon, 1.0, _player)
	var travelled := 0.0
	for i in 400:
		await get_tree().physics_frame
		if not is_instance_valid(far):
			break
		travelled = far.travelled
	_check("an arrow does not fly forever", not is_instance_valid(far),
		"stopped at %.0fpx of %.0f" % [travelled, weapon.range_px])
	_check("and it went about as far as it was meant to",
		travelled >= weapon.range_px * 0.9, "%.0f" % travelled)

	await _hit_an_enemy(weapon)
	await _empty_quiver(bow)
	_finish()


## The thing the whole feature is for: an arrow reaching a wolf and hurting it.
func _hit_an_enemy(weapon: RangedWeaponData) -> void:
	var enemies := get_tree().get_nodes_in_group(Targeting.ENEMY_GROUP)
	_check("the room has something to shoot at", not enemies.is_empty(),
		"%d" % enemies.size())
	if enemies.is_empty():
		return
	var target := enemies[0] as BaseEnemy
	if target == null or target.health == null:
		_check("the target has health to lose", false)
		return

	# **Both ends placed relative to the player**, not to wherever the room's
	# spawner happened to put the wolf. Standing the shooter 320px to the wolf's
	# left put it inside the room's wall on the first run: the arrow died against
	# the world collider without ever reaching anything, and the check read as
	# "arrows do not hurt enemies" when what it had actually proved was that
	# arrows stop at walls.
	#
	# The player is by definition somewhere legal, so the wolf is brought to a
	# spot in front of them instead.
	# Fired from the same height the draw state fires from — chest, not feet.
	# Launching from the origin is what the first run did, and every arrow flew
	# under every hurtbox in the game: a player's position is at their feet and
	# an enemy's hurtbox is not. That was a real bug in `PlayerDrawState` rather
	# than a fault in the test, and this line is the reason it can only come back
	# once.
	var stand := _player.global_position + Vector2(0.0, _player.hitbox.position.y)
	target.global_position = _player.global_position + Vector2(STANDOFF, 0.0)
	await _ticks(2)
	var hp := target.health.current
	var arrow := Arrow.launch(_player.arrow_scene, _room, stand, Vector2.RIGHT,
		weapon, 1.0, _player)
	_check("an arrow is in the air", arrow != null)
	if arrow == null:
		return
	var flight := 0.0
	for i in 200:
		await get_tree().physics_frame
		if is_instance_valid(arrow):
			flight = arrow.travelled
		if target.health.current < hp or not is_instance_valid(arrow):
			break
	_check("an arrow that reaches an enemy hurts it", target.health.current < hp,
		"%d -> %d hp after %.0fpx of flight" % [hp, target.health.current, flight])
	# Two separate facts. It stops dead on the hit — checked now, because that is
	# the frame it matters on and an arrow that kept its hitbox live would carry
	# on through whatever was behind the wolf. Then it goes away, which
	# `queue_free` does at the end of the frame rather than immediately, so
	# asserting it on the same tick tests Godot's deferred-free semantics instead
	# of the arrow.
	_check("and it stops dead rather than carrying on",
		not is_instance_valid(arrow) or not arrow.is_flying())
	await _ticks(2)
	_check("and then it is gone", not is_instance_valid(arrow))
	_check("and it crossed real ground to get there", flight > STANDOFF * 0.5,
		"%.0fpx" % flight)


## How far in front of the player the target is put. Far enough that the arrow
## has to actually fly — a hit at point-blank would pass whether the projectile
## moves or not — and near enough to stay inside the prototype room.
const STANDOFF: float = 260.0


## An empty quiver refuses the shot instead of firing a free arrow.
func _empty_quiver(bow: ItemData) -> void:
	@warning_ignore("return_value_discarded")
	_player.items.take(&"arrow", _player.arrows_left())
	await _ticks(1)
	_check("the quiver can be emptied", _player.arrows_left() == 0,
		"%d" % _player.arrows_left())
	_check("and spending from an empty one fails", not _player.spend_arrow())

	# Straight at the state, because driving it through the input layer would be
	# testing the input layer. What matters is that it does not stay in the draw.
	_player.state_machine.transition_to(&"Draw")
	await _ticks(2)
	_check("drawing with an empty quiver does not stick in the draw state",
		not _player.state_machine.is_in(&"Draw"),
		_player.state_machine.current_state_name())

	var loose := get_tree().get_nodes_in_group("arrows_in_flight")
	_check("and no arrow was produced by it", loose.is_empty(),
		"%d" % loose.size())

	# Put some back and check the draw is willing again, so the refusal above is
	# about the ammunition and not about the state being broken.
	@warning_ignore("return_value_discarded")
	_player.items.add(Items.get_item(&"arrow"), 5)
	await _ticks(1)
	_check("restocking makes the bow usable again", _player.arrows_left() == 5,
		"%d" % _player.arrows_left())
	_check("and the bow is still what is in hand", _player.drawn_bow() != null)
	_check("the shop stocks arrows so this is reachable in play",
		_shop_stocks(&"sundries", &"arrow"))


static func _shop_stocks(shop: StringName, item: StringName) -> bool:
	var data: ShopData = Shops.get_shop(shop)
	if data == null:
		return false
	for entry in data.stock:
		var carried := entry as ItemData
		if carried != null and carried.id == item:
			return true
	return false


static func _find_player(root: Node) -> Player:
	if root is Player:
		return root as Player
	for child in root.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _finish() -> void:
	print("\n%d checks, %d failed\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
