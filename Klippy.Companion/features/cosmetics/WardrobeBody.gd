class_name WardrobeBody
extends PetBody

## Emitted when the wardrobe is clicked without being dragged — Klippy.gd
## connects this to open the cosmetic picker.
signal opened

const TEXTURE: Texture2D = preload("res://assets/KlippyWardrobe.png")

## Rendered height of the wardrobe art on screen; width follows from the
## texture's own aspect ratio. Matches FoodBagBody.TARGET_HEIGHT so the two
## spawnable props read as the same visual scale next to Klippy.
const TARGET_HEIGHT := 300.0

## Extra room around the art so a rotated corner has space to swing through
## before it hits the window edge and gets clipped.
const WINDOW_MARGIN := 55

## Net window-position displacement (px, per axis) between press and release
## below which a press counts as "clicked," not "dragged." PetBody's drag
## follow is a lerp, so even a stationary click nudges the window a
## sub-pixel amount over however many frames elapse before release — this
## just needs to clear that jitter while still catching a deliberate small
## drag.
const CLICK_DRAG_THRESHOLD := 6

var klippy: Klippy

var _press_window_position: Vector2i


func _ready() -> void:
	# A wardrobe is an upright cabinet, not a ball — it shouldn't pick up spin
	# from throws/bounces/drag-wheel the way Klippy and food do.
	can_rotate = false

	var wardrobe_sprite := Sprite2D.new()
	wardrobe_sprite.name = "Sprite2D"
	wardrobe_sprite.texture = TEXTURE
	wardrobe_sprite.scale = Vector2.ONE * (TARGET_HEIGHT / TEXTURE.get_size().y)
	add_child(wardrobe_sprite)

	super._ready()
	_build_click_through_mask()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if klippy and get_window().visible:
		_resolve_body_collision(klippy, delta)


func _on_drag_started(_event: InputEventMouseButton) -> void:
	_press_window_position = get_window().position


func _on_drag_ended() -> void:
	var moved := get_window().position - _press_window_position
	if maxi(absi(moved.x), absi(moved.y)) <= CLICK_DRAG_THRESHOLD:
		opened.emit()


func _content_inset() -> float:
	return WINDOW_MARGIN
