extends Node
## Every `ShopData` in the game, by id, and the one place a trade happens.
##
## The registry half is the same pattern as `Items` and `Skills`, for the same
## reason: a dialogue file names a shop as a string, and a string has to resolve
## to a resource without the dialogue system knowing what a shop is.
##
## The transaction half is here rather than in the shop window because **a trade
## is a rule, not a screen**. Two things have to move atomically — the money and
## the goods — and the failure mode when they do not is a player who paid for a
## loaf that never arrived because their pack was full. Putting `buy` and `sell`
## behind this means the window can only ever ask, and every refusal is decided
## in one place that the tests can drive without opening any UI at all.

const DEFS_DIR := "res://resources/shops/defs"

var _by_id: Dictionary = {}


func _ready() -> void:
	_scan()


func all() -> Array:
	return _by_id.values()


func get_shop(id: StringName) -> ShopData:
	return _by_id.get(id)


func has(id: StringName) -> bool:
	return _by_id.has(id)


# --------------------------------------------------------------- the trade

## Why a trade could not happen, or "" if it could. A string rather than a bool
## because every caller wants to *say* what went wrong — "No room." is a useful
## refusal and a greyed-out button is not.
func why_not_buy(shop: ShopData, item: ItemData, pack: ItemsComponent) -> String:
	if shop == null or item == null:
		return "Nothing to buy."
	if not item.is_tradeable():
		return "She won't sell that."
	if not Purse.can_afford(shop.price_of(item)):
		return "Not enough gold."
	if pack != null and _room_for(pack, item) <= 0:
		return "No room in your pack."
	return ""


## Buy one. Returns "" on success, or the reason it did not happen — and on a
## refusal nothing has moved: the money comes out only once the item is in.
func buy(shop: ShopData, item: ItemData, pack: ItemsComponent) -> String:
	var refusal := why_not_buy(shop, item, pack)
	if refusal != "":
		return refusal
	var price := shop.price_of(item)
	# Goods first. If the pack lies about having room, the player keeps their
	# money — the other order hands them an empty receipt.
	if pack != null and pack.add(item, 1) <= 0:
		return "No room in your pack."
	if not Purse.spend(price):
		# Unreachable given the check above, but if it ever is reached the item
		# goes back rather than being a gift.
		if pack != null:
			_take_one(pack, item)
		return "Not enough gold."
	Sfx.play(&"ui_select", -4.0)
	Events.traded.emit(item.id, 1, -price)
	return ""


func why_not_sell(shop: ShopData, item: ItemData) -> String:
	if shop == null or item == null:
		return "Nothing to sell."
	if item.kind == ItemData.Kind.KEY:
		return "She won't take that off you."
	if not item.is_tradeable():
		return "She has no use for it."
	return ""


## Sell one from `slot`. The slot rather than the item, because a pack can hold
## the same item in two places and the player pointed at one of them.
func sell(shop: ShopData, pack: ItemsComponent, slot: int) -> String:
	if pack == null:
		return "Nothing to sell."
	var item := pack.item_at(slot)
	var refusal := why_not_sell(shop, item)
	if refusal != "":
		return refusal
	if pack.remove(slot, 1) <= 0:
		return "Nothing to sell."
	var paid := shop.offer_for(item)
	@warning_ignore("return_value_discarded")
	Purse.add(paid)
	Sfx.play(&"ui_select", -6.0)
	Events.traded.emit(item.id, -1, paid)
	return ""


## Sell haul material out of the satchel. `amount` is clamped to what is held,
## so "sell all" is `sell_material(shop, sack, id, 999)` rather than a second
## method that can disagree with this one.
##
## Returns "" on success. Nothing partial: the count is decided, then removed,
## then paid for, and a refusal has moved nothing.
func sell_material(shop: ShopData, sack: InventoryComponent, id: StringName,
		amount: int = 1) -> String:
	if shop == null or sack == null:
		return "Nothing to sell."
	if not shop.buys_materials:
		return "She doesn't deal in that."
	if not Materials.known(id):
		return "She has no use for it."
	var selling := mini(amount, sack.count_of(id))
	if selling <= 0:
		return "You have none."
	var paid := shop.offer_for_material(id) * selling
	if sack.remove(id, selling) <= 0:
		return "You have none."
	@warning_ignore("return_value_discarded")
	Purse.add(paid)
	Sfx.play(&"ui_select", -6.0)
	Events.traded.emit(id, -selling, paid)
	return ""


## Slots' worth of space for this specific item, counting part-filled stacks.
static func _room_for(pack: ItemsComponent, item: ItemData) -> int:
	var room := 0
	for slot in pack.items.size():
		var held := pack.item_at(slot)
		if held == null:
			room += item.stack_size
		elif held.id == item.id:
			room += maxi(item.stack_size - pack.count_at(slot), 0)
	return room


static func _take_one(pack: ItemsComponent, item: ItemData) -> void:
	for slot in pack.items.size():
		var held := pack.item_at(slot)
		if held != null and held.id == item.id:
			@warning_ignore("return_value_discarded")
			pack.remove(slot, 1)
			return


func _scan() -> void:
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		push_warning("Shops: no directory at %s." % DEFS_DIR)
		return
	for file in dir.get_files():
		# Exported builds rename `.tres` to `.res`; both have to be caught or
		# every shop vanishes in the shipped game and only in the shipped game.
		var name := file.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var shop := load("%s/%s" % [DEFS_DIR, name]) as ShopData
		if shop == null or not shop.is_valid():
			push_warning("Shops: %s is not a usable ShopData." % name)
			continue
		if _by_id.has(shop.id):
			push_error("Shops: duplicate id '%s'." % shop.id)
			continue
		_by_id[shop.id] = shop
