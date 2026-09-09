extends Node2D

const GRAVITY := 2200.0
const BOUNCE_DAMPING := 0.45
const REST_SPEED := 80.0
const FRICTION := 800.0
const ROLL_RADIUS := 90.0
const AIR_SPIN_DAMPING := 0.1
const SPIN_RECOVERY_RATE := 10.0

var sprite: Sprite2D
var mask_points: PackedVector2Array = PackedVector2Array()

var dragging := false
var drag_offset := Vector2i.ZERO
var last_mouse_pos := Vector2i.ZERO
var velocity := Vector2.ZERO
var angular_velocity := 0.0
var show_hitbox := false


func _ready() -> void:
	sprite = $Sprite2D
	_build_click_through_mask()


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

	var center := Vector2(get_window().size) / 2.0
	mask_points.resize(largest.size())
	for i in largest.size():
		mask_points[i] = largest[i] * sprite.scale - center

	_update_passthrough_mask(0.0)


func _update_passthrough_mask(angle: float) -> void:
	if mask_points.is_empty():
		return

	var center := Vector2(get_window().size) / 2.0
	var region := PackedVector2Array()
	region.resize(mask_points.size())
	for i in mask_points.size():
		region[i] = mask_points[i].rotated(angle) + center

	DisplayServer.window_set_mouse_passthrough(region, 0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			velocity = Vector2.ZERO
			angular_velocity = 0.0
			last_mouse_pos = DisplayServer.mouse_get_position()
			drag_offset = last_mouse_pos - get_window().position
		else:
			dragging = false
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		show_hitbox = not show_hitbox
		queue_redraw()


func _draw() -> void:
	if not show_hitbox or mask_points.is_empty():
		return

	var points := PackedVector2Array()
	points.resize(mask_points.size() + 1)
	for i in mask_points.size():
		points[i] = mask_points[i].rotated(sprite.rotation)
	points[mask_points.size()] = points[0]

	draw_polyline(points, Color.RED, 2.0)


func _physics_process(delta: float) -> void:
	var window := get_window()

	if dragging:
		var mouse_pos := DisplayServer.mouse_get_position()
		window.position = mouse_pos - drag_offset
		if delta > 0.0:
			velocity = Vector2(mouse_pos - last_mouse_pos) / delta
		last_mouse_pos = mouse_pos

		if sprite.rotation != 0.0:
			var t := 1.0 - exp(-SPIN_RECOVERY_RATE * delta)
			sprite.rotation = lerp_angle(sprite.rotation, 0.0, t)
			if abs(sprite.rotation) < 0.001:
				sprite.rotation = 0.0
			_update_passthrough_mask(sprite.rotation)
			if show_hitbox:
				queue_redraw()

		return

	if velocity == Vector2.ZERO:
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
		velocity.x = -velocity.x * BOUNCE_DAMPING
		angular_velocity += -velocity.y / ROLL_RADIUS
	elif pos.x > max_x:
		pos.x = max_x
		velocity.x = -velocity.x * BOUNCE_DAMPING
		angular_velocity += -velocity.y / ROLL_RADIUS

	if pos.y < min_y:
		pos.y = min_y
		velocity.y = -velocity.y * BOUNCE_DAMPING
		angular_velocity += velocity.x / ROLL_RADIUS
	elif pos.y >= floor_y:
		pos.y = floor_y
		if abs(velocity.y) > REST_SPEED:
			velocity.y = -velocity.y * BOUNCE_DAMPING
			angular_velocity += velocity.x / ROLL_RADIUS
		else:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			angular_velocity = velocity.x / ROLL_RADIUS
			direct_roll = true

	if not direct_roll:
		angular_velocity *= max(0.0, 1.0 - AIR_SPIN_DAMPING * delta)

	if angular_velocity != 0.0:
		sprite.rotation += angular_velocity * delta
		_update_passthrough_mask(sprite.rotation)
		if show_hitbox:
			queue_redraw()

	window.position = Vector2i(pos)
