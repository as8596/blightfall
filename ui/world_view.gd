class_name WorldView
extends SubViewportContainer
## The window the world is seen through, and the only thing that scales it.
##
## The world renders into a fixed 1280×720 `SubViewport` with nearest filtering,
## and this container blows that image up to fill the window. The UI lives
## *outside* it, at the window's real resolution — which is the whole point:
## pixel art stays chunky and text rasterises natively, instead of both being
## authored at 720p and stretched together.
##
## Before this, `display/window/stretch/mode` was `canvas_items`, which scales
## the world and every CanvasLayer by the same factor. That is fine for the
## world and wrong for text: on a 1440p monitor the HUD was 720p type at 2×, and
## on 1080p it was 720p type at 1.5×, which is the ugly one.

## What the world is drawn at, before scaling. GDD §15 A1.
const BASE := Vector2i(1280, 720)

## Whole-number scaling only. 1280×720 into 1920×1080 is 1.5×, which duplicates
## every other row of pixels; forced to whole numbers it is 1× in a letterbox
## instead. Crisper and smaller — a real trade, so it is the player's to make
## (GDD §14) rather than ours.
@export var integer_scale: bool = false:
	set(value):
		integer_scale = value
		_fit()

@onready var viewport: SubViewport = $SubViewport


func _ready() -> void:
	stretch = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.size = BASE
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.size_changed.connect(_fit)
	_fit()


## Centre the 1280×720 image in the window at the largest scale that fits.
func _fit() -> void:
	if viewport == null:
		return
	var window := Vector2(get_tree().root.size)
	if window.x <= 0.0 or window.y <= 0.0:
		return

	var factor: float = minf(window.x / float(BASE.x), window.y / float(BASE.y))
	if integer_scale:
		factor = maxf(floorf(factor), 1.0)

	# Position and size are set rather than anchors, because the container is
	# being letterboxed on purpose and an anchor preset would stretch it back.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(factor, factor)
	size = Vector2(BASE)
	position = ((window - Vector2(BASE) * factor) * 0.5).floor()

	# The UI hugs the picture, not the window. On a 21:9 monitor a 16:9 world
	# leaves 440px of bar down each side, and a health bar sitting out on the
	# bar is a health bar that has come loose from the game.
	UiScale.set_content_rect(Rect2(position, Vector2(BASE) * factor))


## Where the pointer is, in world coordinates.
##
## Three transforms deep and none of them optional: the window has black bars
## down the sides, the picture inside them is scaled, and the world inside
## *that* is moved around by a camera. Anything reading `get_mouse_position()`
## straight off gets window pixels and aims at the wrong place by however wide
## the letterbox is.
static func mouse_world_position(node: CanvasItem) -> Vector2:
	var viewport := node.get_viewport()
	var window := node.get_window()
	if viewport == null or window == null:
		return node.global_position

	var area := UiScale.content_rect()
	var factor: float = area.size.x / float(BASE.x) if area.size.x > 0.0 else 1.0
	var inside: Vector2 = (Vector2(window.get_mouse_position()) - area.position) / factor
	# The canvas transform maps world to view, so its inverse maps back.
	return viewport.get_canvas_transform().affine_inverse() * inside


## The scale the world is currently drawn at. The UI does not use it — that is
## the point — but the debug overlay reports it.
func world_scale() -> float:
	return scale.x
