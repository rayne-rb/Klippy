class_name FoodBody
extends PetBody

signal consumed

const FEED_AMOUNT := 5.0

var stats: PetStats
var klippy_window: Window
var bag: FoodBagBody
var contained_in: FoodBagBody
var food_type: String = "standard"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if state == State.DRAGGING:
		contained_in = null
		return

	_check_bag()
	_check_feeding()


## "Stored" is a live membership test against the bag's background art, not a
## sticky flag: a food item only counts while it is actually sitting over the
## background this frame, so one that has rolled back out is no longer saved
## with the bag. The bag's walls are a real physical obstacle here (see
## [method FoodBagBody.resolve_food_wall_collision]) rather than a place that
## pins food in position, so a stored item keeps rolling/settling like any
## other food — it's just confined to the bag's interior.
func _check_bag() -> void:
	contained_in = null
	if bag == null:
		return

	var bag_window := bag.get_window()
	var food_window := get_window()
	var local_center := Vector2(food_window.position - bag_window.position) + Vector2(food_window.size) / 2.0
	var over_bag := Rect2(Vector2.ZERO, Vector2(bag_window.size)).has_point(local_center)

	# A closed bag tucks away whatever is inside it; food sitting elsewhere on
	# the desktop shouldn't vanish just because the bag elsewhere got closed.
	food_window.visible = bag_window.visible or not over_bag
	if not bag_window.visible:
		return

	bag.resolve_food_wall_collision(self)

	if bag.contains_point(local_center):
		contained_in = bag
		food_window.move_to_foreground()


func _check_feeding() -> void:
	if klippy_window == null or stats == null:
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
