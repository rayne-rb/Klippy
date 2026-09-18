class_name VisitingKlippy
extends PetBody

## Somebody else's Klippy, staying over.
##
## The host's VisitHost builds one of these when a visitor announces an arrival,
## dressed from the appearance the visitor carried across the link and left to live
## a normal pet life on the host's desktop: it falls, bounces, can be dragged,
## thrown and rolled, and follows the mouse with its eyes — all locally, with no
## per-frame traffic over the link. What crosses the link is only the moments the
## host cannot decide alone: speech from the visitor's owner, reminders, the
## departure.
##
## Deliberately not a [Klippy] instance — that class owns saves, stats, menus and
## the whole rest of the home machine, none of which a guest should carry. This is
## the look and the physics, nothing more.

signal menu_id_pressed(id: int)

const TEXTURE_SIZE := 400.0
## Matches [constant Klippy.HAT_SWING_MARGIN]: the hat's swing circle is bigger
## than the body, and the window pads for it the same way the real pet's does.
const HAT_SWING_MARGIN := 35.0
const REFERENCE_SIZE := 200.0

const MENU_REMINDERS_ID := 1
const MENU_SEND_HOME_ID := 2

const PUPIL_FOLLOW_RATE := 12.0
const PUPIL_ACTIVATION_RADIUS_SCALE := 2.5
## Rest positions and per-direction pupil reach, traced from the same source art
## [Klippy] uses — the guest renders with the same catalogs, so the same numbers
## keep the pupils inside the sockets. Mirrored by hand rather than shared, since
## [Klippy] keeps them as its own constants.
const LEFT_PUPIL_REST := Vector2(150.5 - 200.0, 129.5 - 200.0)
const LEFT_PUPIL_BOUNDS := Rect2(-18.0, -15.0, 35.0, 28.0)
const RIGHT_PUPIL_REST := Vector2(245.0 - 200.0, 147.0 - 200.0)
const RIGHT_PUPIL_BOUNDS := Rect2(-19.0, -15.0, 38.0, 30.0)

## The host's own pet, so the two can knock each other around. Null when the host
## has no pet in play (e.g. it is itself away through a portal right now).
var host_pet: PetBody

## The guest's art size in pixels, mirroring [member Klippy.current_size]. The
## default matches the pet's, until the arrival payload says otherwise.
var current_size := 200

var context_menu: PopupMenu

var detail: Sprite2D
var left_eye: Sprite2D
var right_eye: Sprite2D
var left_pupil: Sprite2D
var right_pupil: Sprite2D
var hat: Sprite2D

var speech_bubble: SpeechBubble

var _appearance := {}


func _ready() -> void:
	_build_sprite_tree()
	super._ready()
	_apply_appearance()
	_build_click_through_mask()
	_build_menu()


## Dressed from a [code]visit.arrive[/code] payload: catalog ids resolved the same
## way [Klippy] resolves its saved ones — anything the host's catalogs do not know
## falls back to the default rather than leaving the guest half-dressed.
func apply_appearance(appearance: Dictionary) -> void:
	_appearance = appearance


func _build_sprite_tree() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)

	detail = Sprite2D.new()
	detail.name = "Detail"
	sprite.add_child(detail)

	left_eye = Sprite2D.new()
	left_eye.name = "LeftEye"
	sprite.add_child(left_eye)

	left_pupil = Sprite2D.new()
	left_pupil.name = "LeftPupil"
	sprite.add_child(left_pupil)

	right_eye = Sprite2D.new()
	right_eye.name = "RightEye"
	sprite.add_child(right_eye)

	right_pupil = Sprite2D.new()
	right_pupil.name = "RightPupil"
	sprite.add_child(right_pupil)

	hat = Sprite2D.new()
	hat.name = "Hat"
	hat.position = Vector2(0, -100)
	sprite.add_child(hat)


func _apply_appearance() -> void:
	var body_id := str(_appearance.get("bodyId", BodyCatalog.DEFAULT))
	sprite.texture = BodyCatalog.get_def(
			body_id if body_id in BodyCatalog.ids() else BodyCatalog.DEFAULT).texture

	var expression_id := str(_appearance.get("expressionId", ExpressionCatalog.DEFAULT))
	detail.texture = ExpressionCatalog.get_def(
			expression_id if expression_id in ExpressionCatalog.ids() else ExpressionCatalog.DEFAULT).texture

	var eyes_id := str(_appearance.get("eyesId", EyesCatalog.DEFAULT))
	var eyes_def := EyesCatalog.get_def(
			eyes_id if eyes_id in EyesCatalog.ids() else EyesCatalog.DEFAULT)
	left_eye.texture = eyes_def.texture
	right_eye.texture = eyes_def.right_texture

	var pupils_id := str(_appearance.get("pupilsId", PupilsCatalog.DEFAULT))
	var pupils_def := PupilsCatalog.get_def(
			pupils_id if pupils_id in PupilsCatalog.ids() else PupilsCatalog.DEFAULT)
	left_pupil.texture = pupils_def.texture
	right_pupil.texture = pupils_def.right_texture

	var hat_id := str(_appearance.get("hatId", HatsCatalog.DEFAULT))
	hat.texture = HatsCatalog.get_def(
			hat_id if hat_id in HatsCatalog.ids() else HatsCatalog.DEFAULT).texture


func _build_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.add_item("Reminders", MENU_REMINDERS_ID)
	context_menu.add_item("Send home", MENU_SEND_HOME_ID)
	context_menu.id_pressed.connect(func(id: int) -> void: menu_id_pressed.emit(id))
	RockyTheme.style_popup(context_menu)
	add_child(context_menu)


func _input(event: InputEvent) -> void:
	super._input(event)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		context_menu.position = DisplayServer.mouse_get_position()
		context_menu.popup()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		say(Dialogue.random_greeting())


## A passing remark over the guest's own head. Used for the arrival greeting,
## things the owner says through the link, and reminders set on this side.
func say(text: String) -> void:
	_get_speech_bubble().say(text, get_window())


## A reminder nag: stays up and pokes until clicked, exactly like at home.
func announce_reminder(message: String) -> void:
	_get_speech_bubble().announce_reminder(message, get_window())


func _get_speech_bubble() -> SpeechBubble:
	if speech_bubble == null:
		speech_bubble = SpeechBubble.new()
		add_child(speech_bubble)
	return speech_bubble


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if host_pet == null or not is_instance_valid(host_pet):
		return

	var host_window := host_pet.get_window()
	if not host_window.visible or host_pet.state == State.DRAGGING or state == State.DRAGGING:
		return

	# One-sided on purpose: the guest resolves against the host, and the impulse
	# math in _resolve_body_collision moves both bodies, so the host is never
	# unaware of being bonked. The host never resolves back, or each pair would
	# be corrected twice a tick.
	_resolve_body_collision(host_pet, delta)


func _process(delta: float) -> void:
	_update_pupils(delta)


func _update_pupils(delta: float) -> void:
	var window := get_window()
	var mouse_screen := Vector2(DisplayServer.mouse_get_position())
	var window_center := Vector2(window.position) + Vector2(window.size) / 2.0
	var activation_radius := current_size * PUPIL_ACTIVATION_RADIUS_SCALE

	var wanted_left := Vector2.ZERO
	var wanted_right := Vector2.ZERO
	if mouse_screen.distance_to(window_center) <= activation_radius:
		var look_pos := sprite.to_local(mouse_screen - Vector2(window.position))
		wanted_left = look_pos - LEFT_PUPIL_REST
		wanted_right = look_pos - RIGHT_PUPIL_REST

	left_pupil.position = _follow_pupil(left_pupil.position, wanted_left, LEFT_PUPIL_BOUNDS, delta)
	right_pupil.position = _follow_pupil(right_pupil.position, wanted_right, RIGHT_PUPIL_BOUNDS, delta)


func _follow_pupil(current: Vector2, wanted_offset: Vector2, bounds: Rect2, delta: float) -> Vector2:
	var rx := bounds.end.x if wanted_offset.x >= 0.0 else -bounds.position.x
	var ry := bounds.end.y if wanted_offset.y >= 0.0 else -bounds.position.y
	var clamped := wanted_offset
	if rx > 0.0 and ry > 0.0:
		var t := pow(wanted_offset.x / rx, 2) + pow(wanted_offset.y / ry, 2)
		if t > 1.0:
			clamped = wanted_offset / sqrt(t)

	var lerp_t := 1.0 - exp(-PUPIL_FOLLOW_RATE * delta)
	return current.lerp(clamped, lerp_t)


## Window geometry and physical properties to match [Klippy._apply_size], so a
## guest arrives the size he left home — hat headroom included. Returns the
## window size the host should give this body.
static func window_size_for(pet_size: int) -> Vector2i:
	var margin := int(round(HAT_SWING_MARGIN * (pet_size / TEXTURE_SIZE)))
	return Vector2i(pet_size, pet_size) + Vector2i.ONE * (margin * 2)


func scale_to_size(pet_size: int) -> void:
	var window := get_window()
	var window_size := window_size_for(pet_size)
	window.content_scale_size = window_size
	window.size = window_size

	sprite.scale = Vector2.ONE * (pet_size / TEXTURE_SIZE)
	position = Vector2(window_size) / 2.0
	current_size = pet_size

	roll_radius = pet_size * 0.45
	mass = pow(pet_size / REFERENCE_SIZE, 2.0)

	_rebuild_mask_points()
	_update_passthrough_mask(sprite.rotation)
