class_name TravelPortal
extends Window

## One end of a portal chain that lives on the desktop until banished.
## Draggable: grab the vortex and pull it anywhere, any monitor. It watches
## for the pet to fly into it — through [member probe], supplied by the pet
## itself — and reports the entry, so the owner can teleport him out of the
## next portal in the chain, which may sit on a different monitor.

signal entered(entry_velocity: Vector2, rising: bool)

## Right mouse button went down on this portal. The travel pair ignores it; the
## friend portal uses it for its own little menu (call back, close), since the
## pet's context menu is unreachable while he is away through this portal.
signal right_clicked

const SIZE := 160
const SPIN_SPEED := 1.6
const PULSE_SPEED := 3.0
## While the pet loiters inside the vortex (an infinite dropper), the entry
## re-fires at this interval instead of only on the crossing frame. Must stay
## shorter than the time it takes to fall through the vortex at exit speed,
## or the dropper loop drops out of the bottom.
const LINGER_REFIRE := 0.1

## Swirl colours per portal kind: kind -> [core, rim]. Green is the friend
## portal — the one that opens onto another user's monitor (see the visit slice).
const PALETTE := {
	"blue": [Color("1c46c9"), Color("55c8ff")],
	"red": [Color("b3122f"), Color("ff8a55")],
	"green": [Color("0b6e3f"), Color("7dffb0")],
}

static var _textures := {}

## Supplied by the pet: returns {thrown, center, radius, velocity} for the
## pet's current state, so the portal can spot entries without knowing
## anything about how the pet moves.
var probe: Callable

var _sprite: Sprite2D
var _kind: String
var _time := 0.0
var _was_inside := false
var _last_fire := 0.0
var _had_pet := false
var _last_pet_center := Vector2.ZERO
var _dragging := false
var _drag_offset := Vector2()


func _init(kind: String) -> void:
	_kind = kind
	borderless = true
	transparent = true
	always_on_top = true
	unfocusable = true
	size = Vector2i(SIZE, SIZE)
	content_scale_size = Vector2i(SIZE, SIZE)


func _ready() -> void:
	if not _textures.has(_kind):
		_textures[_kind] = _make_texture(_core_color(), _rim_color())

	_sprite = Sprite2D.new()
	_sprite.texture = _textures[_kind]
	_sprite.position = Vector2(SIZE, SIZE) / 2.0
	add_child(_sprite)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging:
			_dragging = true
			_drag_offset = Vector2(DisplayServer.mouse_get_position()) - Vector2(position)
		elif not event.pressed:
			_dragging = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		right_clicked.emit()


func _process(delta: float) -> void:
	_time += delta
	_sprite.rotation += delta * SPIN_SPEED
	_sprite.scale = Vector2.ONE * (1.0 + sin(_time * PULSE_SPEED) * 0.05)

	if _dragging:
		position = Vector2i(_clamped_to_desktop(
			Vector2(DisplayServer.mouse_get_position()) - _drag_offset))


## Entry detection runs on the physics tick so it samples exactly where the
## pet's movement steps put him.
func _physics_process(_delta: float) -> void:
	_watch_pet()


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


## Entry check with a swept test: the pet is measured against the segment he
## travelled since the last tick, so a fast throw can't tunnel through the
## vortex between frames. Fires on crossing into the vortex, and — while the
## pet lingers inside one, like in a dropper loop — re-fires every
## [constant LINGER_REFIRE] seconds. `rising` distinguishes the two.
func _watch_pet() -> void:
	if not probe.is_valid():
		return
	var info: Dictionary = probe.call()
	var pet_center: Vector2 = info.center
	if not _had_pet:
		_had_pet = true
		_last_pet_center = pet_center
		return

	var inside := false
	if info.thrown:
		var seg := pet_center - _last_pet_center
		var t := 0.0
		if seg.length_squared() > 0.001:
			t = clampf((center() - _last_pet_center).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var closest := _last_pet_center + seg * t
		inside = center().distance_to(closest) < radius() + float(info.radius) * 0.6

	var rising := inside and not _was_inside
	var lingering := inside and _was_inside and _time - _last_fire >= LINGER_REFIRE
	if rising or lingering:
		_last_fire = _time
		entered.emit(info.velocity, rising)

	_was_inside = inside
	_last_pet_center = pet_center


func _core_color() -> Color:
	return PALETTE[_kind][0]


func _rim_color() -> Color:
	return PALETTE[_kind][1]


## The same swirl ConsumablePortal wears, drawn in this portal's own colours.
static func _make_texture(core: Color, rim: Color) -> ImageTexture:
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
			var color := core.lerp(rim, swirl)
			color.a = 1.0 - pow(t, 3.0)
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)
