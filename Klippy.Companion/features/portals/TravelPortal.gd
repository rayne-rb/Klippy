class_name TravelPortal
extends Window

## One end of a linked portal pair that lives on the desktop until banished.
## It watches for the pet to fly into it — through [member probe], supplied by
## the pet itself — and reports the entry, so the pair's owner can teleport
## him out of the twin portal, which may sit on a different monitor.

signal entered(entry_velocity: Vector2)

const SIZE := 160
const SPIN_SPEED := 1.1
const PULSE_SPEED := 3.0

static var _textures := {}

## Supplied by the pet: returns {thrown, center, radius, velocity} for the
## pet's current state, so the portal can spot entries without knowing
## anything about how the pet moves.
var probe: Callable

var _sprite: Sprite2D
var _kind: String
var _time := 0.0
var _was_inside := false


func _init(kind: String) -> void:
	_kind = kind
	borderless = true
	transparent = true
	always_on_top = true
	unfocusable = true
	mouse_passthrough = true
	size = Vector2i(SIZE, SIZE)
	content_scale_size = Vector2i(SIZE, SIZE)


func _ready() -> void:
	if not _textures.has(_kind):
		_textures[_kind] = _make_texture(_core_color(), _rim_color())

	_sprite = Sprite2D.new()
	_sprite.texture = _textures[_kind]
	_sprite.position = Vector2(SIZE, SIZE) / 2.0
	add_child(_sprite)


func _process(delta: float) -> void:
	_time += delta
	_sprite.rotation += delta * SPIN_SPEED
	_sprite.scale = Vector2.ONE * (1.0 + sin(_time * PULSE_SPEED) * 0.05)
	_watch_pet()


## Positions the portal's center at [param center] — global desktop
## coordinates, so any monitor will do.
func place(center: Vector2i) -> void:
	position = center - Vector2i(SIZE, SIZE) / 2


func center() -> Vector2:
	return Vector2(position) + Vector2(SIZE, SIZE) / 2.0


func radius() -> float:
	return SIZE / 2.0


## Edge-triggered entry check: fires only on the frame the pet's center
## crosses into the vortex while thrown. Resting or dragging inside it does
## nothing, and the twin portal doesn't re-catch him the instant he exits.
func _watch_pet() -> void:
	if not probe.is_valid():
		return
	var info: Dictionary = probe.call()
	var inside: bool = (
		info.thrown
		and center().distance_to(info.center) < radius() + float(info.radius) * 0.6
	)
	if inside and not _was_inside:
		entered.emit(info.velocity)
	_was_inside = inside


func _core_color() -> Color:
	return Color("1c46c9") if _kind == "blue" else Color("b3122f")


func _rim_color() -> Color:
	return Color("55c8ff") if _kind == "blue" else Color("ff8a55")


## The same swirl FoodPortal wears, drawn in this portal's own colours.
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
