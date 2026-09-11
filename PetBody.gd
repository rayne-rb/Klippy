class_name PetBody
extends Node2D

enum State { IDLE, DRAGGING, THROWN }

const GRAVITY := 2200.0
const BOUNCE_DAMPING := 0.45
const REST_SPEED := 80.0
const FRICTION := 800.0
const AIR_SPIN_DAMPING := 0.1
const SPIN_RECOVERY_RATE := 10.0
const BASE_FOLLOW_RATE := 25.0
const DRAG_SPIN_STEP := PI / 6.0

var sprite: Sprite2D
var state := State.IDLE
var drag_offset := Vector2i.ZERO
var velocity := Vector2.ZERO
var angular_velocity := 0.0
var drag_spin_target := 0.0

var mass := 1.0
var roll_radius := 90.0

var raw_polygon: PackedVector2Array = PackedVector2Array()
var mask_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	sprite = $Sprite2D


func _build_click_through_mask() -> void:
	var texture := sprite.texture
	if texture == null:
		return

	var image := texture.get_image()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.1)

	var polygons := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 2.0)
	if polygons.is_empty():
		return

	var largest: PackedVector2Array = polygons[0]
	for polygon in polygons:
		if polygon.size() > largest.size():
			largest = polygon

	raw_polygon = largest
	_rebuild_mask_points()
	_update_passthrough_mask(0.0)


func _rebuild_mask_points() -> void:
	if raw_polygon.is_empty():
		return

	var center := Vector2(get_window().size) / 2.0
	mask_points.resize(raw_polygon.size())
	for i in raw_polygon.size():
		mask_points[i] = raw_polygon[i] * sprite.scale - center


func _rotated_mask_points(angle: float) -> PackedVector2Array:
	var center := Vector2(get_window().size) / 2.0
	var region := PackedVector2Array()
	region.resize(mask_points.size())
	for i in mask_points.size():
		region[i] = mask_points[i].rotated(angle) + center
	return region


func _update_passthrough_mask(angle: float) -> void:
	if mask_points.is_empty():
		return

	DisplayServer.window_set_mouse_passthrough(_rotated_mask_points(angle), get_window().get_window_id())


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	_on_state_exit(state)
	state = new_state
	_on_state_enter(state)


func _on_state_enter(_new_state: State) -> void:
	pass


func _on_state_exit(_old_state: State) -> void:
	pass


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			velocity = Vector2.ZERO
			angular_velocity = 0.0
			drag_spin_target = sprite.rotation
			drag_offset = DisplayServer.mouse_get_position() - get_window().position
			_set_state(State.DRAGGING)
			_on_drag_started(event)
		elif state == State.DRAGGING:
			_set_state(State.THROWN)
			_on_drag_ended()
	elif event is InputEventMouseButton and event.pressed and state == State.DRAGGING:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			drag_spin_target = wrapf(drag_spin_target + DRAG_SPIN_STEP, -PI, PI)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			drag_spin_target = wrapf(drag_spin_target - DRAG_SPIN_STEP, -PI, PI)


func _on_drag_started(_event: InputEventMouseButton) -> void:
	pass


func _on_drag_ended() -> void:
	pass


func _on_rotation_changed(angle: float) -> void:
	_update_passthrough_mask(angle)


func _resolve_body_collision(other: PetBody) -> void:
	if state == State.DRAGGING or other.state == State.DRAGGING:
		return

	var window := get_window()
	var other_window := other.get_window()
	var center := Vector2(window.position) + Vector2(window.size) / 2.0
	var other_center := Vector2(other_window.position) + Vector2(other_window.size) / 2.0

	var offset := center - other_center
	var distance := offset.length()
	var min_distance := roll_radius + other.roll_radius
	if distance >= min_distance or distance <= 0.0:
		return

	var normal := offset / distance
	var overlap := min_distance - distance
	var total_mass := mass + other.mass

	window.position += Vector2i(normal * overlap * (other.mass / total_mass))
	other_window.position -= Vector2i(normal * overlap * (mass / total_mass))

	var approach_speed := (velocity - other.velocity).dot(normal)
	if approach_speed >= 0.0:
		return

	var impulse := -(1.0 + BOUNCE_DAMPING) * approach_speed / (1.0 / mass + 1.0 / other.mass)
	var impulse_vector := impulse * normal

	velocity += impulse_vector / mass
	other.velocity -= impulse_vector / other.mass

	if state != State.THROWN:
		_set_state(State.THROWN)
	if other.state != State.THROWN:
		other._set_state(State.THROWN)


func _on_energetic_bounce(_impact_speed: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	var window := get_window()

	if state == State.DRAGGING:
		_process_dragging(delta, window)
		return

	_run_state_physics(delta, window)


func _run_state_physics(delta: float, window: Window) -> void:
	match state:
		State.THROWN:
			_process_thrown(delta, window)
		State.IDLE:
			_process_idle_base(delta, window)


func _process_dragging(delta: float, window: Window) -> void:
	var target_pos := Vector2(DisplayServer.mouse_get_position() - drag_offset)
	var old_pos := Vector2(window.position)
	var follow_t := 1.0
	if delta > 0.0:
		var follow_rate := BASE_FOLLOW_RATE / mass
		follow_t = 1.0 - exp(-follow_rate * delta)
	var new_pos := old_pos.lerp(target_pos, follow_t)
	if delta > 0.0:
		velocity = (new_pos - old_pos) / delta
	window.position = Vector2i(new_pos)

	if sprite.rotation != drag_spin_target:
		var t := 1.0 - exp(-SPIN_RECOVERY_RATE * delta)
		sprite.rotation = lerp_angle(sprite.rotation, drag_spin_target, t)
		if abs(sprite.rotation - drag_spin_target) < 0.001:
			sprite.rotation = drag_spin_target
		_on_rotation_changed(sprite.rotation)


func _process_idle_base(_delta: float, _window: Window) -> void:
	pass


func _process_thrown(delta: float, window: Window) -> void:
	if velocity == Vector2.ZERO:
		_set_state(State.IDLE)
		return

	velocity.y += GRAVITY * delta

	var bounds := DisplayServer.screen_get_usable_rect(window.current_screen)
	var size := Vector2(window.size)
	var pos := Vector2(window.position) + velocity * delta

	var min_x := float(bounds.position.x)
	var max_x := bounds.position.x + bounds.size.x - size.x
	var min_y := float(bounds.position.y)
	var floor_y := bounds.position.y + bounds.size.y - size.y

	var direct_roll := false

	if pos.x < min_x:
		pos.x = min_x
		var impact_speed := velocity.length()
		velocity.x = -velocity.x * BOUNCE_DAMPING
		angular_velocity += -velocity.y / roll_radius
		_on_energetic_bounce(impact_speed)
	elif pos.x > max_x:
		pos.x = max_x
		var impact_speed := velocity.length()
		velocity.x = -velocity.x * BOUNCE_DAMPING
		angular_velocity += -velocity.y / roll_radius
		_on_energetic_bounce(impact_speed)

	if pos.y < min_y:
		pos.y = min_y
		var impact_speed := velocity.length()
		velocity.y = -velocity.y * BOUNCE_DAMPING
		angular_velocity += velocity.x / roll_radius
		_on_energetic_bounce(impact_speed)
	elif pos.y >= floor_y:
		pos.y = floor_y
		if abs(velocity.y) > REST_SPEED:
			var impact_speed := velocity.length()
			velocity.y = -velocity.y * BOUNCE_DAMPING
			angular_velocity += velocity.x / roll_radius
			_on_energetic_bounce(impact_speed)
		else:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			angular_velocity = velocity.x / roll_radius
			direct_roll = true

	if not direct_roll:
		angular_velocity *= max(0.0, 1.0 - AIR_SPIN_DAMPING * delta)

	if angular_velocity != 0.0:
		sprite.rotation += angular_velocity * delta
		_on_rotation_changed(sprite.rotation)

	window.position = Vector2i(pos)

	if velocity == Vector2.ZERO:
		_set_state(State.IDLE)
