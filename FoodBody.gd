class_name FoodBody
extends PetBody

signal consumed
signal stored

const FEED_AMOUNT := 5.0

var stats: PetStats
var klippy_window: Window
var bag_window: Window
var food_type: String = "standard"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _check_storing():
		return
	_check_feeding()


func _check_storing() -> bool:
	if bag_window == null or not bag_window.visible or state == State.DRAGGING:
		return false

	var bag_rect := Rect2i(bag_window.position, bag_window.size)
	var food_rect := Rect2i(get_window().position, get_window().size)

	if bag_rect.intersects(food_rect):
		stored.emit()
		return true
	return false


func _check_feeding() -> void:
	if klippy_window == null or stats == null or state == State.DRAGGING:
		return

	var klippy_rect := Rect2i(klippy_window.position, klippy_window.size)
	var food_rect := Rect2i(get_window().position, get_window().size)

	if klippy_rect.intersects(food_rect):
		stats.feed(FEED_AMOUNT)
		consumed.emit()


static func make_texture(_food_type: String = "standard") -> ImageTexture:
	var diameter := 40
	var image := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var radius := diameter / 2.0
	var center := Vector2(radius, radius)
	for y in diameter:
		for x in diameter:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			image.set_pixel(x, y, Color(0.85, 0.2, 0.2, 1.0) if dist <= radius else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
