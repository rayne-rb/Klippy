class_name FoodBagBody
extends PetBody

signal grabbed

const BAG_WINDOW_SIZE := 110
const CORNER_RADIUS := 16.0
const WALL_THICKNESS := 14

var klippy: Klippy


func _ready() -> void:
	super._ready()
	_build_click_through_mask()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if klippy:
		_resolve_body_collision(klippy)


func _on_drag_started(_event: InputEventMouseButton) -> void:
	grabbed.emit()


static func make_texture() -> ImageTexture:
	var size := BAG_WINDOW_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var wall_color := Color(0.55, 0.35, 0.17)
	var rim_color := Color(0.42, 0.26, 0.12)
	var rim_height := size * 0.18
	var inner_size := size - WALL_THICKNESS * 2
	var inner_radius: float = max(CORNER_RADIUS - WALL_THICKNESS, 0.0)
	for y in size:
		for x in size:
			if not _inside_rounded_rect(x, y, size, size, CORNER_RADIUS):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if _inside_rounded_rect(x - WALL_THICKNESS, y - WALL_THICKNESS, inner_size, inner_size, inner_radius):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			image.set_pixel(x, y, rim_color if y < rim_height else wall_color)
	return ImageTexture.create_from_image(image)


static func _inside_rounded_rect(x: int, y: int, w: int, h: int, r: float) -> bool:
	var px := x + 0.5
	var py := y + 0.5
	var cx: float = clamp(px, r, float(w) - r)
	var cy: float = clamp(py, r, float(h) - r)
	return Vector2(px, py).distance_to(Vector2(cx, cy)) <= r
