extends Node
## Money, and the trade it buys.
##
##     godot --headless --path . tests/shop_test.tscn
##
## Separate from `m1_smoke_test` because it loads Ambry and walks into an
## interior, and separate from `dialogue_test` because a trade is arithmetic and
## arithmetic deserves to be checked without a conversation in the way.
##
## The failure modes worth naming, because a shop has a specific and nasty set
## of them and every one of these is a real bug in some shipped game:
##
## - **Paying for something you did not receive.** A full pack takes the money
##   and drops the loaf. `Shops.buy` moves the goods first for this reason.
## - **Receiving something you did not pay for.** The mirror, and the one that
##   ends up on a speedrun route.
## - **Selling the key.** Any item the player cannot re-acquire is a soft lock
##   with a coin attached, so `ItemData.is_tradeable()` refuses keys outright
##   rather than asking "are you sure".
## - **The infinite loop.** Buy at a price, sell at a higher one, repeat until
##   the number stops meaning anything. Guaranteed here by asserting the offer
##   is never above the price, for every item in every shop.
##
## What this deliberately does **not** check is what she is allowed to stock.
## That is a design call, it will change, and a test that fails the build the
## day the shop sells a sword is a test that gets deleted in annoyance rather
## than consulted.

const AMBRY := "res://levels/ambry/ambry_level.tscn"
const STORE := "res://levels/ambry/interiors/sundries_level.tscn"

var _failures: int = 0
var _checks: int = 0
var _actions: Array = []


func _ready() -> void:
	Engine.max_fps = 250
	_boot.call_deferred()


func _boot() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	await get_tree().process_frame
	await _run()


func _run() -> void:
	print("\n=== Blightfall shop test ===\n")

	_check_prices()
	_check_shops()
	_check_purse()
	await _check_trading()
	await _check_materials()
	await _check_the_cart()
	await _check_the_room()
	_finish()


## The cart: assembling a whole trade, then settling it in one go.
##
## The failure modes here are worse than the one-at-a-time version's, because a
## cart can be half-applied in more ways:
##
## - **Selling the same stack twice.** The "yours" column has to show what is
##   left *after* the cart, or four timber can be added to it eight times.
## - **A trade that only balances as a whole.** Selling the haul must pay for
##   the stew in the same breath, so affordability is net and not per-line.
## - **Settling against a world that moved.** The window can be open while a
##   quest turn-in eats the materials the cart promised.
func _check_the_cart() -> void:
	print("\nThe cart")
	var level := get_tree().current_scene as Level
	if level == null:
		return
	var shop := Shops.get_shop(&"sundries")
	var pack: ItemsComponent = level.player.items
	var sack: InventoryComponent = level.player.inventory
	for slot in pack.items.size():
		if pack.item_at(slot) != null:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, pack.count_at(slot))
	sack.clear()

	var cart := ShopCart.new()
	_check("a new cart is empty", cart.is_empty())
	_check("and settling it is refused",
		Shops.settle(shop, cart, pack, sack) != "")

	# Selling the same stack twice is the bug the "left after cart" rule exists
	# to stop. The UI shows this number, so the number is what gets asserted.
	@warning_ignore("return_value_discarded")
	sack.add(&"timber", 6)
	_check("all six are available at first", cart.left_of(&"timber", 6) == 6)
	cart.add_sell_material(&"timber", 4)
	_check("four in the cart leaves two", cart.left_of(&"timber", 6) == 2,
		"%d" % cart.left_of(&"timber", 6))
	cart.add_sell_material(&"timber", 2)
	_check("and six leaves none", cart.left_of(&"timber", 6) == 0)
	cart.add_sell_material(&"timber", -6)
	_check("taking them back restores it", cart.left_of(&"timber", 6) == 6)
	_check("and an empty line disappears", not cart.sell_materials.has(&"timber"))

	# The trade that only works as a whole. Six timber at 3 is 18; a stew is 35.
	# Neither buying nor selling alone gets there from zero gold.
	Purse.set_amount(20)
	var stew := Items.get_item(&"hearty_stew")
	cart.add_buy(&"hearty_stew", 1)
	_check("the stew alone is unaffordable",
		Shops.why_not_settle(shop, cart, pack, sack) == "Not enough gold.",
		Shops.why_not_settle(shop, cart, pack, sack))
	cart.add_sell_material(&"timber", 6)
	_check("but selling the timber pays for it",
		Shops.why_not_settle(shop, cart, pack, sack) == "",
		Shops.why_not_settle(shop, cart, pack, sack))

	var expected := Purse.amount() - cart.net(shop)
	_check("settling succeeds", Shops.settle(shop, cart, pack, sack) == "")
	_check("the timber is gone", sack.count_of(&"timber") == 0,
		"%d" % sack.count_of(&"timber"))
	_check("the stew arrived", _held(pack, &"hearty_stew") == 1)
	_check("and the money is right", Purse.amount() == expected,
		"%d, expected %d" % [Purse.amount(), expected])
	_check("the cart is emptied by settling", cart.is_empty())

	# Settling against a world that moved: the cart promises materials that are
	# gone by the time Confirm is pressed.
	@warning_ignore("return_value_discarded")
	sack.add(&"stone", 3)
	var stale := ShopCart.new()
	stale.add_sell_material(&"stone", 3)
	@warning_ignore("return_value_discarded")
	sack.remove(&"stone", 2)
	_check("a cart promising what you no longer have is refused",
		Shops.settle(shop, stale, pack, sack) != "")
	_check("and nothing was paid for it", sack.count_of(&"stone") == 1,
		"%d" % sack.count_of(&"stone"))

	# A full pack refuses buys, before any money moves.
	#
	# The pack is emptied first on purpose. Left as it was, it still held one
	# hearty stew — and a stew stacks to three, so there was room for the one
	# being bought and the sale went through. That was the test being wrong
	# rather than the code, and it is worth the two lines to make "full"
	# actually mean full.
	for slot in pack.items.size():
		if pack.item_at(slot) != null:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, pack.count_at(slot))
	var filler := Items.get_item(&"worn_sword")
	for slot in pack.items.size():
		@warning_ignore("return_value_discarded")
		pack.add(filler, 1)

	var full := ShopCart.new()
	full.add_buy(&"hearty_stew", 1)
	Purse.set_amount(500)
	var gold_before := Purse.amount()
	# Captured, not called twice: `settle` has side effects, and evaluating it
	# once for the assertion and again for the failure detail would settle it.
	var stopped := Shops.settle(shop, full, pack, sack)
	_check("a full pack refuses the cart", stopped == "No room in your pack.", stopped)
	_check("and the gold stays put", Purse.amount() == gold_before)

	# ...but selling something out of that same full pack makes room for it,
	# which is the whole reason sells are applied before buys.
	full.add_sell_item(&"worn_sword", 1)
	_check("selling from a full pack makes room in the same trade",
		Shops.why_not_settle(shop, full, pack, sack) == "",
		Shops.why_not_settle(shop, full, pack, sack))
	_check("and it settles", Shops.settle(shop, full, pack, sack) == "")
	_check("the stew is in the pack", _held(pack, &"hearty_stew") >= 1)


## Selling the haul. **This is the only source of income in the game**, so it is
## the half of the shop that decides whether any of the rest of it is reachable:
## the world drops materials, materials go in the satchel, and nothing else the
## player can acquire is worth anything.
func _check_materials() -> void:
	print("\nThe haul")
	var shop := Shops.get_shop(&"sundries")

	var unpriced: Array[String] = []
	for id in Materials.ORDER:
		if Materials.value_of(id) <= 0:
			unpriced.append(String(id))
	_check("every material is worth something", unpriced.is_empty(), ", ".join(unpriced))
	_check("she deals in them", shop.buys_materials)
	_check("and pays for one", shop.offer_for_material(&"timber") > 0,
		"%d" % shop.offer_for_material(&"timber"))
	_check("but not for something she has never seen",
		shop.offer_for_material(&"moonstone") == 0)

	# A haul is worth much more than a meal, or there is no reason to walk
	# anywhere. Set against the cheapest thing on her shelf.
	var loaf := Items.get_item(&"bread")
	_check("a haul beats pocket change",
		shop.offer_for_material(&"ironwork") > shop.price_of(loaf),
		"%d vs %d" % [shop.offer_for_material(&"ironwork"), shop.price_of(loaf)])

	var level := get_tree().current_scene as Level
	if level == null:
		return
	var sack: InventoryComponent = level.player.inventory
	sack.clear()
	@warning_ignore("return_value_discarded")
	sack.add(&"timber", 5)
	Purse.set_amount(0)

	var each := shop.offer_for_material(&"timber")
	_check("selling one succeeds", Shops.sell_material(shop, sack, &"timber", 1) == "")
	_check("it leaves the satchel", sack.count_of(&"timber") == 4,
		"%d" % sack.count_of(&"timber"))
	_check("and is paid for", Purse.amount() == each, "%d" % Purse.amount())

	# Shift-click sells the stack, and asks for more than is held on purpose —
	# "sell all" is this call with a big number, so it has to clamp rather than
	# pay out for timber that was never there.
	_check("selling the stack succeeds",
		Shops.sell_material(shop, sack, &"timber", 999) == "")
	_check("the satchel empties", sack.count_of(&"timber") == 0,
		"%d" % sack.count_of(&"timber"))
	_check("and pays for exactly what was held", Purse.amount() == each * 5,
		"%d, expected %d" % [Purse.amount(), each * 5])

	var before := Purse.amount()
	_check("selling what you do not have is refused",
		Shops.sell_material(shop, sack, &"timber", 1) != "")
	_check("and pays nothing", Purse.amount() == before)

	# The satchel is the thing the whole expedition loop fills, so the menu and
	# the shop have to agree about what is in it. They read the same cache.
	await _ticks(2)
	_check("the HUD cache tracks the satchel", int(Hud.materials.get(&"timber", 0)) == 0,
		str(Hud.materials))
	@warning_ignore("return_value_discarded")
	sack.add(&"stone", 3)
	await _ticks(2)
	_check("and updates when it changes", int(Hud.materials.get(&"stone", 0)) == 3,
		str(Hud.materials))


# ------------------------------------------------------------------- prices

func _check_prices() -> void:
	print("Prices (tools/price_items.py owns these; nothing is hand-typed)")

	var unpriced: Array[String] = []
	var keys_worth_money: Array[String] = []
	for id in Items.all():
		var item: ItemData = Items.get_item(id)
		if item.kind == ItemData.Kind.KEY:
			if item.value != 0:
				keys_worth_money.append(String(id))
			continue
		if item.value <= 0:
			unpriced.append(String(id))
	_check("every non-key item has a price", unpriced.is_empty(), ", ".join(unpriced))

	# A key with a price is a key that can be sold, and a sold key is a door
	# that never opens again.
	_check("no key is worth anything", keys_worth_money.is_empty(),
		", ".join(keys_worth_money))

	var key := Items.get_item(&"rusted_key")
	_check("and so a key is not tradeable", key != null and not key.is_tradeable())

	# The one relationship that has to hold across the whole item table, or the
	# economy has a hole in it that fishing eventually finds.
	var sword := Items.get_item(&"worn_sword")
	var bass := Items.get_item(&"bass")
	_check("a weapon is worth more than a fish",
		sword != null and bass != null and sword.value > bass.value,
		"%d vs %d" % [sword.value if sword else -1, bass.value if bass else -1])


# -------------------------------------------------------------------- shops

func _check_shops() -> void:
	print("\nShops")
	var shops := Shops.all()
	_check("there is a shop to trade at", shops.size() >= 1, "%d" % shops.size())

	var sundries := Shops.get_shop(&"sundries")
	_check("the general store exists", sundries != null)
	if sundries == null:
		return

	_check("it has a name over the door", not sundries.display_name.is_empty(),
		sundries.display_name)
	_check("and something on the shelf", sundries.stock.size() >= 4,
		"%d lines" % sundries.stock.size())

	# The money printer. Checked for every item in every shop rather than for
	# the rates, because the rates are floats and the prices are integers, and
	# it is the rounding that would let one specific cheap item through.
	var inverted: Array[String] = []
	for shop in Shops.all():
		var it: ShopData = shop
		for id in Items.all():
			var item: ItemData = Items.get_item(id)
			if not item.is_tradeable():
				continue
			if it.offer_for(item) > it.price_of(item):
				inverted.append("%s pays %d for %s and sells it at %d"
					% [it.id, it.offer_for(item), id, it.price_of(item)])
	_check("nothing can be bought for less than it sells for", inverted.is_empty(),
		", ".join(inverted))

	# Zero-value things must not be silently free-and-worthless in the UI: a
	# row that reads "0" is a row a player will click.
	var key := Items.get_item(&"rusted_key")
	_check("an untradeable item prices at nothing", sundries.price_of(key) == 0)
	_check("and is refused by name",
		Shops.why_not_sell(sundries, key) != "",
		Shops.why_not_sell(sundries, key))


# ------------------------------------------------------------------- purse

func _check_purse() -> void:
	print("\nThe purse")
	Purse.set_amount(100)
	_check("it holds what it was given", Purse.amount() == 100)
	_check("it can afford what it has", Purse.can_afford(100))
	_check("and not a coin more", not Purse.can_afford(101))

	_check("spending succeeds", Purse.spend(40))
	_check("and takes exactly that", Purse.amount() == 60, "%d" % Purse.amount())
	_check("overspending is refused", not Purse.spend(61))
	_check("and changes nothing", Purse.amount() == 60, "%d" % Purse.amount())

	@warning_ignore("return_value_discarded")
	Purse.add(-1000)
	_check("it never goes negative", Purse.amount() == 0, "%d" % Purse.amount())

	# Saved, or a shop is a place where progress goes to be forgotten.
	Purse.set_amount(77)
	var saved := Purse.save_data()
	Purse.set_amount(0)
	Purse.load_data(saved)
	_check("gold survives a save and load", Purse.amount() == 77, "%d" % Purse.amount())
	_check("the purse is registered as saveable", Purse.is_in_group(SaveGame.GROUP))


# ------------------------------------------------------------------ trading

func _check_trading() -> void:
	print("\nTrading")
	get_tree().change_scene_to_file(AMBRY)
	await get_tree().tree_changed
	await _ticks(6)

	var level := get_tree().current_scene as Level
	_check("Ambry loaded", level != null)
	if level == null:
		return
	var pack: ItemsComponent = level.player.items
	var shop := Shops.get_shop(&"sundries")

	# A clean slate, or a starting kit makes every count below relative to
	# something the test did not choose.
	for slot in pack.items.size():
		if pack.item_at(slot) != null:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, pack.count_at(slot))

	var bread: ItemData = shop.stock[0]
	var price := shop.price_of(bread)
	Purse.set_amount(price * 2)

	var held_before := _held(pack, bread.id)
	_check("buying is allowed when it is affordable",
		Shops.why_not_buy(shop, bread, pack) == "")
	_check("and it succeeds", Shops.buy(shop, bread, pack) == "")
	_check("the item arrives", _held(pack, bread.id) == held_before + 1,
		"%d -> %d" % [held_before, _held(pack, bread.id)])
	_check("and is paid for exactly", Purse.amount() == price, "%d" % Purse.amount())

	# Selling it straight back must not be a profit.
	var offer := shop.offer_for(bread)
	_check("she pays less than she charges", offer < price, "%d < %d" % [offer, price])
	var slot_of_bread := _slot_of(pack, bread.id)
	_check("selling succeeds", Shops.sell(shop, pack, slot_of_bread) == "")
	_check("the item leaves", _held(pack, bread.id) == held_before,
		"%d" % _held(pack, bread.id))
	_check("and is paid for", Purse.amount() == price + offer, "%d" % Purse.amount())

	# Broke.
	Purse.set_amount(0)
	_check("a purse with nothing in it cannot buy",
		Shops.why_not_buy(shop, bread, pack) == "Not enough gold.",
		Shops.why_not_buy(shop, bread, pack))
	_check("and the attempt moves nothing", Shops.buy(shop, bread, pack) != ""
		and _held(pack, bread.id) == held_before)

	# A full pack. The nastiest case: the money must not leave.
	Purse.set_amount(price * 4)
	var filler := Items.get_item(&"worn_sword")
	for slot in pack.items.size():
		if pack.item_at(slot) == null:
			@warning_ignore("return_value_discarded")
			pack.add(filler, 1)
	var gold_before := Purse.amount()
	var refusal := Shops.buy(shop, bread, pack)
	_check("a full pack refuses the sale", refusal != "", refusal)
	_check("and the gold stays put", Purse.amount() == gold_before,
		"%d -> %d" % [gold_before, Purse.amount()])

	# A key cannot be sold even when it is sitting in the pack.
	for slot in pack.items.size():
		if pack.item_at(slot) != null:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, pack.count_at(slot))
	var key := Items.get_item(&"rusted_key")
	@warning_ignore("return_value_discarded")
	pack.add(key, 1)
	var key_slot := _slot_of(pack, key.id)
	gold_before = Purse.amount()
	_check("selling a key is refused", Shops.sell(shop, pack, key_slot) != "")
	_check("the key is still there", _held(pack, key.id) == 1)
	_check("and nothing was paid", Purse.amount() == gold_before)


# ------------------------------------------------------------- her, in situ

func _check_the_room() -> void:
	print("\nThe shop, and the woman in it")

	# The conversation file has to parse and name a shop that exists — a
	# `"shop"` action pointing at nothing is a reply that silently does nothing.
	var talk := Dialogue.load_dialogue(&"shopkeeper")
	_check("her conversation loads", not talk.is_empty())
	var named := 0
	var missing: Array[String] = []
	for node_name in talk.get("nodes", {}):
		for choice in (talk["nodes"][node_name] as Dictionary).get("choices", []):
			# Only the shop actions. A reply may carry `quest` or `turn_in`
			# instead, and those name a quest rather than a shop —
			# `tests/quest_test.gd` is what checks those resolve.
			if String((choice as Dictionary).get("action", "")) != "shop":
				continue
			named += 1
			var id := StringName(String((choice as Dictionary).get("shop", "")))
			if not Shops.has(id):
				missing.append("%s -> %s" % [node_name, id])
	_check("every trade reply names a real shop", missing.is_empty(), ", ".join(missing))
	_check("and there is more than one way to reach the shelf", named >= 3, "%d" % named)

	# The branch that only exists after she has told you about it.
	Dialogue.forget_conversations()
	_check("the errand is not offered before she raises it",
		not Dialogue.has_seen(&"shopkeeper", "errand_accepted"))

	get_tree().change_scene_to_file(STORE)
	await get_tree().tree_changed
	await _ticks(6)

	var store := get_tree().current_scene as Level
	_check("her shop is a room you can stand in", store != null)
	if store == null:
		return
	var cast := store.npcs()
	var ids: Array = cast.map(func(entry: Dictionary) -> StringName: return entry["id"])
	_check("and she is behind the counter", ids.has(&"shopkeeper"), str(ids))

	# The window itself. Driven directly rather than through a click, because
	# what is being checked is that it opens, reads the pack, and gives the
	# time back on the way out — not that a Panel forwards a mouse button.
	_check("the shop window opens", ShopMenu.open(&"sundries"))
	_check("and it says so", ShopMenu.is_open())
	_check("the world is held while it is up", get_tree().paused)
	ShopMenu.close()
	_check("closing it lets go", not ShopMenu.is_open() and not get_tree().paused)
	_check("an unknown shop opens nothing", not ShopMenu.open(&"no_such_shop"))

	await _check_the_seam()


## Talking to her and choosing to trade actually opens the shop.
##
## **This is the only part of the feature nothing else covers.** The trade rules
## are checked above without a UI, the window is checked above without a
## conversation, and both would keep passing if the wire between them were cut —
## which is exactly the shape of bug that ships, because every individual piece
## demonstrably works.
func _check_the_seam() -> void:
	Dialogue.forget_conversations()
	_check("her conversation starts", Dialogue.start(&"shopkeeper"))

	# Click through the opening lines the way a player would, until the replies
	# are up. Bounded, so a rewrite that adds a line does not hang the suite and
	# a rewrite that removes the replies fails it.
	var taps := 0
	while not Dialogue.showing_replies() and taps < 12:
		Dialogue._on_box_input(_click())
		await get_tree().process_frame
		taps += 1
	_check("and offers replies", Dialogue.showing_replies(), "%d taps" % taps)

	var trade := -1
	for i in Dialogue._choices.size():
		if String((Dialogue._choices[i] as Dictionary).get("action", "")) == "shop":
			trade = i
			break
	_check("one of them is a trade", trade >= 0)
	if trade < 0:
		return

	Dialogue._choice = trade
	Dialogue._pick()
	# The window opens deferred, so the box can finish closing under it.
	await get_tree().process_frame
	await get_tree().process_frame
	_check("choosing it opens the shop", ShopMenu.is_open())
	_check("and the conversation got out of the way", not Dialogue.is_open())
	ShopMenu.close()


static func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


# ------------------------------------------------------------------ helpers

static func _held(pack: ItemsComponent, id: StringName) -> int:
	var total := 0
	for slot in pack.items.size():
		var item := pack.item_at(slot)
		if item != null and item.id == id:
			total += pack.count_at(slot)
	return total


static func _slot_of(pack: ItemsComponent, id: StringName) -> int:
	for slot in pack.items.size():
		var item := pack.item_at(slot)
		if item != null and item.id == id:
			return slot
	return -1


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
