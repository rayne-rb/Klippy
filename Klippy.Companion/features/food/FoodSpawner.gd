class_name FoodSpawner
extends Node

## Owns everything about food items: the windows they live in, the pool they are
## recycled through, and the texture they are drawn with.
##
## Pulled out of Klippy so the pet only has to ask for a snack and be told whether
## one is available; how food is made and reclaimed is nobody else's business.

## Emitted when spawning becomes possible or impossible, so a menu can enable or
## disable its Feed entry without polling.
signal availability_changed

const WINDOW_SIZE := 60
const MASS := 0.3
const MAX_ITEMS := 8
const SPAWN_GAP := 10

var _stats: PetStats
var _anchor: PetBody
var _active: Array[Window] = []
var _pool: Array[Window] = []


## [param anchor] is the body food should appear beside and be eaten at.
func setup(stats: PetStats, anchor: PetBody) -> void:
	_stats = stats
	_anchor = anchor


func active_count() -> int:
	return _active.size()


func can_spawn() -> bool:
	return _stats != null and _stats.feeding_enabled and _active.size() < MAX_ITEMS


## Drops one food item next to the anchor. Returns false when there is no room.
func spawn(food_type: String = FoodCatalog.APPLE) -> bool:
	if _active.size() >= MAX_ITEMS:
		return false

	var window: Window
	var body: FoodBody

	if not _pool.is_empty():
		window = _pool.pop_back()
		body = window.get_child(0) as FoodBody
	else:
		window = _build_window()
		body = window.get_child(0) as FoodBody
		body.consumed.connect(_on_consumed.bind(window))

	body.mass = MASS
	body.stats = _stats
	body.klippy = _anchor
	# A pooled window's sprite still carries whatever food it last held, so this
	# has to be re-applied every spawn rather than only when the window is built.
	body.apply_food_type(food_type)
	body.velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.drag_spin_target = 0.0
	body.state = PetBody.State.IDLE
	body.sprite.rotation = 0.0
	body.set_physics_process(true)

	var anchor_window := _anchor.get_window()
	window.position = anchor_window.position + Vector2i(anchor_window.size.x + SPAWN_GAP, 0)
	window.show()

	_active.append(window)
	availability_changed.emit()
	return true


func _build_window() -> Window:
	var window := Window.new()
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	window.unfocusable = true

	var window_size := Vector2i(WINDOW_SIZE, WINDOW_SIZE)
	window.size = window_size
	window.content_scale_size = window_size

	var body := FoodBody.new()
	body.position = Vector2(window_size) / 2.0
	body.roll_radius = WINDOW_SIZE * 0.45

	var sprite := Sprite2D.new()
	# Godot names an unnamed code-added child @Sprite2D@N; say it plainly so the
	# body finds it the same way a scene-built one does. Texture and scale are
	# set right after by the [method spawn] call that triggered this build.
	sprite.name = "Sprite2D"
	body.add_child(sprite)
	window.add_child(body)

	add_child(window)
	return window


func _on_consumed(window: Window) -> void:
	var body := window.get_child(0) as FoodBody
	body.set_physics_process(false)
	window.hide()
	_active.erase(window)

	# Reuse rather than free: spawning is a menu click away and rebuilding the
	# window plus its texture every time was the expensive part.
	if _pool.size() < MAX_ITEMS:
		_pool.append(window)
	else:
		window.queue_free()

	availability_changed.emit()
