class_name ExperienceComponent
extends Node
## Points, levels, and nothing else.
##
## **This amends GDD §15 A7**, which said flatly that there is no XP and no
## level. There is now — the HUD carries a bar for it. What A7 was actually
## protecting is kept intact, though, and kept here rather than remembered: a
## level *grants nothing*. It emits `player_leveled` and stops. Every stat in
## the game still comes from `StatsComponent`, still carries the id of the
## building that granted it, and is still refused without one.
##
## So the bar reads as "how far along am I", and the village is still the only
## thing that makes you stronger. If a level is ever meant to hand out a stat,
## that decision goes in the GDD before it goes in the code, because it is the
## decision A7 exists to slow down.

signal changed(current: int, needed: int, level: int)
signal leveled(level: int)

## Points into the current level, not the lifetime total. A bar wants the
## former, and the latter is recoverable from it whenever something needs it.
var current: int = 0
var level: int = 1

## What level 1 costs. Each level after it costs `growth` times the last,
## rounded — gentle enough that early levels arrive while the player is still
## learning what one is for.
@export var first_level_cost: int = 60
@export_range(1.0, 2.0, 0.01) var growth: float = 1.35

## Where the curve stops climbing. Not a level cap — a cost cap.
@export var max_level: int = 30


func _ready() -> void:
	changed.emit.call_deferred(current, needed(), level)


## Points to finish the level the player is on.
func needed() -> int:
	var cost := float(first_level_cost)
	for i in range(1, mini(level, max_level)):
		cost *= growth
	return int(roundf(cost))


## Lifetime total, for a character sheet that wants to say a bigger number.
func total() -> int:
	var sum := current
	var cost := float(first_level_cost)
	for i in range(1, level):
		sum += int(roundf(cost))
		cost *= growth
	return sum


## Award `amount`. Rolls over as many levels as it earns, so a single large
## award cannot be silently capped at one.
func grant(amount: int) -> void:
	if amount <= 0:
		return
	current += amount
	var gained := 0
	while current >= needed():
		current -= needed()
		level += 1
		gained += 1
		leveled.emit(level)
		# A runaway grant should not lock the frame. Nothing awards this much,
		# and "nothing does" is exactly the kind of thing that stops being true.
		if gained > 100:
			break
	changed.emit(current, needed(), level)


func save_data() -> Dictionary:
	return {"current": current, "level": level}


func load_data(data: Dictionary) -> void:
	level = maxi(SaveGame.read_int(data, "level", level), 1)
	current = maxi(SaveGame.read_int(data, "current", current), 0)
	changed.emit(current, needed(), level)
