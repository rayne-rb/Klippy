class_name FoodBagBody
extends PetBody

signal grabbed

const BAG_WINDOW_SIZE := 110
const CORNER_RADIUS := 16.0
const WALL_THICKNESS := 14

## Extra room around the drawn bag so a rotated corner has space to swing
## through before it hits the window edge and gets clipped.
const WINDOW_MARGIN := 24

var klippy: Klippy


func _ready() -> void:
	super._ready()
	_build_click_through_mask()


## The bag's texture is a hollow frame, so the base [method PetBody._build_click_through_mask]
## can't be used as-is: [method BitMap.opaque_to_polygons] only ever returns the
## outer silhouette for a shape with a hole, which would make the whole square
## (including the hollow middle) block clicks. Build the rim as an explicit
## outer-ring polygon instead, bridged to the inner hole boundary so the hollow
## center stays click-through.
func _build_click_through_mask() -> void:
	var outer := _rounded_rect_loop(BAG_WINDOW_SIZE, CORNER_RADIUS)

	var inner_size := BAG_WINDOW_SIZE - WALL_THICKNESS * 2
	var inner_radius: float = max(CORNER_RADIUS - WALL_THICKNESS, 0.0)
	var inner := _rounded_rect_loop(inner_size, inner_radius)
	for i in inner.size():
		inner[i] += Vector2.ONE * WALL_THICKNESS

	raw_polygon = _bridge_loops(outer, inner)
	_rebuild_mask_points()
	_update_passthrough_mask(0.0)


static func _rounded_rect_loop(size: float, radius: float, segments_per_corner: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [
		Vector2(size - radius, radius),
		Vector2(size - radius, size - radius),
		Vector2(radius, size - radius),
		Vector2(radius, radius),
	]
	for c in 4:
		var center: Vector2 = centers[c]
		var start_angle := -PI / 2.0 + c * (PI / 2.0)
		for i in segments_per_corner + 1:
			var angle := start_angle + (PI / 2.0) * (float(i) / segments_per_corner)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Splices [param inner] into [param outer] as a single simple polygon (the
## "keyhole" trick): walk out to the nearest point on the hole, trace all the
## way around it, then walk back — so the hole is excluded from the shape
## without needing a fill rule that understands multiple contours.
static func _bridge_loops(outer: PackedVector2Array, inner: PackedVector2Array) -> PackedVector2Array:
	var outer_index := 0
	var inner_index := 0
	var best_dist := INF
	for oi in outer.size():
		for ii in inner.size():
			var d := outer[oi].distance_squared_to(inner[ii])
			if d < best_dist:
				best_dist = d
				outer_index = oi
				inner_index = ii

	var bridged := PackedVector2Array()
	for i in range(outer_index + 1):
		bridged.append(outer[i])
	for i in range(inner.size() + 1):
		bridged.append(inner[(inner_index + i) % inner.size()])
	bridged.append(outer[outer_index])
	for i in range(outer_index + 1, outer.size()):
		bridged.append(outer[i])
	return bridged


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if klippy:
		_resolve_body_collision(klippy)


func _on_drag_started(_event: InputEventMouseButton) -> void:
	grabbed.emit()


static func make_texture() -> ImageTexture:
	var size := BAG_WINDOW_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var wall_color := Color(0.55, 0.35, 0.17)
	var rim_color := Color(0.42, 0.26, 0.12)
	var rim_height := size * 0.18
	var inner_size := size - WALL_THICKNESS * 2
	var inner_radius: float = max(CORNER_RADIUS - WALL_THICKNESS, 0.0)
	for y in size:
		for x in size:
			if not _inside_rounded_rect(x, y, size, size, CORNER_RADIUS):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if _inside_rounded_rect(x - WALL_THICKNESS, y - WALL_THICKNESS, inner_size, inner_size, inner_radius):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			image.set_pixel(x, y, rim_color if y < rim_height else wall_color)
	return ImageTexture.create_from_image(image)


static func _inside_rounded_rect(x: int, y: int, w: int, h: int, r: float) -> bool:
	var px := x + 0.5
	var py := y + 0.5
	var cx: float = clamp(px, r, float(w) - r)
	var cy: float = clamp(py, r, float(h) - r)
	return Vector2(px, py).distance_to(Vector2(cx, cy)) <= r
