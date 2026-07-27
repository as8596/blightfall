extends Node
## Save/load. JSON on disk, a registration pattern in the tree.
##
## Built now rather than later because a save system touches everything, and
## retrofitting one means revisiting every system that turned out to own state.
## Right now it persists almost nothing — a player and a position — and that is
## fine. What matters is that adding heart shards, tools, quest flags or which
## lines the fox has already said becomes *two methods on the node that owns
## that state*, not a change to this file.
##
## **Why JSON and not ResourceSaver.** A `.tres` can name a script, so loading
## one at runtime executes whatever it points at — a save file is the one file
## in the game a player can hand-edit or download from a friend, which makes it
## the worst possible place to accept that. JSON carries data and only data.
## It is also diffable, hand-fixable, and doesn't break when a class is renamed.
##
## **How a node opts in.** Join the `saveable` group and implement three
## methods:
##
##     func save_id() -> StringName: return &"player"
##     func save_data() -> Dictionary: return {"health": 5}
##     func load_data(data: Dictionary) -> void: ...
##
## Ids are stable strings, not node paths — moving a node in the scene tree
## must not invalidate saves.

signal saved(slot: int)
signal loaded(slot: int)
signal save_failed(slot: int, reason: String)

const GROUP: StringName = &"saveable"

## Bump when the schema changes in a way old files can't satisfy, and add a
## branch to `_migrate`. A version field costs nothing now and is the difference
## between "old saves still work" and "everyone loses their progress".
const VERSION: int = 1

const SLOT_COUNT: int = 3

var playtime: float = 0.0

var _last_error: String = ""


func _process(delta: float) -> void:
	playtime += delta


# --------------------------------------------------------------- file paths

static func slot_path(slot: int) -> String:
	return "user://save_%02d.json" % slot


static func backup_path(slot: int) -> String:
	return slot_path(slot) + ".bak"


static func temp_path(slot: int) -> String:
	return slot_path(slot) + ".tmp"


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func delete_save(slot: int) -> void:
	for path in [slot_path(slot), backup_path(slot), temp_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# ------------------------------------------------------------ capture/apply

## Walk the saveable group and build the save payload.
func capture() -> Dictionary:
	var entries := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		if not _is_saveable(node):
			push_warning("SaveGame: %s is in the saveable group but lacks the interface." % node)
			continue
		var id := String(node.call(&"save_id"))
		if id.is_empty():
			continue
		if entries.has(id):
			push_error("SaveGame: duplicate save_id '%s'." % id)
			continue
		entries[id] = node.call(&"save_data")

	var scene_path := ""
	var current := get_tree().current_scene
	if current != null:
		scene_path = current.scene_file_path

	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"playtime": playtime,
		"scene": scene_path,
		"entries": entries,
	}


## Hand each saveable node its entry. Nodes with no entry are left alone, so a
## save written before a system existed still loads.
func apply(data: Dictionary) -> void:
	var entries: Dictionary = data.get("entries", {})
	playtime = float(data.get("playtime", 0.0))
	for node in get_tree().get_nodes_in_group(GROUP):
		if not _is_saveable(node):
			continue
		var id := String(node.call(&"save_id"))
		if entries.has(id) and entries[id] is Dictionary:
			node.call(&"load_data", entries[id])


static func _is_saveable(node: Node) -> bool:
	return node.has_method(&"save_id") \
		and node.has_method(&"save_data") \
		and node.has_method(&"load_data")


# ------------------------------------------------------------------- disk io

## Write the slot. Returns false and emits `save_failed` on any problem.
##
## Writes to a temp file and renames over the real one, keeping the previous
## save as `.bak`. A save interrupted halfway — alt-F4, power cut, full disk —
## must not be able to destroy the save the player already had.
func save_slot(slot: int) -> bool:
	_last_error = ""
	var payload := capture()
	var text := JSON.stringify(payload, "  ")

	var temp := temp_path(slot)
	var handle := FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		return _fail(slot, "cannot open %s (%d)" % [temp, FileAccess.get_open_error()])
	handle.store_string(text)
	handle.close()

	var final := slot_path(slot)
	if FileAccess.file_exists(final):
		if FileAccess.file_exists(backup_path(slot)):
			DirAccess.remove_absolute(backup_path(slot))
		DirAccess.rename_absolute(final, backup_path(slot))

	var error := DirAccess.rename_absolute(temp, final)
	if error != OK:
		return _fail(slot, "rename failed (%d)" % error)

	saved.emit(slot)
	return true


## Read and validate a slot. Returns an empty dictionary if it is missing or
## unusable; `last_error()` says which.
func read_slot(slot: int) -> Dictionary:
	_last_error = ""
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		_last_error = "no save in slot %d" % slot
		return {}

	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		_last_error = "cannot read %s" % path
		return {}
	var text := handle.get_as_text()
	handle.close()

	# JSON.parse_string() pushes an engine error on malformed input. A save file
	# is the one file a player can hand-edit, so malformed is an expected case,
	# not an exceptional one — parse through an instance and handle it quietly.
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	var parsed: Variant = parser.data if parse_error == OK else null
	if not (parsed is Dictionary):
		# Hand-edited or truncated. Fall back to the backup rather than telling
		# the player their progress is gone.
		_last_error = "slot %d is not valid JSON (%s)" % [slot, parser.get_error_message()]
		return _read_backup(slot)

	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version > VERSION:
		_last_error = "slot %d was written by a newer version (%d > %d)" % [slot, version, VERSION]
		return {}
	if version < VERSION:
		data = _migrate(data, version)
	if not (data.get("entries") is Dictionary):
		_last_error = "slot %d has no entries" % slot
		return {}
	return data


func _read_backup(slot: int) -> Dictionary:
	var path := backup_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return {}
	var parser := JSON.new()
	var ok := parser.parse(handle.get_as_text()) == OK
	handle.close()
	var parsed: Variant = parser.data if ok else null
	if parsed is Dictionary and (parsed as Dictionary).get("entries") is Dictionary:
		_last_error += " — recovered from backup"
		return parsed
	return {}


## Load a slot into the current scene. Does not change scenes — see
## `load_slot_into_scene` for that.
func load_slot(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	apply(data)
	loaded.emit(slot)
	return true


## Load a slot, switching scenes first if the save was made somewhere else.
func load_slot_into_scene(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false

	var scene_path := String(data.get("scene", ""))
	var current := get_tree().current_scene
	var here := current.scene_file_path if current != null else ""
	if not scene_path.is_empty() and scene_path != here:
		if not ResourceLoader.exists(scene_path):
			return _fail(slot, "save points at a missing scene: %s" % scene_path)
		get_tree().change_scene_to_file(scene_path)
		# change_scene_to_file is deferred; the new tree is not up until the
		# next idle frame, and applying into the old one would silently do
		# nothing.
		await get_tree().tree_changed
		await get_tree().process_frame

	apply(data)
	loaded.emit(slot)
	return true


## Schema upgrades. Each step moves one version forward, so a v1 save still
## opens after the format has moved on three times.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var version := from_version
	while version < VERSION:
		match version:
			0:
				# Pre-versioning files, if any ever escaped. Nothing to do but
				# claim them.
				data["version"] = 1
			_:
				break
		version = int(data.get("version", version + 1))
	return data


func _fail(slot: int, reason: String) -> bool:
	_last_error = reason
	push_error("SaveGame: " + reason)
	save_failed.emit(slot, reason)
	return false


func last_error() -> String:
	return _last_error


# ------------------------------------------- typed readers for load_data()

## JSON has one number type, so every integer comes back as a float and every
## field can be missing or the wrong type in a file a player has edited. These
## are the only way values should be pulled out of a save entry.

static func read_int(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key)
	return int(value) if (value is float or value is int) else fallback


static func read_float(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key)
	return float(value) if (value is float or value is int) else fallback


static func read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key)
	return bool(value) if value is bool else fallback


static func read_string(data: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = data.get(key)
	return String(value) if value is String else fallback


static func read_vector2(data: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var value: Variant = data.get(key)
	if not (value is Array) or (value as Array).size() != 2:
		return fallback
	var array: Array = value
	if not (array[0] is float or array[0] is int):
		return fallback
	if not (array[1] is float or array[1] is int):
		return fallback
	return Vector2(float(array[0]), float(array[1]))


## Vector2 as a JSON-safe pair.
static func write_vector2(value: Vector2) -> Array:
	return [value.x, value.y]
