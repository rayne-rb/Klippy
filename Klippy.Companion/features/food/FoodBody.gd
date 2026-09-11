class_name FoodBody
extends PetBody

signal consumed

const FEED_AMOUNT := 5.0

var stats: PetStats
var klippy_window: Window
var bag: FoodBagBody
var contained_in: FoodBagBody
var food_type: String = "standard"

## Every food item currently in the tree (bag-contained, loose on the desktop,
## or pooled-and-hidden alike), so any one of them can find the rest to
## collide with. Nothing here is a manager pass; each item just looks up its
## own neighbors and resolves against those that haven't been resolved yet
## this tick (see [method _resolve_food_collisions]).
static var _all_food: Array[FoodBody] = []


func _enter_tree() -> void:
	_all_food.append(self)


func _exit_tree() -> void:
	_all_food.erase(self)


func _physics_process(delta: float) -> void:
	var pre_move_position := get_window().position
	super._physics_process(delta)

	if state == State.DRAGGING:
		contained_in = null
		return

	_resolve_food_collisions()
	_check_bag(pre_move_position)
	_check_feeding()


## Bounces this item off every other live food item it overlaps, using the
## same circle-circle math [method PetBody._resolve_body_collision] already
## uses for Klippy-vs-bag. Walking the shared registry from just past this
## item's own index means each pair only ever gets resolved once per tick,
## no matter which of the two items happens to process first.
func _resolve_food_collisions() -> void:
	var index := _all_food.find(self)
	if index == -1:
		return

	for i in range(index + 1, _all_food.size()):
		var other := _all_food[i]
		if not is_instance_valid(other) or not other.is_physics_processing():
			continue
		_resolve_body_collision(other)


## A bag-associated item has no floor of its own to rest on the way loose food
## does on the real desktop, so it must never latch into a static
## [constant State.IDLE] — that would just freeze it wherever gravity
## happened to zero its velocity for one tick. Food with no bag keeps the
## normal desktop resting behavior.
func _can_rest() -> bool:
	return bag == null


func _process_idle_base(_delta: float, _window: Window) -> void:
	if bag != null:
		_set_state(State.THROWN)


## "Stored" is a live membership test against the bag's background art, not a
## sticky flag: a food item only counts while it is actually sitting over the
## background this frame, so one that has rolled back out is no longer saved
## with the bag. The bag's walls are a real physical obstacle here (see
## [method FoodBagBody.resolve_food_wall_collision]) rather than a place that
## pins food in position, so a stored item keeps rolling/settling like any
## other food — it's just confined to the bag's interior.
func _check_bag(pre_move_position: Vector2i) -> void:
	contained_in = null
	if bag == null:
		return

	var bag_window := bag.get_window()
	var food_window := get_window()
	var half_size := Vector2(food_window.size) / 2.0

	# Both measured as of the start of this tick, before anything moved —
	# the food's true position relative to the bag a moment ago.
	var prev_local_center := Vector2(pre_move_position - bag.tick_start_position) + half_size

	# Carry the food along with however far the bag itself moved this tick,
	# same as a real bag drags its contents when picked up — otherwise a
	# fast drag/throw of the bag just leaves loose contents behind in
	# mid-air, which looks exactly like food escaping. Only carry it if it
	# was actually inside the bag's footprint a moment ago; food elsewhere
	# shouldn't jump just because some unrelated bag moved.
	if Rect2(Vector2.ZERO, Vector2(bag_window.size)).has_point(prev_local_center):
		food_window.position += bag.movement_delta_this_tick()

	# The wall keeps holding contents in place even while the bag is closed —
	# a real bag doesn't spill what's inside just because you can't see it —
	# so this has to keep running regardless of [member Window.visible].
	# Skipping it while hidden used to mean gravity kept right on pulling
	# food down with nothing to stop it, so by the time the bag reopened
	# the contents had often fallen straight out through where the (now
	# uncollidable) wall used to be.
	bag.resolve_food_wall_collision(self, prev_local_center)

	# The collision may have just moved the window, so re-derive this rather
	# than reuse the pre-collision value above.
	var local_center := Vector2(food_window.position - bag_window.position) + half_size
	var over_bag := Rect2(Vector2.ZERO, Vector2(bag_window.size)).has_point(local_center)

	# A closed bag tucks away whatever is inside it; food sitting elsewhere on
	# the desktop shouldn't vanish just because the bag elsewhere got closed.
	food_window.visible = bag_window.visible or not over_bag

	# Keep it above the bag's background whenever it's anywhere over the bag
	# at all, not just once it's confirmed "stored" — otherwise it can sit
	# behind the background art (invisible) for however long it takes to
	# settle into the stricter interior zone.
	if bag_window.visible and over_bag:
		food_window.move_to_foreground()

	if bag.contains_point(local_center):
		contained_in = bag


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
