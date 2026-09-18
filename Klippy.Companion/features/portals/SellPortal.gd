class_name SellPortal
extends Window

## The desktop end of "list this on the market": drag a consumable item onto
## this vortex and it leaves for the market, once a price is set. Unlike
## [ConsumablePortal]'s one-shot pop, this persists on the desktop — summoned
## and banished from the context menu, like [TravelPortal] — since there is no
## way to know in advance which item, if any, is about to be dragged over.
##
## Detection is each item's own job (see [member ConsumableBody.sell_portal]
## and [method ConsumableBody._check_market_sell]), the same way feeding checks
## an item's own distance to Klippy rather than Klippy watching every item.

const SIZE := 160
const SPIN_SPEED := 1.6
const PULSE_SPEED := 3.0
const CORE := Color("b8860b")
const RIM := Color("ffd66b")

static var _texture: ImageTexture

var _sprite: Sprite2D
var _time := 0.0
var _dragging := false
var _drag_offset := Vector2()


func _init() -> void:
	borderless = true
	transparent = true
	always_on_top = true
	unfocusable = true
	size = Vector2i(SIZE, SIZE)
	content_scale_size = Vector2i(SIZE, SIZE)


func _ready() -> void:
	if _texture == null:
		_texture = _make_texture()

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.position = Vector2(SIZE, SIZE) / 2.0
	add_child(_sprite)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging:
			_dragging = true
			_drag_offset = Vector2(DisplayServer.mouse_get_position()) - Vector2(position)
		elif not event.pressed:
			_dragging = false


func _process(delta: float) -> void:
	_time += delta
	_sprite.rotation += delta * SPIN_SPEED
	_sprite.scale = Vector2.ONE * (1.0 + sin(_time * PULSE_SPEED) * 0.05)

	if _dragging:
		position = Vector2i(_clamped_to_desktop(
			Vector2(DisplayServer.mouse_get_position()) - _drag_offset))


## Positions the portal's center at [param center] — global desktop
## coordinates, so any monitor will do.
func place(center: Vector2i) -> void:
	position = center - Vector2i(SIZE, SIZE) / 2


func center() -> Vector2:
	return Vector2(position) + Vector2(SIZE, SIZE) / 2.0


func radius() -> float:
	return SIZE / 2.0


## Never fully off-desktop: the vortex is clamped inside the union of every
## connected screen while dragged.
func _clamped_to_desktop(pos: Vector2) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in DisplayServer.get_screen_count():
		var rect := DisplayServer.screen_get_usable_rect(i)
		lo = lo.min(Vector2(rect.position))
		hi = hi.max(Vector2(rect.end))
	return pos.clamp(lo, hi - Vector2(SIZE, SIZE))


## The same swirl [ConsumablePortal] and [TravelPortal] wear, drawn in this
## portal's own colours.
static func _make_texture() -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE, SIZE) / 2.0
	var radius := SIZE / 2.0

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var dist := point.distance_to(center)
			if dist > radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var t := dist / radius
			var angle := (point - center).angle()
			var swirl := sin(angle * 3.0 + t * 10.0) * 0.5 + 0.5
			var color := CORE.lerp(RIM, swirl)
			color.a = 1.0 - pow(t, 3.0)
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)
