extends Node
## The volume sliders, and the buses they move.
##
## **The buses are made here rather than shipped as a `default_bus_layout`.**
## A bus layout is a binary resource that does not diff, and the whole of what
## this project needs from one is "two children of Master". Building them in
## code means the mix is readable in a text file and cannot silently lose a bus
## to a merge.
##
## Volumes are stored as 0..1 and converted to decibels on the way out, because
## a slider is linear and hearing is not: -20dB is *half as loud*, not a fifth,
## and a slider that moves in decibels does nothing for its first third and
## everything in its last.

signal changed

const CONFIG_PATH := "user://settings.cfg"

## Bus name to its default level. Master last is deliberate — it multiplies the
## other two, so a player who pulls it down has turned everything down rather
## than having to find both.
const BUSES := {"Music": 0.7, "Sfx": 0.9, "Master": 1.0}

var _levels: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_restore()


## Make `Music` and `Sfx` if they are not already there, both routed to Master.
## Idempotent: an exported project that ships a layout keeps it.
func _ensure_buses() -> void:
	for name in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var at := AudioServer.bus_count
		AudioServer.add_bus(at)
		AudioServer.set_bus_name(at, name)
		AudioServer.set_bus_send(at, "Master")


## 0..1, where 1 is unattenuated.
func volume(bus: String) -> float:
	return float(_levels.get(bus, BUSES.get(bus, 1.0)))


func set_volume(bus: String, level: float) -> void:
	var clamped: float = clampf(level, 0.0, 1.0)
	_levels[bus] = clamped
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	# Silence is its own case: `linear_to_db(0)` is negative infinity, which
	# Godot handles, but muting the bus outright is cheaper and unambiguous.
	AudioServer.set_bus_mute(index, clamped <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.001)))
	changed.emit()
	_save()


func _restore() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(CONFIG_PATH) == OK
	for bus in BUSES:
		var stored: float = float(config.get_value("audio", bus, BUSES[bus])) if loaded \
			else float(BUSES[bus])
		# Applied through the setter so the bus and the table can never disagree,
		# but without saving on the way in — restoring is not choosing.
		var clamped: float = clampf(stored, 0.0, 1.0)
		_levels[bus] = clamped
		var index := AudioServer.get_bus_index(bus)
		if index != -1:
			AudioServer.set_bus_mute(index, clamped <= 0.001)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.001)))


func _save() -> void:
	var config := ConfigFile.new()
	# Read first, so this never becomes the file that eats the UI scale setting.
	@warning_ignore("return_value_discarded")
	config.load(CONFIG_PATH)
	for bus in _levels:
		config.set_value("audio", bus, _levels[bus])
	@warning_ignore("return_value_discarded")
	config.save(CONFIG_PATH)
