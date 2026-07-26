class_name HealthComponent
extends Node
## HP, damage handling, and a `died` signal (BUILD-PLAN week 3).
##
## Deliberately knows nothing about hurtboxes, i-frames or knockback — it is
## just a number that can go down. Invulnerability is the Hurtbox's business.

signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal died
signal changed(current: int, max_health: int)

## Player: 6 hearts to start, 12 max (GDD §5). Enemies: see EnemyData.
@export var max_health: int = 6

## Debug / cutscene switch. Damage is silently ignored while true.
@export var invincible: bool = false

var current: int


func _ready() -> void:
	current = max_health
	changed.emit(current, max_health)


## Returns true if any damage was actually applied.
func take_damage(amount: int, source: Node = null) -> bool:
	if invincible or amount <= 0 or not is_alive():
		return false
	current = maxi(current - amount, 0)
	damaged.emit(amount, source)
	changed.emit(current, max_health)
	if current == 0:
		died.emit()
	return true


func heal(amount: int) -> void:
	if amount <= 0 or not is_alive():
		return
	var before := current
	current = mini(current + amount, max_health)
	if current != before:
		healed.emit(current - before)
		changed.emit(current, max_health)


func set_max_health(value: int, refill: bool = true) -> void:
	max_health = maxi(1, value)
	current = max_health if refill else mini(current, max_health)
	changed.emit(current, max_health)


func reset() -> void:
	current = max_health
	changed.emit(current, max_health)


func is_alive() -> bool:
	return current > 0


func fraction() -> float:
	return float(current) / float(maxi(max_health, 1))
