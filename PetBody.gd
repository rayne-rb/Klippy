class_name PetBody
extends Node2D

const GRAVITY := 2200.0
const BOUNCE_DAMPING := 0.45
const REST_SPEED := 80.0
const FRICTION := 800.0
const AIR_SPIN_DAMPING := 0.1
const SPIN_RECOVERY_RATE := 10.0
const BASE_FOLLOW_RATE := 25.0

var sprite: Sprite2D
var dragging := false
var drag_offset := Vector2i.ZERO
var velocity := Vector2.ZERO
var angular_velocity := 0.0

var mass := 1.0
var roll_radius := 90.0


func _ready() -> void:
	sprite = $Sprite2D


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			velocity = Vector2.ZERO
			angular_velocity = 0.0
			drag_offset = DisplayServer.mouse_get_position() - get_window().position
			_on_drag_started(event)
		else:
			dragging = false
			_on_drag_ended()


func _on_drag_started(_event: InputEventMouseButton) -> void:
	pass


func _on_drag_ended() -> void:
	pass


func _on_rotation_changed(_angle: float) -> void:
	pass


func _on_energetic_bounce(_impact_speed: float) -> void:
	pass


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
			_on_rotation_changed(sprite.rotation)

		return

	_process_non_dragging(delta, window)


func _process_non_dragging(delta: float, window: Window) -> void:
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
