class_name Prop
extends Node2D
## A drawn thing standing in the world: a tree, a bush, a barrel, a cart.
##
## Props are not tiles. A tile is 64x64, aligned to the grid, and drawn on one
## layer for the whole map — which is right for ground and walls, and wrong for
## anything the player walks *behind*. A tree is 200px tall, occupies a third of
## a tile at its base, and has to sort against the player by its trunk. That is a
## node, not a cell.
##
## **The base is the origin.** The sprite is offset up by its own height so the
## point the thing stands on sits at `position`, which is what y-sorting sorts
## by. Get this wrong and a tree drawn from its centre sorts as though the player
## were standing at its canopy — you walk behind a tree while still well in front
## of it.
##
## **The sort point is not always the base.** Something the player can walk into
## sorts half way up its own picture instead, so they are drawn in front of a
## bush until they have waded past the middle of it. See `SORT_BIAS`.
##
## **`z_index` stays 0.** Godot applies z_index before y-sorting, so a prop on a
## different z than the player is either always in front or always behind it, and
## no amount of correct sorting inside the layer will fix that (this cost an
## afternoon once already — see the roofs in Ambry).

## The picture. Frame 0 of a strip if `frames` is set.
@export var texture: Texture2D:
	set(value):
		texture = value
		_refresh()

## Blocks movement. A bush usually should not; a tree should.
@export var solid: bool = true:
	set(value):
		solid = value
		_refresh()

## The blocking footprint, in pixels, centred on the base.
##
## Deliberately separate from the sprite size and deliberately small: what stops
## the player is the trunk, not the canopy. A collider matching the drawn
## silhouette makes a forest feel like a maze of invisible walls, because the
## player is stopped by branches they can clearly see they are under.
@export var footprint: Vector2 = Vector2(28, 16):
	set(value):
		footprint = value
		_refresh()

## Draw the art larger than it was authored.
##
## **Integer values only, and the reason is the pixel grid.** At 2.0 every source
## pixel becomes a clean 2x2 block; at 1.6 some become 2px and some stay 1px, and
## the eye reads the unevenness as a broken sprite long before it reads it as a
## bigger tree. Anything non-integer is snapped down with a warning.
##
## This exists because a tree drawn at the same resolution as the character is a
## tree the same height as the character. Scaling up trades pixel density for
## scale, which is the right trade for background mass and the wrong one for
## anything the player has to read quickly — so it is a per-prop knob rather than
## a global one.
@export var art_scale: float = 1.0:
	set(value):
		art_scale = value
		_refresh()

## Nudge the drawn image without moving the sorting origin. For art whose base
## is not exactly at the bottom of its canvas.
@export var art_offset: Vector2 = Vector2.ZERO:
	set(value):
		art_offset = value
		_refresh()

## Mirror the sprite. Set per-instance by a map builder so a row of the same
## tree is not a row of the same picture.
@export var flip: bool = false:
	set(value):
		flip = value
		_refresh()

var _sprite: Sprite2D
var _body: StaticBody2D
var _shape: CollisionShape2D


## How see-through a prop goes when the player is behind it, and how fast it
## gets there. Not fully transparent: a ghost of the canopy is what tells you
## you are *behind* something rather than that the tree has vanished.
const FADE_TO := 0.35
const FADE_SPEED := 6.0

## Only things that actually hide you bother tracking the player. A thorn bush
## is shorter than he is and fading it would be a flicker for nothing.
const FADE_ABOVE := 96.0

## How far up its own picture a prop sorts against the player, as a fraction of
## the drawn height. Half: you are in front of a bush until you have waded past
## the middle of it, and behind it after.
##
## **Why it is needed at all.** Sorting on the base is right for something you
## cannot enter, and wrong for something you can. A bush blocks nothing, so the
## player walks *into* it — and the instant their feet cross its bottom edge
## they were drawn behind the whole thing, standing in the front half of a bush
## that was covering them. Half-height is where it stops looking wrong.
##
## Godot has no per-node sort offset, but it does flatten nested Y-sort trees:
## this node is `y_sort_enabled`, so its Sprite2D is sorted against the player by
## the sprite's *own* global Y. Lifting the sprite node and pushing its `offset`
## back down by the same amount moves the sort point and not the picture — and
## the prop's origin stays on the base, which every builder and collider depends
## on.
const SORT_BIAS := 0.5

var _cover: Rect2 = Rect2()
var _fade: float = 1.0


func _ready() -> void:
	y_sort_enabled = true
	# Same z as the player, or sorting cannot help us. See the class comment.
	z_index = 0
	_build()
	_refresh()
	set_process(_cover.size.y >= FADE_ABOVE)


## Fade out while the player is underneath the drawn sprite.
##
## **The test is the picture, not the trunk.** A radius around the base fades a
## tree you are standing beside and in front of, and fails to fade the one whose
## canopy you are actually lost behind — the canopy is 4 tiles tall and the
## footprint is a third of one. So this asks whether the player is inside the
## rectangle the sprite covers, which is the only thing that can hide them.
##
## Polled rather than driven by an `Area2D`, because the area that matters is
## the *art* and it changes with `art_scale`; keeping a second collision shape
## in step with the sprite is a bug waiting for the first prop that resizes.
func _process(delta: float) -> void:
	var wanted := 1.0
	var scene := get_tree().current_scene
	var player := scene.get("player") as Node2D if scene != null else null
	if player != null and _cover.has_point(player.global_position - global_position):
		wanted = FADE_TO
	if is_equal_approx(_fade, wanted):
		return
	_fade = move_toward(_fade, wanted, FADE_SPEED * delta)
	if _sprite != null:
		_sprite.modulate.a = _fade


func _build() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)

	_body = StaticBody2D.new()
	_body.collision_layer = 1        # World
	_body.collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	_body.add_child(_shape)
	add_child(_body)


func _refresh() -> void:
	if _sprite == null:
		return
	_sprite.texture = texture
	_sprite.flip_h = flip
	var zoom := maxf(floorf(art_scale), 1.0)
	if not is_equal_approx(zoom, art_scale):
		push_warning("Prop %s: art_scale %.2f is not a whole number; using %d."
			% [name, art_scale, int(zoom)])
	_sprite.scale = Vector2(zoom, zoom)
	if texture != null:
		# Base on the origin. Same rule as AnimationComponent's feet-on-origin.
		# In sprite-local units, so `scale` multiplies it and the base stays put
		# however tall the thing is drawn.
		#
		# The lift is added back here in the same units, so moving the sort point
		# below cannot move the picture: `position` goes up by `lift` in prop
		# space, `offset` comes down by `lift / zoom` in sprite space, and they
		# cancel exactly.
		var lift := _sort_lift()
		_sprite.position = Vector2(0.0, -lift)
		_sprite.offset = Vector2(0, -texture.get_height() * 0.5 + lift / zoom) + art_offset / zoom
	# What the sprite covers, in this prop's own space, so `_process` can ask
	# whether the player is under the picture. Recomputed here because it moves
	# with the texture, the scale and the offset — all three of which are
	# exported and can change after `_ready`.
	if texture != null:
		var drawn := texture.get_size() * zoom
		_cover = Rect2(Vector2(-drawn.x * 0.5, -drawn.y) + art_offset, drawn)
	set_process(_cover.size.y >= FADE_ABOVE)

	(_shape.shape as RectangleShape2D).size = footprint
	# The footprint sits *behind* the base by half its depth, so the player can
	# stand at the foot of a tree rather than being held a body-length away.
	_shape.position = Vector2(0, -footprint.y * 0.5)
	_body.process_mode = Node.PROCESS_MODE_INHERIT if solid else Node.PROCESS_MODE_DISABLED
	_shape.disabled = not solid


## How far above the base this prop sorts, in pixels. Zero for most things.
##
## **Two exclusions, and both are the difference between a fix and a new bug.**
##
## *Solid props sort on their base.* The footprint already stops the player
## short, so they can never be inside a barrel or a trunk — and a lifted sort
## point would draw them in front of a tree they are demonstrably standing
## behind, which is the original complaint with the sign reversed.
##
## *So does anything taller than the player.* `FADE_ABOVE` is already the line
## this file draws between something you are *in* and something you are *under*,
## and the answer for the second kind is the fade, not the sort — a 512px
## thicket tree lifted by 256 would let you walk a quarter of a screen past it
## still drawn on top. Reusing the constant keeps the two halves of that
## judgement from drifting apart.
func _sort_lift() -> float:
	if solid or texture == null:
		return 0.0
	var drawn := texture.get_height() * maxf(floorf(art_scale), 1.0)
	if drawn >= FADE_ABOVE:
		return 0.0
	return drawn * SORT_BIAS
