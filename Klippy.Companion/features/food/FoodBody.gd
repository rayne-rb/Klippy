class_name FoodBody
extends PetBody

signal consumed

const FEED_AMOUNT := 5.0

var stats: PetStats
var klippy_window: Window
var bag: FoodBagBody
var contained_in: FoodBagBody
var contained_offset: Vector2i = Vector2i.ZERO
var food_type: String = "standard"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if state == State.DRAGGING:
		contained_in = null
		return

	if contained_in:
		_follow_container()
		return

	_check_bag_containment()
	_check_feeding()


func _follow_container() -> void:
	var bag_window := contained_in.get_window()
	var food_window := get_window()
	food_window.visible = bag_window.visible
	if bag_window.visible:
		food_window.position = bag_window.position + contained_offset
	velocity = Vector2.ZERO
	angular_velocity = 0.0


func _check_bag_containment() -> void:
	if bag == null or not bag.get_window().visible:
		return

	var bag_window := bag.get_window()
	var bag_rect := Rect2i(bag_window.position, bag_window.size)
	var food_window := get_window()
	var food_rect := Rect2i(food_window.position, food_window.size)

	if not bag_rect.intersects(food_rect):
		return

	var offset := food_window.position - bag_window.position
	var margin := FoodBagBody.WINDOW_MARGIN
	var max_offset := bag_window.size - Vector2i.ONE * margin - food_window.size
	contained_offset = Vector2i(
		clampi(offset.x, margin, max(max_offset.x, margin)),
		clampi(offset.y, margin, max(max_offset.y, margin))
	)
	contained_in = bag
	food_window.move_to_front()


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
