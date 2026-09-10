class_name Klippy
extends PetBody

const TEXTURE_SIZE := 400.0
const SIZE_STEPS := [100, 200, 300, 400]
const CLOSE_ID := 0
const DVD_ID := 1
const SETTINGS_ID := 2
const FEED_ID := 3
const STATUS_ID := 4
const REVIVE_ID := 5
const DEV_TOOLS_ID := 6

const REFERENCE_SIZE := 200.0
const DVD_SPEED := 220.0
const DAMAGE_SPEED_THRESHOLD := 1200.0

const COMPLAINT_CHANCE := 0.12
const COMPLAINT_COOLDOWN := 4.0

const FOOD_WINDOW_SIZE := 60
const FOOD_MASS := 0.3
const MAX_FOOD_ITEMS := 8

const HUNGRY_BOUNCE_AMPLITUDE := 28.0
const HUNGRY_BOUNCE_SPEED := 10.0
const HUNGRY_BOUNCES_PER_BURST := 5
const HUNGRY_BOUNCE_ENVELOPE_MIN_SCALE := 0.35
const HUNGRY_BURST_INTERVAL := 300.0
const VERY_HUNGRY_BURST_INTERVAL := 150.0

const PLAY_MIN_HEALTH := 60.0
const PLAY_DISTANCE_THRESHOLD := 400.0
const PLAY_MOOD_BOOST := 1.5

var active_food_items: Array[Window] = []
var food_window_pool: Array[Window] = []

var idle_base_y := 0
var bounce_timer := 0.0
var bouncing := false
var bounce_phase := 0.0
var bounce_cycles_done := 0

var play_tracking_active := false
var play_distance_traveled := 0.0

var context_menu: PopupMenu
var settings_window: SettingsPanel
var status_dialog: StatusDialog
var close_confirm_dialog: ConfirmationDialog
var dev_tools_dialog: DevToolsDialog

var speech_bubble: SpeechBubble
var complaint_cooldown_timer: Timer
var stats: PetStats

var dvd_mode := false

var raw_polygon: PackedVector2Array = PackedVector2Array()
var mask_points: PackedVector2Array = PackedVector2Array()

var show_hitbox := false

var current_size := 200

var show_food_value := false
var show_mood_value := false
var show_health_value := false
var dev_tools_enabled := false
var vsync_enabled := true
var target_fps := 30


func _ready() -> void:
	super._ready()
	_build_click_through_mask()
	_recompute_physical_properties()

	var save_data := SaveData.load_data()
	var klippy_data: Dictionary = save_data.get("klippy", {})
	var stats_data: Dictionary = save_data.get("stats", {})
	var settings_data: Dictionary = save_data.get("settings", {})
	var meta_data: Dictionary = save_data.get("meta", {})

	stats = PetStats.new()
	add_child(stats)
	stats.food = stats_data.get("food", PetStats.MAX_FOOD)
	stats.mood = stats_data.get("mood", PetStats.MOOD_MID)
	stats.health = stats_data.get("health", PetStats.MAX_HEALTH)
	stats.feeding_enabled = stats_data.get("feeding_enabled", false)
	stats.is_dead = stats_data.get("is_dead", false)
	if meta_data.has("saved_at"):
		var elapsed: float = Time.get_unix_time_from_system() - float(meta_data["saved_at"])
		stats.apply_offline_progress(elapsed)
	stats.feeding_enabled_changed.connect(_on_feeding_enabled_changed)

	show_food_value = settings_data.get("show_food_value", false)
	show_mood_value = settings_data.get("show_mood_value", false)
	show_health_value = settings_data.get("show_health_value", false)
	dev_tools_enabled = settings_data.get("dev_tools_enabled", false)
	vsync_enabled = settings_data.get("vsync_enabled", true)
	target_fps = settings_data.get("target_fps", 30)
	_apply_display_settings()

	context_menu = PopupMenu.new()
	context_menu.add_item("Feed", FEED_ID)
	context_menu.add_item("Status", STATUS_ID)
	context_menu.add_item("DVD", DVD_ID)
	context_menu.add_item("Settings", SETTINGS_ID)
	context_menu.add_item("Close Klippy", CLOSE_ID)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(context_menu)
	_on_feeding_enabled_changed(stats.feeding_enabled)
	stats.died.connect(_update_revive_item)
	_update_revive_item()
	_update_dev_tools_item()

	var saved_size: int = klippy_data.get("size", current_size)
	if saved_size in SIZE_STEPS:
		_apply_size(saved_size)

	idle_base_y = get_window().position.y

	complaint_cooldown_timer = Timer.new()
	complaint_cooldown_timer.one_shot = true
	complaint_cooldown_timer.wait_time = COMPLAINT_COOLDOWN
	add_child(complaint_cooldown_timer)

	get_tree().root.close_requested.connect(_on_quit_requested)


func _on_show_food_toggled(enabled: bool) -> void:
	show_food_value = enabled
	if status_dialog:
		status_dialog.set_show_food_value(enabled)


func _on_show_mood_toggled(enabled: bool) -> void:
	show_mood_value = enabled
	if status_dialog:
		status_dialog.set_show_mood_value(enabled)


func _on_show_health_toggled(enabled: bool) -> void:
	show_health_value = enabled
	if status_dialog:
		status_dialog.set_show_health_value(enabled)


func _on_dev_tools_toggled(enabled: bool) -> void:
	dev_tools_enabled = enabled
	_update_dev_tools_item()


func _update_dev_tools_item() -> void:
	var index := context_menu.get_item_index(DEV_TOOLS_ID)
	if dev_tools_enabled:
		if index == -1:
			context_menu.add_item("Dev Tools", DEV_TOOLS_ID)
	elif index != -1:
		context_menu.remove_item(index)


func _open_settings() -> void:
	if settings_window == null:
		settings_window = SettingsPanel.new()
		add_child(settings_window)
		settings_window.setup(stats, {
			"show_food": show_food_value,
			"show_mood": show_mood_value,
			"show_health": show_health_value,
			"dev_tools_enabled": dev_tools_enabled,
			"size": current_size,
			"vsync_enabled": vsync_enabled,
			"fps": target_fps,
		}, SIZE_STEPS)
		settings_window.show_food_toggled.connect(_on_show_food_toggled)
		settings_window.show_mood_toggled.connect(_on_show_mood_toggled)
		settings_window.show_health_toggled.connect(_on_show_health_toggled)
		settings_window.dev_tools_toggled.connect(_on_dev_tools_toggled)
		settings_window.size_selected.connect(_on_size_selected)
		settings_window.vsync_toggled.connect(_on_vsync_toggled)
		settings_window.fps_selected.connect(_on_fps_selected)
		settings_window.close_requested.connect(_on_settings_closed)
	settings_window.popup_centered()


func _on_settings_closed() -> void:
	settings_window.queue_free()
	settings_window = null


func _open_status() -> void:
	if status_dialog == null:
		status_dialog = StatusDialog.new()
		add_child(status_dialog)
		status_dialog.setup(stats)
		status_dialog.set_show_food_value(show_food_value)
		status_dialog.set_show_mood_value(show_mood_value)
		status_dialog.set_show_health_value(show_health_value)
		status_dialog.close_requested.connect(_on_status_closed)
	status_dialog.popup_centered()


func _on_status_closed() -> void:
	status_dialog.queue_free()
	status_dialog = null


func _open_dev_tools() -> void:
	if dev_tools_dialog == null:
		dev_tools_dialog = DevToolsDialog.new()
		add_child(dev_tools_dialog)
		dev_tools_dialog.setup(stats)
		dev_tools_dialog.bounce_triggered.connect(trigger_bounce_now)
		dev_tools_dialog.close_requested.connect(_on_dev_tools_closed)
	dev_tools_dialog.popup_centered()


func _on_dev_tools_closed() -> void:
	dev_tools_dialog.queue_free()
	dev_tools_dialog = null


func _open_close_confirm() -> void:
	if close_confirm_dialog == null:
		close_confirm_dialog = ConfirmationDialog.new()
		close_confirm_dialog.title = "Close Klippy"
		close_confirm_dialog.dialog_text = "Close Klippy?"
		close_confirm_dialog.confirmed.connect(_on_quit_requested)
		close_confirm_dialog.canceled.connect(_on_close_confirm_closed)
		close_confirm_dialog.close_requested.connect(_on_close_confirm_closed)
		add_child(close_confirm_dialog)
	close_confirm_dialog.popup_centered()


func _on_close_confirm_closed() -> void:
	if close_confirm_dialog:
		close_confirm_dialog.queue_free()
		close_confirm_dialog = null


func _get_speech_bubble() -> SpeechBubble:
	if speech_bubble == null:
		speech_bubble = SpeechBubble.new()
		add_child(speech_bubble)
	return speech_bubble


func _on_vsync_toggled(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_display_settings()


func _on_fps_selected(fps: int) -> void:
	target_fps = fps
	_apply_display_settings()


func _apply_display_settings() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = target_fps


func _on_size_selected(new_size: int) -> void:
	_apply_size(new_size)


func _save_state() -> void:
	SaveData.save_data({
		"klippy": {"size": current_size},
		"stats": {
			"food": stats.food,
			"mood": stats.mood,
			"health": stats.health,
			"feeding_enabled": stats.feeding_enabled,
			"is_dead": stats.is_dead,
		},
		"settings": {
			"show_food_value": show_food_value,
			"show_mood_value": show_mood_value,
			"show_health_value": show_health_value,
			"dev_tools_enabled": dev_tools_enabled,
			"vsync_enabled": vsync_enabled,
			"target_fps": target_fps,
		},
		"meta": {"saved_at": Time.get_unix_time_from_system()},
	})


func _on_quit_requested() -> void:
	_save_state()
	get_tree().quit()


func _maybe_complain() -> void:
	if stats.is_dead or not complaint_cooldown_timer.is_stopped():
		return
	if randf() < COMPLAINT_CHANCE:
		_get_speech_bubble().say(Dialogue.random_complaint(), get_window())
		complaint_cooldown_timer.start()


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

	DisplayServer.window_set_mouse_passthrough(_rotated_mask_points(angle), 0)


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		CLOSE_ID:
			_open_close_confirm()
		SETTINGS_ID:
			_open_settings()
		STATUS_ID:
			_open_status()
		DVD_ID:
			_toggle_dvd_mode()
		FEED_ID:
			_spawn_food_item()
		REVIVE_ID:
			stats.revive()
			_update_revive_item()
		DEV_TOOLS_ID:
			_open_dev_tools()


func _update_revive_item() -> void:
	var index := context_menu.get_item_index(REVIVE_ID)
	if stats.is_dead:
		if index == -1:
			context_menu.add_item("Revive", REVIVE_ID)
	elif index != -1:
		context_menu.remove_item(index)


func _on_feeding_enabled_changed(_enabled: bool) -> void:
	_update_feed_menu_state()


func _update_feed_menu_state() -> void:
	var can_feed := stats.feeding_enabled and active_food_items.size() < MAX_FOOD_ITEMS
	context_menu.set_item_disabled(context_menu.get_item_index(FEED_ID), not can_feed)


func _spawn_food_item() -> void:
	if active_food_items.size() >= MAX_FOOD_ITEMS:
		return

	var window: Window
	var body: FoodBody

	if not food_window_pool.is_empty():
		window = food_window_pool.pop_back()
		body = window.get_child(0) as FoodBody
	else:
		window = Window.new()
		window.borderless = true
		window.transparent = true
		window.always_on_top = true
		window.unfocusable = false
		var window_size := Vector2i(FOOD_WINDOW_SIZE, FOOD_WINDOW_SIZE)
		window.size = window_size
		window.content_scale_size = window_size

		body = FoodBody.new()
		body.position = Vector2(window_size) / 2.0
		body.roll_radius = FOOD_WINDOW_SIZE * 0.45

		var sprite2d := Sprite2D.new()
		sprite2d.texture = _make_food_texture()
		body.add_child(sprite2d)
		window.add_child(body)

		add_child(window)
		body.consumed.connect(_on_food_item_consumed.bind(window))

	body.mass = FOOD_MASS
	body.stats = stats
	body.klippy_window = get_window()
	body.velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.drag_spin_target = 0.0
	body.state = PetBody.State.IDLE
	body.sprite.rotation = 0.0
	body.set_physics_process(true)

	var klippy_window := get_window()
	window.position = klippy_window.position + Vector2i(klippy_window.size.x + 10, 0)
	window.show()

	active_food_items.append(window)
	_update_feed_menu_state()


func _on_food_item_consumed(window: Window) -> void:
	var body := window.get_child(0) as FoodBody
	body.set_physics_process(false)
	window.hide()
	active_food_items.erase(window)
	if food_window_pool.size() < MAX_FOOD_ITEMS:
		food_window_pool.append(window)
	else:
		window.queue_free()
	_update_feed_menu_state()


func _make_food_texture() -> ImageTexture:
	var diameter := 40
	var image := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var radius := diameter / 2.0
	var center := Vector2(radius, radius)
	for y in diameter:
		for x in diameter:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			image.set_pixel(x, y, Color(0.85, 0.2, 0.2, 1.0) if dist <= radius else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _toggle_dvd_mode() -> void:
	dvd_mode = not dvd_mode
	angular_velocity = 0.0
	if dvd_mode:
		velocity = Vector2(DVD_SPEED, 0.0).rotated(randf_range(0.0, TAU))
		_set_state(State.THROWN)
	else:
		velocity = Vector2.ZERO
		_set_state(State.IDLE)


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
	super._input(event)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		context_menu.position = DisplayServer.mouse_get_position()
		context_menu.popup()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		show_hitbox = not show_hitbox
		queue_redraw()


func _on_drag_started(event: InputEventMouseButton) -> void:
	dvd_mode = false
	if event.double_click and not stats.is_dead:
		_get_speech_bubble().say(Dialogue.random_greeting(), get_window())


func _on_rotation_changed(angle: float) -> void:
	_update_passthrough_mask(angle)
	if show_hitbox:
		queue_redraw()


func _on_energetic_bounce(impact_speed: float) -> void:
	if impact_speed >= DAMAGE_SPEED_THRESHOLD:
		stats.apply_throw_damage()
	_maybe_complain()


func _draw() -> void:
	if not show_hitbox or mask_points.is_empty():
		return

	var points := PackedVector2Array()
	points.resize(mask_points.size() + 1)
	for i in mask_points.size():
		points[i] = mask_points[i].rotated(sprite.rotation)
	points[mask_points.size()] = points[0]

	draw_polyline(points, Color.RED, 2.0)


func _run_state_physics(delta: float, window: Window) -> void:
	if dvd_mode:
		_process_dvd(delta, window)
		return

	var pos_before := Vector2(window.position)
	super._run_state_physics(delta, window)

	if state == State.THROWN and play_tracking_active:
		play_distance_traveled += (Vector2(window.position) - pos_before).length()


func _on_state_enter(new_state: State) -> void:
	if new_state == State.IDLE:
		idle_base_y = get_window().position.y
		_reset_bounce()
	elif new_state == State.THROWN:
		play_tracking_active = not dvd_mode
		play_distance_traveled = 0.0


func _on_state_exit(old_state: State) -> void:
	if old_state != State.THROWN or not play_tracking_active:
		return

	play_tracking_active = false
	if play_distance_traveled >= PLAY_DISTANCE_THRESHOLD and stats.health > PLAY_MIN_HEALTH:
		stats.apply_play_boost(PLAY_MOOD_BOOST)


func _reset_bounce() -> void:
	bounce_timer = 0.0
	bouncing = false
	bounce_phase = 0.0
	bounce_cycles_done = 0


func _get_bounce_burst_interval() -> float:
	match stats.get_status():
		"Hungry":
			return HUNGRY_BURST_INTERVAL
		"Very Hungry":
			return VERY_HUNGRY_BURST_INTERVAL
		_:
			return 0.0


func _bounce_envelope(cycle_index: int) -> float:
	if HUNGRY_BOUNCES_PER_BURST <= 1:
		return 1.0
	var t := float(cycle_index) / float(HUNGRY_BOUNCES_PER_BURST - 1)
	return HUNGRY_BOUNCE_ENVELOPE_MIN_SCALE + (1.0 - HUNGRY_BOUNCE_ENVELOPE_MIN_SCALE) * sin(PI * t)


func trigger_bounce_now() -> void:
	if state != State.IDLE or bouncing:
		return
	bouncing = true
	bounce_phase = 0.0
	bounce_cycles_done = 0


func _process_idle_base(delta: float, window: Window) -> void:
	if stats.is_dead:
		return

	if bouncing:
		bounce_phase += delta * HUNGRY_BOUNCE_SPEED
		if bounce_phase >= TAU:
			bounce_phase -= TAU
			bounce_cycles_done += 1
			if bounce_cycles_done >= HUNGRY_BOUNCES_PER_BURST:
				window.position = Vector2i(window.position.x, idle_base_y)
				_reset_bounce()
				return

		var amplitude := HUNGRY_BOUNCE_AMPLITUDE * _bounce_envelope(bounce_cycles_done)
		var offset := int(round(sin(bounce_phase) * amplitude))
		window.position = Vector2i(window.position.x, idle_base_y + offset)
		return

	var burst_interval := _get_bounce_burst_interval()
	if burst_interval <= 0.0:
		bounce_timer = 0.0
		return

	bounce_timer += delta
	if bounce_timer >= burst_interval:
		bouncing = true
		bounce_phase = 0.0
		bounce_cycles_done = 0


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
