class_name FoodBody
extends PetBody

const FEED_AMOUNT := 5.0

var stats: PetStats
var klippy_window: Window


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_check_feeding()


func _check_feeding() -> void:
	if klippy_window == null or stats == null or state == State.DRAGGING:
		return

	var klippy_rect := Rect2i(klippy_window.position, klippy_window.size)
	var food_rect := Rect2i(get_window().position, get_window().size)

	if klippy_rect.intersects(food_rect):
		stats.feed(FEED_AMOUNT)
		get_window().queue_free()
