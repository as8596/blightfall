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


func interact(actor: Node) -> void:
	super(actor)
	var taken: Array[String] = []
	var left := {}
	for id in contents:
		var wanted := int(contents[id])
		var got := _give(actor, id, wanted)
		if got > 0:
			taken.append("%s x%d" % [_name_of(id), got])
		if got < wanted:
			left[id] = wanted - got
	contents = left

	if gold > 0:
		@warning_ignore("return_value_discarded")
		Purse.add(gold)
		taken.append("%d gold" % gold)
		gold = 0

	if taken.is_empty():
		# Everything bounced — a full pack. Say so and leave the pile standing,
		# rather than quietly deleting somebody's hide.
		Events.quest_refused.emit(&"", "No room for that.")
		return
	Sfx.play(&"ui_select", -8.0)
	if contents.is_empty() and gold <= 0:
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


static func _name_of(id: StringName) -> String:
	if Materials.known(id):
		return Materials.name_of(id)
	var item := Items.get_item(id)
	return item.display_name if item != null else String(id)
