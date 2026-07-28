class_name StaminaComponent
extends Node
## Dodge stamina — and *only* dodge stamina (GDD §6, decided).
##
## Attacks cost nothing. This is a rhythm limiter that stops panic-rolling, not
## a resource to manage. If dodging ever feels like budgeting, `max_stamina` is
## too small — that is the week 4 check, and it is a real one.

signal changed(current: float, max_stamina: float)
signal spent(amount: float)
signal depleted

## A spend was turned down for want of stamina. `depleted` fires when the pool
## reaches zero, which is a different moment: you can empty it on a dash that
## succeeded. This is the one where the limiter says no, and it is the only time
## the player needs telling about stamina at all.
signal refused(amount: float)

## 4 consecutive dodges (GDD §6).
@export var max_stamina: float = 4.0

## Seconds to refill from empty. GDD: ~1.5s.
@export var full_regen_time: float = 1.5

## Pause before regen resumes after spending. 0 keeps the pool generous.
@export var regen_delay: float = 0.0

var current: float
var _delay_remaining: float = 0.0


func _ready() -> void:
	current = max_stamina
	changed.emit(current, max_stamina)


func _process(delta: float) -> void:
	if _delay_remaining > 0.0:
		_delay_remaining = maxf(_delay_remaining - delta, 0.0)
		return
	if current >= max_stamina:
		return
	current = minf(current + regen_rate() * delta, max_stamina)
	changed.emit(current, max_stamina)


func regen_rate() -> float:
	return max_stamina / maxf(full_regen_time, 0.0001)


func can_spend(amount: float) -> bool:
	return current >= amount


## Returns false and changes nothing if the pool is too low.
func spend(amount: float) -> bool:
	if not can_spend(amount):
		refused.emit(amount)
		return false
	current = maxf(current - amount, 0.0)
	_delay_remaining = regen_delay
	spent.emit(amount)
	changed.emit(current, max_stamina)
	if is_zero_approx(current):
		depleted.emit()
	return true


func refill() -> void:
	current = max_stamina
	_delay_remaining = 0.0
	changed.emit(current, max_stamina)


func fraction() -> float:
	return current / maxf(max_stamina, 0.0001)
