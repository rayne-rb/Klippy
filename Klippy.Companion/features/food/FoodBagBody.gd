class_name FoodBagBody
extends PetBody

signal grabbed

const WALL_TEXTURE: Texture2D = preload("res://assets/KlippyFoodBag.png")
const BACK_TEXTURE: Texture2D = preload("res://assets/KlippyFoodBagBack.png")

## Rendered height of the bag art on screen; width follows from the texture's
## own aspect ratio.
const TARGET_HEIGHT := 300.0

## Extra room around the art so a rotated corner has space to swing through
## before it hits the window edge and gets clipped. Needs to cover half the
## art's rotated diagonal minus half its tallest side (~43px at the current
## TARGET_HEIGHT) — this doesn't auto-scale with that constant, so bump it
## along with any future size change.
const WINDOW_MARGIN := 55

var klippy: Klippy

## The background art's silhouette, in the wall texture's own (unscaled,
## unrotated) pixel space — same canvas as [member raw_polygon], since both
## images share one aligned canvas. This is the zone that marks food as
## "stored".
var interior_polygon: PackedVector2Array

## This window's position as of the start of the current physics tick, before
## dragging/throw physics moves it — [method FoodBody._check_bag] diffs
## against this to carry contained food along with the bag instead of
## leaving it behind whenever the bag itself is picked up and moved.
var tick_start_position: Vector2i


func _ready() -> void:
	var wall_sprite := Sprite2D.new()
	wall_sprite.name = "Sprite2D"
	wall_sprite.texture = WALL_TEXTURE
	wall_sprite.scale = Vector2.ONE * (TARGET_HEIGHT / WALL_TEXTURE.get_size().y)
	add_child(wall_sprite)

	# A child of the wall sprite so it shares its rotation/scale for free;
	# [member Node2D.show_behind_parent] keeps it drawn underneath despite
	# being later in the tree.
	var background_sprite := Sprite2D.new()
	background_sprite.texture = BACK_TEXTURE
	background_sprite.show_behind_parent = true
	wall_sprite.add_child(background_sprite)

	super._ready()
	# The wall art is an open outline (not a closed ring), so it traces as a
	# single simple polygon with no hole to lose — the inherited sprite-alpha
	# mask already covers only the ink line, nothing more to do here.
	_build_click_through_mask()
	_build_interior_polygon()


func _build_interior_polygon() -> void:
	var image := BACK_TEXTURE.get_image()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.1)
	var polygons := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 2.0)
	if polygons.is_empty():
		return

	var largest: PackedVector2Array = polygons[0]
	for polygon in polygons:
		if polygon.size() > largest.size():
			largest = polygon
	interior_polygon = largest


func _physics_process(delta: float) -> void:
	tick_start_position = get_window().position
	super._physics_process(delta)
	if klippy and get_window().visible:
		_resolve_body_collision(klippy)


func movement_delta_this_tick() -> Vector2i:
	return get_window().position - tick_start_position


func _on_drag_started(_event: InputEventMouseButton) -> void:
	grabbed.emit()


## [param local_point] is in this window's local pixel space (top-left
## origin), same as [method PetBody._rotated_mask_points]. True when it falls
## inside the background art's silhouette.
func contains_point(local_point: Vector2) -> bool:
	if interior_polygon.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(local_point, _rotated_interior_points())


func _rotated_interior_points() -> PackedVector2Array:
	var center := Vector2(BACK_TEXTURE.get_size()) / 2.0
	var window_center := Vector2(get_window().size) / 2.0
	var angle := sprite.rotation
	var points := PackedVector2Array()
	points.resize(interior_polygon.size())
	for i in interior_polygon.size():
		points[i] = ((interior_polygon[i] - center) * sprite.scale).rotated(angle) + window_center
	return points


## Bounces [param food] off the wall art's traced outline — the same
## closest-point-on-segment approach [method PetBody._resolve_body_collision]
## uses for circle-circle, just against a polyline instead of another circle.
## This is what lets the bag actually hold food in rather than just marking it
## stored: an item has to physically be unable to roll out through the wall.
##
## [param prev_local_center] is where [param food] was (in this window's local
## space) before it moved this tick. A simple "is it close to the wall right
## now" check misses anything moving fast enough to land clean on the far
## side of the wall's thin ink line in a single tick — always possible now
## that food never rests (see [method FoodBody._can_rest]), since gravity
## keeps building speed for as long as nothing catches it — so this first
## checks whether the food's whole path this tick crossed the wall at all.
func resolve_food_wall_collision(food: FoodBody, prev_local_center: Vector2) -> void:
	if raw_polygon.is_empty():
		return

	var wall := _rotated_mask_points(sprite.rotation)
	var food_window := food.get_window()
	var local_center := Vector2(food_window.position - get_window().position) + Vector2(food_window.size) / 2.0
	var edge_count := wall.size()

	if prev_local_center != local_center:
		for i in edge_count:
			var a := wall[i]
			var b := wall[(i + 1) % edge_count]
			var crossing = Geometry2D.segment_intersects_segment(prev_local_center, local_center, a, b)
			if crossing == null:
				continue

			var edge_dir := (b - a).normalized()
			var normal := Vector2(-edge_dir.y, edge_dir.x)
			if normal.dot(local_center - prev_local_center) > 0.0:
				normal = -normal

			var corrected := (crossing as Vector2) + normal * food.roll_radius
			food_window.position = Vector2i(corrected - Vector2(food_window.size) / 2.0) + get_window().position
			_bounce_food(food, normal)
			return

	var closest_dist := INF
	var closest_point := Vector2.ZERO
	for i in edge_count:
		var point := Geometry2D.get_closest_point_to_segment(local_center, wall[i], wall[(i + 1) % edge_count])
		var d := local_center.distance_to(point)
		if d < closest_dist:
			closest_dist = d
			closest_point = point

	if closest_dist >= food.roll_radius or closest_dist <= 0.0:
		return

	var normal := (local_center - closest_point) / closest_dist
	var overlap := food.roll_radius - closest_dist
	food_window.position += Vector2i(normal * overlap)
	_bounce_food(food, normal)


func _bounce_food(food: FoodBody, normal: Vector2) -> void:
	var approach_speed := food.velocity.dot(-normal)
	if approach_speed <= 0.0:
		return

	food.velocity += (1.0 + BOUNCE_DAMPING) * approach_speed * normal
	if food.state != State.THROWN:
		food._set_state(State.THROWN)
