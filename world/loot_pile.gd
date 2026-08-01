class_name LootPile
extends Interactable
## What a dead thing leaves behind, and the keypress that takes it.
##
## **Searched, not walked over.** `Pickup` is walked over deliberately —
## materials are the routine currency of a run and forty keypresses is a tax,
## not a decision. A kill is different: it is a moment, and something worth
## stopping for is worth a button. It also means loot cannot be hoovered up by
## accident while you are still dodging the next wolf.
##
## The contents are rolled **when the pile is made**, not when it is opened, so
## a player cannot re-roll a drop by walking away and coming back — and so the
## pile can say how much is in it before anyone touches it.

## {id: count}. Ids may be items or haul materials; `_give` sorts out which bag
## each belongs in, so a loot table never has to know.
@export var contents: Dictionary = {}
@export var gold: int = 0

const ICON: Texture2D = preload("res://art/icons/items/drops/rags.png")


func _ready() -> void:
	prompt = "Search"
	super()
	if _sprite() == null:
		var body := Sprite2D.new()
		body.name = "Visual"
		body.texture = ICON
		body.centered = true
		body.modulate = Color(0.86, 0.80, 0.70)
		add_child(body)


func _sprite() -> Sprite2D:
	return get_node_or_null("Visual") as Sprite2D


## Roll a table into a pile, or return null if it came up empty.
##
## Empty is the common case and it matters that it produces *nothing* rather
## than an empty pile: a body you can search for no reward teaches the player to
## stop searching bodies.
static func roll(data: EnemyData) -> Dictionary:
	var rolled := {}
	if data != null:
		for id in data.loot:
			var entry: Array = data.loot[id]
			if entry.size() < 3 or Rng.randf() > float(entry[0]):
				continue
			var count := Rng.randi_range(int(entry[1]), int(entry[2]))
			if count > 0:
				rolled[StringName(id)] = count
	var coins := 0
	if data != null and data.gold_chance > 0.0 and Rng.randf() <= data.gold_chance:
		coins = Rng.randi_range(data.gold_min, data.gold_max)
	if rolled.is_empty() and coins <= 0:
		return {}
	return {"contents": rolled, "gold": coins}


func can_interact(actor: Node) -> bool:
	return super(actor) and not (contents.is_empty() and gold <= 0)


## Open the window over it.
##
## **It used to take everything on the keypress.** That is fine when the pile is
## two hides and wrong the moment it is not: with a full pack you found out what
## you had left behind by reading a toast that had already gone, and there was
## no way to take the fang and leave the rags. `ui/loot_menu.gd` is the window;
## this is still the only thing that moves an item, so the two cannot disagree
## about what a full pack means.
##
## The old behaviour is the fallback, for the case where no window can open —
## a headless test, or a menu already up. Searching a body has to do *something*.
func interact(actor: Node) -> void:
	super(actor)
	if LootMenu.open(self, actor):
		return
	if take_all(actor).is_empty():
		# Everything bounced. Say so and leave the pile standing, rather than
		# quietly deleting somebody's hide.
		Events.quest_refused.emit(&"", "No room for that.")
		return
	Sfx.play(&"ui_select", -8.0)
	retire()


## Move up to `amount` of one id into the actor's bags. Returns how many
## actually went, which is less than asked for when the pack is full and zero
## when it is completely full.
##
## **Does not free the pile**, even when that empties it: the window is drawing
## this node and a pile that deletes itself mid-click takes the window with it.
## `retire` is the separate step, and the window calls it on the way out.
func take(actor: Node, id: StringName, amount: int) -> int:
	var wanted := mini(amount, int(contents.get(id, 0)))
	if wanted <= 0:
		return 0
	var got := _give(actor, id, wanted)
	if got <= 0:
		return 0
	var left := int(contents[id]) - got
	if left > 0:
		contents[id] = left
	else:
		contents.erase(id)
	return got


## Coins, which never bounce — the purse has no limit and nothing to be full of.
func take_gold() -> int:
	if gold <= 0:
		return 0
	var coins := gold
	gold = 0
	@warning_ignore("return_value_discarded")
	Purse.add(coins)
	return coins


## Everything that fits, named. An empty array means nothing moved at all.
func take_all(actor: Node) -> Array[String]:
	var taken: Array[String] = []
	for id in contents.keys():
		var got := take(actor, id, int(contents[id]))
		if got > 0:
			taken.append("%s x%d" % [name_of(id), got])
	var coins := take_gold()
	if coins > 0:
		taken.append("%d gold" % coins)
	return taken


func is_empty() -> bool:
	return contents.is_empty() and gold <= 0


## How many things are still on it, counting stacks rather than items — which is
## what "did anything move" wants to know.
func count() -> int:
	return contents.size() + (1 if gold > 0 else 0)


## Clear away a pile that has nothing left. Separate from `take` so the window
## can hold a reference across a whole search.
func retire() -> void:
	if is_empty():
		queue_free()


## Put one id wherever it belongs. Materials go in the satchel, everything else
## in the pack — which is the distinction `InventoryComponent` and
## `ItemsComponent` draw, and the reason a loot table does not have to.
static func _give(actor: Node, id: StringName, amount: int) -> int:
	if Materials.known(id):
		var sack: InventoryComponent = actor.get("inventory")
		return sack.add(id, amount) if sack != null else 0
	var item := Items.get_item(id)
	var pack: ItemsComponent = actor.get("items")
	if item == null or pack == null:
		return 0
	return pack.add(item, amount)


## The two lookups the window needs, on the same "materials or items, and the
## caller does not have to know which" rule as `_give`.
static func name_of(id: StringName) -> String:
	if Materials.known(id):
		return Materials.name_of(id)
	var item := Items.get_item(id)
	return item.display_name if item != null else String(id)


static func icon_of(id: StringName) -> Texture2D:
	if Materials.known(id):
		return Materials.icon_of(id)
	var item := Items.get_item(id)
	return item.icon if item != null else null


## Contents in a fixed order, so the grid does not rearrange itself between one
## click and the next. Materials first and alphabetical within each half:
## `Dictionary` preserves insertion order, and the insertion order here is
## whatever the loot table happened to roll.
static func sorted(from: Dictionary) -> Array:
	var out: Array = from.keys()
	out.sort_custom(func(a, b) -> bool:
		var a_material := Materials.known(a)
		if a_material != Materials.known(b):
			return a_material
		return String(name_of(a)) < String(name_of(b)))
	return out
