class_name PetBody
extends Node2D

enum State { IDLE, DRAGGING, THROWN }

const GRAVITY := 2200.0
const BOUNCE_DAMPING := 0.45
const REST_SPEED := 80.0
const FRICTION := 800.0

## Overlap this small is left uncorrected rather than pushed apart every
## single tick. Two bodies resting against each other never quite reach zero
## overlap — gravity keeps re-introducing a sliver of it each frame even once
## their relative velocity is fully damped out — so without a slop, the hard
## positional correction below fires every tick forever, which reads as the
## contact visibly vibrating in place.
const PENETRATION_SLOP := 1.5
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

## When true, a throw that crosses the left/right border of the current
## screen re-emerges from the facing border of the adjacent screen (index
## +/- 1), if such a screen exists. Borders without a neighbour stay solid.
var monitor_border_wrap := false

## Restitution for wall/floor bounces (see [method _process_thrown]), separate
## from the shared [constant BOUNCE_DAMPING] so a per-instance buff (Klippy
## going extra-bouncy off jelly, say) can override just this one body without
## touching every other body's collisions.
var bounce_damping := BOUNCE_DAMPING

## Whether landings, air spin and drag-wheel spin are allowed to turn this
## body's sprite at all. Round bodies (Klippy, food) roll realistically as
## [member roll_radius] converts their linear velocity to spin; an upright
## prop with no floor-contact roll of its own (the wardrobe) would otherwise
## pick up an arbitrary, never-recovered tilt from any residual velocity left
## over when a drag ends. Subclasses that shouldn't roll set this false.
var can_rotate := true

var raw_polygon: PackedVector2Array = PackedVector2Array()
var mask_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	sprite = _resolve_sprite()


## Scene-built bodies get their sprite from the .tscn, where it is named; bodies
## assembled in code may not name theirs, so fall back to the first Sprite2D child
## rather than leaving [member sprite] null for every rotation to trip over.
func _resolve_sprite() -> Sprite2D:
	var named := get_node_or_null(^"Sprite2D") as Sprite2D
	if named != null:
		return named

	for child in get_children():
		if child is Sprite2D:
			return child as Sprite2D

	push_error("%s has no Sprite2D child; it will not rotate or draw." % name)
	return null


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

	## [member raw_polygon] is in the sprite texture's own pixel space, so it
	## must be centered on the texture's size, not the window's — the two only
	## coincide when the window is sized to exactly fit the sprite.
	var center := Vector2(sprite.texture.get_size()) / 2.0
	mask_points.resize(raw_polygon.size())
	for i in raw_polygon.size():
		mask_points[i] = (raw_polygon[i] - center) * sprite.scale


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


## Fires every physics tick while dragging, with the drag velocity just
## computed for this frame. Lets a subclass notice being shaken (Klippy wakes
## from sleep on it; see [method Klippy._on_drag_move]).
func _on_drag_move(_velocity: Vector2, _delta: float) -> void:
	pass


func _on_rotation_changed(angle: float) -> void:
	_update_passthrough_mask(angle)


func _resolve_body_collision(other: PetBody, delta: float) -> void:
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

	var correction := maxf(overlap - PENETRATION_SLOP, 0.0)
	if correction > 0.0:
		window.position += Vector2i(normal * correction * (other.mass / total_mass))
		other_window.position -= Vector2i(normal * correction * (mass / total_mass))

	# Friction along the contact tangent, independent of whether the pair is
	# approaching or separating along the normal this tick — otherwise two
	# bodies just resting against each other (food piled on food in the bag,
	# say) keep gliding past one another indefinitely, since nothing else
	# ever touches their sideways velocity.
	var tangent := Vector2(-normal.y, normal.x)
	var relative_tangential_speed := (velocity - other.velocity).dot(tangent)
	if relative_tangential_speed != 0.0:
		var damped_speed := move_toward(relative_tangential_speed, 0.0, FRICTION * delta)
		var friction_impulse := (damped_speed - relative_tangential_speed) / (1.0 / mass + 1.0 / other.mass)
		velocity += friction_impulse / mass * tangent
		other.velocity -= friction_impulse / other.mass * tangent

	var approach_speed := (velocity - other.velocity).dot(normal)
	if approach_speed >= 0.0:
		return

	# Below REST_SPEED, a full-restitution bounce would just hand back
	# whatever tiny closing speed gravity re-added since last tick — forever,
	# for anything that never settles into IDLE (bagged food piled on other
	# food, say; see [method FoodBody._can_rest]). Cancelling the closing
	# speed instead of reflecting it stops that from ever starting, while a
	# real throw/impact still bounces normally.
	var restitution := 0.0 if -approach_speed <= REST_SPEED else BOUNCE_DAMPING
	var impulse := -(1.0 + restitution) * approach_speed / (1.0 / mass + 1.0 / other.mass)
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
	# _input() only ends the drag if THIS window's own click-through mask lets
	# the release event reach it — miss that (easy with a thin/irregular mask,
	# or another window overlapping at the release point) and the object would
	# otherwise stay glued to the cursor forever, since everything above reads
	# the live mouse position rather than waiting on another event. Checking
	# the actual button state directly is routing-independent, so it can't
	# be missed the same way.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_state(State.THROWN)
		_on_drag_ended()
		return

	var target_pos := Vector2(DisplayServer.mouse_get_position() - drag_offset)
	var old_pos := Vector2(window.position)
	var follow_t := 1.0
	if delta > 0.0:
		var follow_rate := BASE_FOLLOW_RATE / mass
		follow_t = 1.0 - exp(-follow_rate * delta)
	var new_pos := old_pos.lerp(target_pos, follow_t)
	if delta > 0.0:
		velocity = (new_pos - old_pos) / delta
		_on_drag_move(velocity, delta)
	window.position = Vector2i(new_pos)

	if can_rotate and sprite.rotation != drag_spin_target:
		var t := 1.0 - exp(-SPIN_RECOVERY_RATE * delta)
		sprite.rotation = lerp_angle(sprite.rotation, drag_spin_target, t)
		if abs(sprite.rotation - drag_spin_target) < 0.001:
			sprite.rotation = drag_spin_target
		_on_rotation_changed(sprite.rotation)


func _process_idle_base(_delta: float, _window: Window) -> void:
	pass


## Bodies that should never settle into a static [constant State.IDLE] (a food
## item rolling around a bag, say — it has no floor of its own to rest on, so
## going idle the instant gravity zeroes its velocity for a tick just leaves
## it frozen wherever that happened) can override this to keep physics
## running unconditionally instead.
func _can_rest() -> bool:
	return true


func _process_thrown(delta: float, window: Window) -> void:
	if velocity == Vector2.ZERO and _can_rest():
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
		if monitor_border_wrap and _wrap_to_neighbor_screen(-1, window):
			return
		pos.x = min_x
		var impact_speed := velocity.length()
		velocity.x = -velocity.x * bounce_damping
		angular_velocity += -velocity.y / roll_radius
		_on_energetic_bounce(impact_speed)
	elif pos.x > max_x:
		if monitor_border_wrap and _wrap_to_neighbor_screen(1, window):
			return
		pos.x = max_x
		var impact_speed := velocity.length()
		velocity.x = -velocity.x * bounce_damping
		angular_velocity += -velocity.y / roll_radius
		_on_energetic_bounce(impact_speed)

	if pos.y < min_y:
		pos.y = min_y
		var impact_speed := velocity.length()
		velocity.y = -velocity.y * bounce_damping
		angular_velocity += velocity.x / roll_radius
		_on_energetic_bounce(impact_speed)
	elif pos.y >= floor_y:
		pos.y = floor_y
		if abs(velocity.y) > REST_SPEED:
			var impact_speed := velocity.length()
			velocity.y = -velocity.y * bounce_damping
			angular_velocity += velocity.x / roll_radius
			_on_energetic_bounce(impact_speed)
		else:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			angular_velocity = velocity.x / roll_radius
			direct_roll = true

	if not direct_roll:
		angular_velocity *= max(0.0, 1.0 - AIR_SPIN_DAMPING * delta)

	if can_rotate and angular_velocity != 0.0:
		sprite.rotation += angular_velocity * delta
		_on_rotation_changed(sprite.rotation)

	window.position = Vector2i(pos)

	if velocity == Vector2.ZERO and _can_rest():
		_set_state(State.IDLE)


## With [member monitor_border_wrap], re-emerges the pet from the border of
## the screen that physically faces the border he just crossed ([param dir]
## +1 = he crossed this screen's right border, -1 = left). Velocity is
## preserved, so he keeps flying in the same direction on the other side.
func _wrap_to_neighbor_screen(dir: int, window: Window) -> bool:
	var neighbor := neighbor_screen_across(window.current_screen, dir)
	if neighbor == -1:
		return false

	var rect := DisplayServer.screen_get_usable_rect(neighbor)
	var pos := Vector2(window.position)
	var new_x := rect.position.x + 2.0 if dir > 0 else rect.end.x - window.size.x - 2.0
	var new_y := clampf(pos.y, rect.position.y, maxf(rect.end.y - window.size.y, rect.position.y))
	window.position = Vector2i(Vector2(new_x, new_y))
	window.current_screen = neighbor
	return true


## The screen whose edge physically faces [param screen]'s `side` border
## (+1 right, -1 left): a monitor whose opposing edge sits at the same x and
## whose vertical range overlaps. Screen indices don't follow the physical
## layout, so adjacency is measured from real geometry. Returns -1 when
## nothing abuts that border.
static func neighbor_screen_across(screen: int, side: int) -> int:
	var count := DisplayServer.get_screen_count()
	if screen < 0 or screen >= count:
		return -1
	var rect := Rect2(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	for i in count:
		if i == screen:
			continue
		var other := Rect2(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		var vertical_overlap := rect.position.y < other.end.y and other.position.y < rect.end.y
		if not vertical_overlap:
			continue
		if side > 0 and absf(other.position.x - rect.end.x) <= 8.0:
			return i
		if side < 0 and absf(other.end.x - rect.position.x) <= 8.0:
			return i
	return -1
