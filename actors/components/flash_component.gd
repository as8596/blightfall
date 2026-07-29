class_name FlashComponent
extends Node
## White hit-flash via shader, not `modulate` (GDD §5, BUILD-PLAN week 3).
##
## `modulate` multiplies, so it can only ever darken a sprite — it cannot make
## a dark pixel white. The shader mixes toward the flash colour instead, which
## is why the rule exists. The material is duplicated per instance at runtime so
## one enemy flashing doesn't flash the whole pack.
##
## **The material is attached only while flashing.** It used to sit on the sprite
## permanently at `flash_amount = 0.0`, which reads as a no-op and is not one: in
## the Compatibility renderer a canvas item with a custom shader takes a
## different colour path from one without, and the result was every sprite in the
## game rendering squared — `#d9c48d` reaching the screen as `#b9974e`. Measured,
## not guessed: 58 of the player's 59 colours survive with no material attached,
## and none of them survive with one.
##
## That is a whole-game colour cast for a shader that was doing nothing 99% of
## the time, and it showed up as "why does the character look so red" rather than
## as anything a test was watching. Attaching on demand costs one assignment per
## hit and makes the untouched case pixel-exact by construction.

const FLASH_SHADER: Shader = preload("res://art/shaders/hit_flash.gdshader")

## The CanvasItem to flash. Defaults to a sibling named "Visual".
@export var target_path: NodePath = ^"../Visual"

## GDD §5: white for 0.08s.
@export var flash_time: float = 0.08

@export var flash_color: Color = Color.WHITE

var _target: CanvasItem
var _material: ShaderMaterial
var _remaining: float = 0.0


func _ready() -> void:
	set_process(false)
	_target = get_node_or_null(target_path) as CanvasItem
	if _target == null:
		push_warning("FlashComponent on %s: no CanvasItem at '%s'." % [get_parent(), target_path])
		return
	_material = ShaderMaterial.new()
	_material.shader = FLASH_SHADER
	_material.set_shader_parameter(&"flash_amount", 0.0)
	_material.set_shader_parameter(&"flash_color", flash_color)
	# Deliberately not assigned here. See the class comment.


func _process(delta: float) -> void:
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining > 0.0:
		return
	_set_amount(0.0)
	set_process(false)


## Flash now. `duration` <= 0 uses `flash_time`.
func flash(duration: float = -1.0) -> void:
	if _material == null:
		return
	_remaining = flash_time if duration <= 0.0 else duration
	_material.set_shader_parameter(&"flash_color", flash_color)
	_set_amount(1.0)
	set_process(true)


## Hold the flash until `clear()`. Used by the death animation.
func hold(color: Color = Color.WHITE) -> void:
	if _material == null:
		return
	set_process(false)
	_remaining = 0.0
	_material.set_shader_parameter(&"flash_color", color)
	_set_amount(1.0)


func clear() -> void:
	set_process(false)
	_remaining = 0.0
	_set_amount(0.0)


## Set the mix, and attach or detach the material with it. Detaching is the
## point: a sprite showing its own colours must not be going through the shader
## at all.
func _set_amount(value: float) -> void:
	if _material == null or _target == null:
		return
	_material.set_shader_parameter(&"flash_amount", value)
	var wanted: Material = _material if value > 0.0 else null
	if _target.material != wanted:
		_target.material = wanted


func is_flashing() -> bool:
	return _remaining > 0.0
