extends Node
## Every `ItemData` in the game, by id.
##
## Exists so a save can store `"bread"` rather than a resource path. A save file
## is the one file a player can hand-edit or download from a friend, and
## `systems/save/save_game.gd` refuses to let one name anything loadable for
## exactly that reason — so ids resolve through here instead. It also means
## renaming or moving a `.tres` cannot empty somebody's bag.
##
## Scanned rather than listed, because a hand-maintained list of every item is a
## list that silently goes stale the first time one is added.

const DEFS_DIR := "res://resources/items/defs"

var _by_id: Dictionary = {}


func _ready() -> void:
	_scan()


func all() -> Dictionary:
	return _by_id


func get_item(id: StringName) -> ItemData:
	return _by_id.get(id)


func has(id: StringName) -> bool:
	return _by_id.has(id)


func count() -> int:
	return _by_id.size()


func _scan() -> void:
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		push_warning("Items: no directory at %s." % DEFS_DIR)
		return
	for file in dir.get_files():
		# Exported builds rename `.tres` to `.res`; both have to be caught or
		# every item vanishes in the shipped game and only in the shipped game.
		var name := file.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var item := load("%s/%s" % [DEFS_DIR, name]) as ItemData
		if item == null or not item.is_valid():
			push_warning("Items: %s is not a usable ItemData." % name)
			continue
		if _by_id.has(item.id):
			push_error("Items: duplicate id '%s'." % item.id)
			continue
		_by_id[item.id] = item
