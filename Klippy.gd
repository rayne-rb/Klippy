extends Node2D

const GRAVITY := 2200.0
const BOUNCE_DAMPING := 0.45
const REST_SPEED := 80.0
const FRICTION := 800.0
const AIR_SPIN_DAMPING := 0.1
const SPIN_RECOVERY_RATE := 10.0

const TEXTURE_SIZE := 400.0
const SIZE_STEPS := [100, 200, 300, 400]
const CLOSE_ID := 0
const DVD_ID := 1
const SETTINGS_ID := 2

const REFERENCE_SIZE := 200.0
const BASE_FOLLOW_RATE := 25.0
const DVD_SPEED := 220.0

var sprite: Sprite2D
var context_menu: PopupMenu
var resize_menu: PopupMenu
var settings_window: Window

var dvd_mode := false

var raw_polygon: PackedVector2Array = PackedVector2Array()
var mask_points: PackedVector2Array = PackedVector2Array()

var dragging := false
var drag_offset := Vector2i.ZERO
var velocity := Vector2.ZERO
var angular_velocity := 0.0
var show_hitbox := false

var current_size := 200
var roll_radius := 90.0
var mass := 1.0


func _ready() -> void:
	sprite = $Sprite2D
	_build_click_through_mask()
	_recompute_physical_properties()

	resize_menu = PopupMenu.new()
	for i in SIZE_STEPS.size():
		resize_menu.add_item("%d x %d" % [SIZE_STEPS[i], SIZE_STEPS[i]], i)
	resize_menu.id_pressed.connect(_on_resize_option_pressed)

	context_menu = PopupMenu.new()
	context_menu.add_submenu_node_item("Resize", resize_menu)
	context_menu.add_item("DVD", DVD_ID)
	context_menu.add_item("Settings", SETTINGS_ID)
	context_menu.add_item("Close", CLOSE_ID)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(context_menu)

	settings_window = Window.new()
	settings_window.title = "Settings"
	settings_window.size = Vector2i(300, 200)
	settings_window.close_requested.connect(settings_window.hide)
	add_child(settings_window)
	settings_window.hide()


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


func _update_passthrough_mask(angle: float) -> void:
	if mask_points.is_empty():
		return

	var center := Vector2(get_window().size) / 2.0
	var region := PackedVector2Array()
	region.resize(mask_points.size())
	for i in mask_points.size():
		region[i] = mask_points[i].rotated(angle) + center

	DisplayServer.window_set_mouse_passthrough(region, 0)


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		CLOSE_ID:
			get_tree().quit()
		SETTINGS_ID:
			settings_window.popup_centered()
		DVD_ID:
			_toggle_dvd_mode()


func _toggle_dvd_mode() -> void:
	dvd_mode = not dvd_mode
	angular_velocity = 0.0
	if dvd_mode:
		velocity = Vector2(DVD_SPEED, 0.0).rotated(randf_range(0.0, TAU))
	else:
		velocity = Vector2.ZERO


func _on_resize_option_pressed(id: int) -> void:
	_apply_size(SIZE_STEPS[id])


func _apply_size(new_size: int) -> void:
	var window := get_window()
	var old_center := Vector2(window.position) + Vector2(window.size) / 2.0
	var new_size_v := Vector2i(new_size, new_size)

	window.content_scale_size = new_size_v
	window.size = new_size_v
	window.position = Vector2i(old_center - Vector2(new_size_v) / 2.0)

	sprite.scale = Vector2.ONE * (new_size / TEXTURE_SIZE)
	position = Vector2(new_size_v) / 2.0
	current_size = new_size
	_recompute_physical_properties()

	_rebuild_mask_points()
	_update_passthrough_mask(sprite.rotation)
	if show_hitbox:
		queue_redraw()


func _recompute_physical_properties() -> void:
	roll_radius = current_size * 0.45
	mass = pow(current_size / REFERENCE_SIZE, 2.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			dvd_mode = false
			velocity = Vector2.ZERO
			angular_velocity = 0.0
			drag_offset = DisplayServer.mouse_get_position() - get_window().position
		else:
			dragging = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		context_menu.position = DisplayServer.mouse_get_position()
		context_menu.popup()
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

		if sprite.rotation != 0.0:
			var t := 1.0 - exp(-SPIN_RECOVERY_RATE * delta)
			sprite.rotation = lerp_angle(sprite.rotation, 0.0, t)
			if abs(sprite.rotation) < 0.001:
				sprite.rotation = 0.0
			_update_passthrough_mask(sprite.rotation)
			if show_hitbox:
				queue_redraw()

		return

	if dvd_mode:
		_process_dvd(delta, window)
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
		angular_velocity += -velocity.y / roll_radius
	elif pos.x > max_x:
		pos.x = max_x
		velocity.x = -velocity.x * BOUNCE_DAMPING
		angular_velocity += -velocity.y / roll_radius

	if pos.y < min_y:
		pos.y = min_y
		velocity.y = -velocity.y * BOUNCE_DAMPING
		angular_velocity += velocity.x / roll_radius
	elif pos.y >= floor_y:
		pos.y = floor_y
		if abs(velocity.y) > REST_SPEED:
			velocity.y = -velocity.y * BOUNCE_DAMPING
			angular_velocity += velocity.x / roll_radius
		else:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			angular_velocity = velocity.x / roll_radius
			direct_roll = true

	if not direct_roll:
		angular_velocity *= max(0.0, 1.0 - AIR_SPIN_DAMPING * delta)

	if angular_velocity != 0.0:
		sprite.rotation += angular_velocity * delta
		_update_passthrough_mask(sprite.rotation)
		if show_hitbox:
			queue_redraw()

	window.position = Vector2i(pos)


func _process_dvd(delta: float, window: Window) -> void:
	var bounds := DisplayServer.screen_get_usable_rect(window.current_screen)
	var size := Vector2(window.size)
	var pos := Vector2(window.position) + velocity * delta

	var min_x := float(bounds.position.x)
	var max_x := bounds.position.x + bounds.size.x - size.x
	var min_y := float(bounds.position.y)
	var max_y := bounds.position.y + bounds.size.y - size.y

	if pos.x < min_x:
		pos.x = min_x
		velocity.x = -velocity.x
	elif pos.x > max_x:
		pos.x = max_x
		velocity.x = -velocity.x

	if pos.y < min_y:
		pos.y = min_y
		velocity.y = -velocity.y
	elif pos.y > max_y:
		pos.y = max_y
		velocity.y = -velocity.y

	window.position = Vector2i(pos)
