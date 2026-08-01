extends Node
## What a dead thing leaves behind, and the window you take it out of.
##
##     godot --headless --path . tests/loot_test.tscn
##
## Its own scene because a loot pile is where two systems meet that otherwise
## never touch: the roll that decides what is on a body, and the two different
## bags a player carries. Every failure worth naming lives on that seam.
##
## - **Taking what does not fit.** A full pack has to refuse an item and leave
##   it on the ground. Silently eating it is the worst outcome here, because the
##   player watched it happen and there is nothing to undo.
## - **Taking what does fit, and leaving the rest.** The half-full case, which
##   is what the window exists for: the old keypress took everything or nothing.
## - **Paying twice.** Coins go in the purse once. `take_gold` zeroing the pile
##   before adding is the reason it cannot be clicked twice.
## - **Leaving a picked-clean pile standing.** An empty pile you can still walk
##   up to is a body that promises loot it does not have.
## - **Freeing the pile out from under the window.** `take` deliberately does
##   not, and this is the check that keeps it that way.

const PILE: PackedScene = preload("res://world/loot_pile.tscn")
const PLAYER: PackedScene = preload("res://actors/player/player.tscn")

var _failures: int = 0
var _checks: int = 0
var _player: Player


func _ready() -> void:
	Engine.max_fps = 250
	_run.call_deferred()


func _run() -> void:
	print("\n=== Blightfall loot test ===\n")
	_player = PLAYER.instantiate()
	add_child(_player)
	await _ticks(4)

	await _test_taking()
	await _test_full_pack()
	await _test_gold()
	await _test_window()

	print("\n%d checks, %d failed\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if detail != "" else ""])


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _pile(contents: Dictionary, gold: int = 0) -> LootPile:
	var pile: LootPile = PILE.instantiate()
	pile.contents = contents.duplicate()
	pile.gold = gold
	add_child(pile)
	return pile


# ------------------------------------------------------------------- taking

func _test_taking() -> void:
	print("-- one stack at a time")
	var pile := _pile({&"timber": 3, &"stone": 2})
	_check("a fresh pile is not empty", not pile.is_empty())
	_check("and counts its stacks", pile.count() == 2, "%d" % pile.count())

	var got := pile.take(_player, &"timber", 3)
	_check("taking a stack moves all of it", got == 3, "%d" % got)
	_check("and the stack leaves the pile", not pile.contents.has(&"timber"),
		str(pile.contents))
	_check("while the other stack stays put", int(pile.contents.get(&"stone", 0)) == 2,
		str(pile.contents))

	# The window is drawing this node. A pile that deleted itself the moment its
	# last stack moved would take the window with it.
	@warning_ignore("return_value_discarded")
	pile.take(_player, &"stone", 2)
	_check("emptying a pile does not free it", is_instance_valid(pile))
	_check("but it does report itself empty", pile.is_empty())
	pile.retire()
	await _ticks(2)
	_check("and retiring it does free it", not is_instance_valid(pile))

	# Asking for more than is there is not an error, it is a click on a stack of
	# two while the code offers to take five.
	var short := _pile({&"stone": 2})
	_check("taking more than is there takes what is there",
		short.take(_player, &"stone", 99) == 2)
	_check("and asking for something that is not there takes nothing",
		short.take(_player, &"timber", 1) == 0)
	short.retire()
	await _ticks(2)


# ------------------------------------------------------------------ refusals

func _test_full_pack() -> void:
	print("\n-- a full satchel")
	var sack: InventoryComponent = _player.inventory
	sack.clear()
	# One short of full, so the next stack can only partly fit — which is the
	# case the old take-everything keypress could not express at all.
	var room := 1
	@warning_ignore("return_value_discarded")
	sack.add(&"stone", sack.capacity - room)
	_check("the satchel is one short of full",
		sack.total() == sack.capacity - room, "%d/%d" % [sack.total(), sack.capacity])

	var pile := _pile({&"timber": 4})
	var got := pile.take(_player, &"timber", 4)
	_check("a nearly full satchel takes what fits", got == room, "%d" % got)
	_check("and the rest stays on the body",
		int(pile.contents.get(&"timber", 0)) == 4 - room, str(pile.contents))
	_check("which means the pile is still worth searching", not pile.is_empty())

	got = pile.take(_player, &"timber", 4)
	_check("a completely full satchel takes nothing", got == 0, "%d" % got)
	_check("and nothing is quietly destroyed",
		int(pile.contents.get(&"timber", 0)) == 4 - room, str(pile.contents))

	_check("take_all on a full satchel reports nothing moved",
		pile.take_all(_player).is_empty())
	pile.queue_free()
	sack.clear()
	await _ticks(2)


func _test_gold() -> void:
	print("\n-- coins")
	var before := Purse.amount()
	var pile := _pile({}, 42)
	_check("a pile with only coins is not empty", not pile.is_empty())
	_check("taking them returns the amount", pile.take_gold() == 42)
	_check("and the purse has them", Purse.amount() == before + 42,
		"%d -> %d" % [before, Purse.amount()])
	_check("taking again returns nothing", pile.take_gold() == 0)
	_check("and the purse is not paid twice", Purse.amount() == before + 42,
		"%d" % Purse.amount())
	_check("a pile with nothing left is empty", pile.is_empty())
	pile.retire()
	await _ticks(2)


# ------------------------------------------------------------------- window

func _test_window() -> void:
	print("\n-- the window")
	_player.inventory.clear()
	var pile := _pile({&"timber": 2, &"stone": 1}, 7)

	_check("searching opens the window rather than emptying the pile",
		LootMenu.open(pile, _player))
	await _ticks(2)
	_check("and it says it is open", LootMenu.is_open())
	_check("with the pile untouched", pile.count() == 3, "%d" % pile.count())
	_check("and the game paused", get_tree().paused)

	# Escape, the same key that backs out of every other window.
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await _ticks(3)
	_check("Escape closes it", not LootMenu.is_open())
	_check("and gives the game back", not get_tree().paused)
	_check("leaving the pile where it was", is_instance_valid(pile) and pile.count() == 3,
		"%d" % pile.count() if is_instance_valid(pile) else "freed")

	# A second search takes everything, and the window has nothing left to show.
	_check("it can be searched again", LootMenu.open(pile, _player))
	await _ticks(2)
	LootMenu._on_take_all()
	await _ticks(3)
	_check("take all empties the pile", pile.is_empty() if is_instance_valid(pile) else true)
	_check("and closes the window behind it", not LootMenu.is_open())
	await _ticks(2)
	_check("and the picked-clean pile is gone", not is_instance_valid(pile))
	_check("with the game running again", not get_tree().paused)

	# The order the grid draws in has to be stable, or a stack moves out from
	# under the pointer between one click and the next.
	var mixed := _pile({&"wolf_fang": 1, &"timber": 2, &"stone": 1})
	var first := LootPile.sorted(mixed.contents)
	var second := LootPile.sorted(mixed.contents)
	_check("the grid order is stable", first == second, str(first))
	_check("and materials come before items",
		first.size() == 3 and Materials.known(first[0]) and not Materials.known(first[2]),
		str(first))
	mixed.queue_free()
	await _ticks(2)
