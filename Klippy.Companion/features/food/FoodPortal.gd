class_name FoodPortal
extends Window

## A brief animated glow that opens at the middle of the screen and closes
## again, giving summoned food somewhere to visibly pop out of instead of
## just appearing next to Klippy.

## Fired the instant the portal finishes opening — spawn the food now, so it
## looks like it came out of the portal rather than appearing before or
## after it's actually open.
signal opened

const SIZE := 140
const OPEN_TIME := 0.25
const HOLD_TIME := 0.2
const CLOSE_TIME := 0.3
const SPIN_SPEED := 2.5

static var _texture: ImageTexture

var _sprite: Sprite2D


func _init() -> void:
	borderless = true
	transparent = true
	always_on_top = true
	unfocusable = true
	visible = true
	size = Vector2i(SIZE, SIZE)
	content_scale_size = Vector2i(SIZE, SIZE)


func _ready() -> void:
	if _texture == null:
		_texture = _make_texture()

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.position = Vector2(SIZE, SIZE) / 2.0
	_sprite.scale = Vector2.ZERO
	add_child(_sprite)

	var bounds := DisplayServer.screen_get_usable_rect(current_screen)
	position = bounds.position + bounds.size / 2 - Vector2i(SIZE, SIZE) / 2

	_play()


func _process(delta: float) -> void:
	_sprite.rotation += delta * SPIN_SPEED


func _play() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2.ONE, OPEN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): opened.emit())
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(_sprite, "scale", Vector2.ZERO, CLOSE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


## A small violet/cyan vortex, brightest at the core and fading to nothing at
## the rim — generated once and shared by every portal rather than rebuilt
## per summon.
static func _make_texture() -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE, SIZE) / 2.0
	var radius := SIZE / 2.0
	var core := Color(0.55, 0.25, 0.85)
	var rim := Color(0.35, 0.8, 1.0)

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
