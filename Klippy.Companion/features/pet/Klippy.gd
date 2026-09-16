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
const SUMMON_FOOD_ID := 7
const CONNECTION_ID := 8
const REMINDERS_ID := 9
const SUMMON_PORTALS_ID := 10
const BANISH_PORTALS_ID := 11

# While the pet loiters inside a portal (a dropper loop) the portal re-fires
# every LINGER_REFIRE seconds; this gap throttles those repeat teleports.
# Fresh crossings into a portal teleport immediately and ignore it.
const PORTAL_CHAIN_COOLDOWN := 0.08
# Exits are capped so a dropper loop stays smooth instead of accelerating
# until the pet tunnels through everything.
const PORTAL_MAX_EXIT_SPEED := 1300.0

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

const PUPIL_FOLLOW_RATE := 12.0
# Scales with current_size so activation range stays proportionate as Klippy
# is resized, rather than a flat pixel radius that would feel too small at
# 400 or too large at 100.
const PUPIL_ACTIVATION_RADIUS_SCALE := 2.5
# Rest position and the room each pupil has to move before its edge would exit
# the eye white, per side, traced from the source art (both eyes are hand-drawn
# and asymmetric, so this isn't derived at runtime). Rest is expressed in
# Sprite2D-local space, which Godot centers on the 400x400 texture's midpoint
# (Sprite2D.centered defaults to true) — that's why these aren't the raw
# 0..400 pixel coordinates traced from the image.
const LEFT_PUPIL_REST := Vector2(150.5 - 200.0, 129.5 - 200.0)
# The left eye's raw alpha bbox is misleading on the right side: it picks up a
# small highlight-glint blob near the top-right that's disconnected from the
# actual socket. Traced at the pupil's own vertical center instead, the real
# eye-white edge there is ~x=189, not the ~213 the full-image bbox suggests.
const LEFT_PUPIL_BOUNDS := Rect2(-18.0, -15.0, 35.0, 28.0)
const RIGHT_PUPIL_REST := Vector2(245.0 - 200.0, 147.0 - 200.0)
const RIGHT_PUPIL_BOUNDS := Rect2(-19.0, -15.0, 38.0, 30.0)

const PLAY_MIN_HEALTH := 60.0
const PLAY_DISTANCE_THRESHOLD := 400.0
const PLAY_MOOD_BOOST := 1.5

var food_spawner: FoodSpawner

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
var close_confirm_dialog: Window
var dev_tools_dialog: DevToolsDialog
var food_bag: FoodBagBody
var connection_dialog: PairingDialog
var reminder_dialog: ReminderDialog

var remote_control: RemoteControl
var reminder_scheduler: ReminderScheduler

var blue_portal: TravelPortal
var red_portal: TravelPortal
var travel_portals: Array[TravelPortal] = []
var _portal_chain_cooldown := 0.0

var left_pupil: Sprite2D
var right_pupil: Sprite2D

var speech_bubble: SpeechBubble
var complaint_cooldown_timer: Timer
var stats: PetStats

var dvd_mode := false

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
	left_pupil = sprite.get_node(^"LeftPupil") as Sprite2D
	right_pupil = sprite.get_node(^"RightPupil") as Sprite2D
	_build_click_through_mask()
	_recompute_physical_properties()

	var save_data := SaveData.load_data()
	var klippy_data: Dictionary = save_data.get("klippy", {})
	var stats_data: Dictionary = save_data.get("stats", {})
	var settings_data: Dictionary = save_data.get("settings", {})
	var meta_data: Dictionary = save_data.get("meta", {})
	var food_bag_data: Dictionary = save_data.get("food_bag", {})

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

	food_spawner = FoodSpawner.new()
	add_child(food_spawner)
	food_spawner.setup(stats, get_window())
	food_spawner.availability_changed.connect(_update_feed_menu_state)

	# Lets the server and the phone drive the pet. Everything it can reach is
	# handed over explicitly here, so the pet keeps working with the link absent.
	remote_control = RemoteControl.new()
	add_child(remote_control)
	remote_control.setup(stats, food_spawner, _say, _set_dvd_mode)

	show_food_value = settings_data.get("show_food_value", false)
	show_mood_value = settings_data.get("show_mood_value", false)
	show_health_value = settings_data.get("show_health_value", false)
	monitor_border_wrap = settings_data.get("border_wrap", false)
	dev_tools_enabled = settings_data.get("dev_tools_enabled", false)
	vsync_enabled = settings_data.get("vsync_enabled", true)
	target_fps = settings_data.get("target_fps", 30)
	_apply_display_settings()

	context_menu = PopupMenu.new()
	context_menu.add_item("Feed", FEED_ID)
	context_menu.add_item("Summon Food", SUMMON_FOOD_ID)
	context_menu.add_item("Summon Portals", SUMMON_PORTALS_ID)
	context_menu.add_item("Status", STATUS_ID)
	context_menu.add_item("Reminders", REMINDERS_ID)
	context_menu.add_item("DVD", DVD_ID)
	context_menu.add_item("Connection", CONNECTION_ID)
	context_menu.add_item("Settings", SETTINGS_ID)
	context_menu.add_item("Close Klippy", CLOSE_ID)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	RockyTheme.style_popup(context_menu)
	add_child(context_menu)
	_on_feeding_enabled_changed(stats.feeding_enabled)
	stats.died.connect(_update_revive_item)
	_update_revive_item()
	_update_dev_tools_item()

	_create_food_bag()
	# The bag's art isn't a simple rectangle, so anywhere clever picked ahead
	# of time risks landing just outside it — dead center is the one point
	# guaranteed to be inside, and food-vs-food collision spreads the pile
	# back out over the following few ticks. They still need a tiny nudge
	# apart from each other first, though: exactly-coincident items have no
	# meaningful direction to push apart along, so left dead-on-top of one
	# another they'd just stay stacked forever.
	var bag_center := Vector2i(food_bag.get_window().size) / 2
	var jitter_index := 0
	for food_id in food_bag_data:
		var stored_count: int = int(food_bag_data[food_id])
		for i in stored_count:
			var jitter := Vector2(cos(jitter_index * 2.4), sin(jitter_index * 2.4)) * 5.0
			_spawn_contained_food(food_id, bag_center + Vector2i(jitter))
			jitter_index += 1

	var saved_size: int = klippy_data.get("size", current_size)
	if saved_size in SIZE_STEPS:
		_apply_size(saved_size)

	idle_base_y = get_window().position.y

	reminder_scheduler = ReminderScheduler.new()
	add_child(reminder_scheduler)
	reminder_scheduler.setup(save_data.get("reminders", {}))
	reminder_scheduler.reminder_due.connect(_on_reminder_due)
	reminder_scheduler.reminders_changed.connect(_save_state)

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


func _on_monitor_border_wrap_toggled(enabled: bool) -> void:
	monitor_border_wrap = enabled


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
			"border_wrap": monitor_border_wrap,
			"size": current_size,
			"vsync_enabled": vsync_enabled,
			"fps": target_fps,
		}, SIZE_STEPS)
		settings_window.show_food_toggled.connect(_on_show_food_toggled)
		settings_window.show_mood_toggled.connect(_on_show_mood_toggled)
		settings_window.show_health_toggled.connect(_on_show_health_toggled)
		settings_window.dev_tools_toggled.connect(_on_dev_tools_toggled)
		settings_window.monitor_border_wrap_toggled.connect(_on_monitor_border_wrap_toggled)
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


func _create_food_bag() -> void:
	var window := Window.new()
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	window.unfocusable = true

	var art_scale := FoodBagBody.TARGET_HEIGHT / FoodBagBody.BACK_TEXTURE.get_size().y
	var visual_size := Vector2(FoodBagBody.BACK_TEXTURE.get_size()) * art_scale
	var window_size := Vector2i(visual_size) + Vector2i.ONE * (FoodBagBody.WINDOW_MARGIN * 2)
	window.size = window_size
	window.content_scale_size = window_size

	var body := FoodBagBody.new()
	body.position = Vector2(window_size) / 2.0
	body.roll_radius = minf(visual_size.x, visual_size.y) * 0.45
	body.klippy = self
	window.add_child(body)

	add_child(window)

	var klippy_window := get_window()
	window.position = klippy_window.position + Vector2i(-window_size.x - 10, 0)
	window.visible = false

	body.grabbed.connect(_raise_contained_food)
	food_bag = body


func _toggle_food_bag() -> void:
	var window := food_bag.get_window()
	if window.visible:
		window.hide()
	else:
		window.show()
		_raise_contained_food()


func _raise_contained_food() -> void:
	for window in active_food_items:
		var body := window.get_child(0) as FoodBody
		if body.contained_in == food_bag:
			window.move_to_foreground()


## Says something out loud. Handed to RemoteControl so the phone can put words in
## Klippy's mouth without reaching into the speech bubble itself.
func _say(text: String) -> void:
	if stats.is_dead:
		return
	_get_speech_bubble().say(text, get_window())


func _open_connection() -> void:
	if connection_dialog == null:
		connection_dialog = PairingDialog.new()
		add_child(connection_dialog)
		connection_dialog.unpair_requested.connect(_on_unpair_requested)
		connection_dialog.close_requested.connect(_on_connection_closed)
	connection_dialog.popup_centered()


func _on_connection_closed() -> void:
	connection_dialog.queue_free()
	connection_dialog = null


func _open_reminders() -> void:
	if reminder_dialog == null:
		reminder_dialog = ReminderDialog.new()
		add_child(reminder_dialog)
		reminder_dialog.setup(reminder_scheduler)
		reminder_dialog.close_requested.connect(_on_reminders_closed)
	reminder_dialog.popup_centered()


func _on_reminders_closed() -> void:
	reminder_dialog.queue_free()
	reminder_dialog = null


## Hands the due reminder to the speech bubble, which keeps it up and nagging
## until clicked. Reminders speak even when Klippy is dead — the user asked
## for them, after all.
func _on_reminder_due(reminder: Dictionary) -> void:
	var message := str(reminder.get("message", "")).strip_edges()
	if message.is_empty():
		return
	_get_speech_bubble().announce_reminder(message, get_window())


func _on_unpair_requested() -> void:
	KlippyLink.forget_pairing()


func _open_close_confirm() -> void:
	if close_confirm_dialog == null:
		close_confirm_dialog = Window.new()
		var vbox := RockyTheme.setup_window(close_confirm_dialog, "Close Klippy")

		var label := Label.new()
		label.text = "Really say goodbye?"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_END
		vbox.add_child(row)

		var keep_button := Button.new()
		keep_button.text = "Keep him"
		keep_button.pressed.connect(func() -> void: close_confirm_dialog.close_requested.emit())
		row.add_child(keep_button)

		var close_button := Button.new()
		close_button.text = "Close"
		close_button.theme_type_variation = "ButtonPrimary"
		close_button.pressed.connect(_on_quit_requested)
		row.add_child(close_button)

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
	var contained_counts := {}
	for window in active_food_items:
		var body := window.get_child(0) as FoodBody
		if body.contained_in == food_bag:
			contained_counts[body.food_type] = contained_counts.get(body.food_type, 0) + 1

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
			"border_wrap": monitor_border_wrap,
			"vsync_enabled": vsync_enabled,
			"target_fps": target_fps,
		},
		"food_bag": contained_counts,
		"reminders": reminder_scheduler.to_save_data(),
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
			_toggle_food_bag()
		REVIVE_ID:
			stats.revive()
			_update_revive_item()
		DEV_TOOLS_ID:
			_open_dev_tools()
		SUMMON_FOOD_ID:
			_summon_food()
		SUMMON_PORTALS_ID:
			_summon_portals()
		BANISH_PORTALS_ID:
			_banish_portals()
		CONNECTION_ID:
			_open_connection()
		REMINDERS_ID:
			_open_reminders()


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
	context_menu.set_item_disabled(context_menu.get_item_index(FEED_ID), not stats.feeding_enabled)
	var can_summon := stats.feeding_enabled and active_food_items.size() < MAX_FOOD_ITEMS
	context_menu.set_item_disabled(context_menu.get_item_index(SUMMON_FOOD_ID), not can_summon)


func _summon_food() -> void:
	if active_food_items.size() >= MAX_FOOD_ITEMS:
		return

	var portal := FoodPortal.new()
	# A brand-new Window defaults to the primary screen regardless of where
	# Klippy actually is, so on a multi-monitor setup the portal would open
	# wherever screen 0 is rather than next to the pet.
	portal.current_screen = get_window().current_screen
	add_child(portal)
	portal.opened.connect(_on_food_portal_opened.bind(portal))


## Spawns the food only once the portal is actually open (see
## [signal FoodPortal.opened]), then repositions/launches it out of the
## portal's center instead of [method _spawn_food_body]'s normal
## next-to-Klippy default.
func _on_food_portal_opened(portal: FoodPortal) -> void:
	_spawn_food_body(FoodCatalog.APPLE)
	if active_food_items.is_empty():
		return

	var window: Window = active_food_items.back()
	var body := window.get_child(0) as FoodBody
	var portal_center := portal.position + Vector2i(portal.size) / 2
	window.position = portal_center - window.size / 2

	var angle := randf() * TAU
	body.velocity = Vector2(cos(angle), sin(angle)) * 220.0
	body.state = PetBody.State.THROWN


## Travel portals: a linked pair — blue here, red on the next monitor when
## there is one. Entering either portal exits the other.
func _summon_portals() -> void:
	if not travel_portals.is_empty():
		return
	var screens := maxi(DisplayServer.get_screen_count(), 1)
	var blue_screen := get_window().current_screen
	var red_screen := (blue_screen + 1) % screens if screens > 1 else blue_screen
	_spawn_portal("blue", blue_screen, 0.25)
	_spawn_portal("red", red_screen, 0.75)
	_update_portal_menu_items()


func _banish_portals() -> void:
	for portal in travel_portals:
		if is_instance_valid(portal):
			portal.queue_free()
	travel_portals.clear()
	blue_portal = null
	red_portal = null
	_update_portal_menu_items()


func _spawn_portal(kind: String, screen: int, x_fraction: float, y_fraction := 0.45) -> void:
	var portal := TravelPortal.new(kind)
	portal.current_screen = screen
	portal.probe = _pet_probe
	portal.entered.connect(_on_portal_entered.bind(portal))
	add_child(portal)
	var bounds := DisplayServer.screen_get_usable_rect(screen)
	var spot := Vector2(bounds.position) + Vector2(bounds.size.x * x_fraction, bounds.size.y * y_fraction)
	portal.place(Vector2i(spot))
	travel_portals.append(portal)
	if kind == "blue":
		blue_portal = portal
	elif kind == "red":
		red_portal = portal


func _update_portal_menu_items() -> void:
	var have_portals := not travel_portals.is_empty()
	context_menu.set_item_disabled(context_menu.get_item_index(SUMMON_PORTALS_ID), have_portals)
	var banish_index := context_menu.get_item_index(BANISH_PORTALS_ID)
	if have_portals:
		if banish_index == -1:
			context_menu.add_item("Banish Portals", BANISH_PORTALS_ID)
	elif banish_index != -1:
		context_menu.remove_item(banish_index)


## What the travel portals need to know about the pet each frame, in their
## own words — the pet stays in charge of how it moves.
func _pet_probe() -> Dictionary:
	var window := get_window()
	return {
		"thrown": state == State.THROWN,
		"center": Vector2(window.position) + Vector2(window.size) / 2.0,
		"radius": roll_radius,
		"velocity": velocity,
	}


## Emitted by the portal the pet just flew into (`rising`), or by one he is
## loitering inside (`rising == false`, the dropper case). His velocity
## carries over — direction included, capped for sanity — so he bursts out of
## the next portal in the chain the way he came in, offset far enough that it
## doesn't instantly re-catch him.
func _on_portal_entered(entry_velocity: Vector2, rising: bool, entered_portal: TravelPortal) -> void:
	var now := Time.get_unix_time_from_system()
	if not rising and now < _portal_chain_cooldown:
		return
	if travel_portals.size() < 2 or not is_instance_valid(entered_portal):
		return

	var index := travel_portals.find(entered_portal)
	var exit_portal: TravelPortal = travel_portals[(index + 1) % travel_portals.size()]
	if index == -1 or not is_instance_valid(exit_portal):
		return

	var exit_velocity := entry_velocity.limit_length(PORTAL_MAX_EXIT_SPEED)
	var direction := exit_velocity.normalized() if exit_velocity.length() > 1.0 \
			else Vector2.RIGHT.rotated(randf() * TAU)
	var window := get_window()
	window.current_screen = exit_portal.current_screen
	var exit_center := exit_portal.center()
	window.position = Vector2i(exit_center + direction * (exit_portal.radius() + roll_radius + 8.0)) \
			- Vector2i(window.size) / 2
	velocity = exit_velocity
	_portal_chain_cooldown = now + PORTAL_CHAIN_COOLDOWN


func _spawn_food_body(food_type: String) -> void:
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
		window.unfocusable = true
		var window_size := Vector2i(FOOD_WINDOW_SIZE, FOOD_WINDOW_SIZE)
		window.size = window_size
		window.content_scale_size = window_size

		body = FoodBody.new()
		body.position = Vector2(window_size) / 2.0
		body.roll_radius = FOOD_WINDOW_SIZE * 0.45

		var sprite2d := Sprite2D.new()
		body.add_child(sprite2d)
		window.add_child(body)

		add_child(window)
		body.consumed.connect(_on_food_item_consumed.bind(window))

	body.mass = FOOD_MASS
	body.stats = stats
	body.klippy_window = get_window()
	body.bag = food_bag
	body.contained_in = null
	# A pooled window's sprite still carries whatever food it last held, so this
	# has to be re-applied every spawn rather than only when the window is built.
	body.apply_food_type(food_type)
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


## Drops a food item at [param local_position] (relative to the bag window's
## top-left) and lets physics take it from there — whether it actually lands
## in the "stored" zone is discovered on the next physics tick, same as if a
## player had dropped it there by hand (see [method FoodBody._check_bag]).
func _spawn_contained_food(food_type: String, local_position: Vector2i) -> void:
	_spawn_food_body(food_type)
	if active_food_items.is_empty():
		return

	var window: Window = active_food_items.back()
	var bag_window := food_bag.get_window()
	window.position = bag_window.position + local_position


func _toggle_dvd_mode() -> void:
	_set_dvd_mode(not dvd_mode)


## Separate from the toggle so a remote command can say which state it wants rather
## than flipping whatever happens to be current.
func _set_dvd_mode(enabled: bool) -> void:
	if enabled == dvd_mode:
		return

	dvd_mode = enabled
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


func _process(delta: float) -> void:
	_update_pupils(delta)


## Point both pupils at the mouse. Reads the OS-level cursor position rather
## than [method Node2D.get_global_mouse_position] because most of Klippy's
## window is a mouse-passthrough region — the viewport's cached mouse position
## only updates on motion events the window actually receives, which is rare,
## so it would sit frozen and then jump. [method Node2D.to_local] then folds
## out the sprite's current scale/rotation, giving the mouse position in the
## same unrotated space the bounds below were traced in, regardless of whether
## Klippy is currently spinning from a drag or a throw.
func _update_pupils(delta: float) -> void:
	var window := get_window()
	var mouse_screen := Vector2(DisplayServer.mouse_get_position())
	var window_center := Vector2(window.position) + Vector2(window.size) / 2.0
	var activation_radius := current_size * PUPIL_ACTIVATION_RADIUS_SCALE

	# Outside the activation radius the pupils just relax back to their rest
	# position (a zero offset) via the same lerp used to track the mouse, so
	# there's no separate snap-back path to keep in sync with the tracking one.
	var wanted_left := Vector2.ZERO
	var wanted_right := Vector2.ZERO
	if mouse_screen.distance_to(window_center) <= activation_radius:
		var look_pos := sprite.to_local(mouse_screen - Vector2(window.position))
		wanted_left = look_pos - LEFT_PUPIL_REST
		wanted_right = look_pos - RIGHT_PUPIL_REST

	left_pupil.position = _follow_pupil(left_pupil.position, wanted_left, LEFT_PUPIL_BOUNDS, delta)
	right_pupil.position = _follow_pupil(right_pupil.position, wanted_right, RIGHT_PUPIL_BOUNDS, delta)


## [param bounds] holds the max reach per direction (left/up as its negative
## position, right/down as its end), not a box to clamp into directly — the
## eye white is oval, so a plain per-axis clampf would let the offset reach
## the box's corners, which sit outside the actual eye shape. Scaling back
## any offset that falls outside the quadrant's ellipse keeps the pupil
## inside the socket at every angle instead of just on the axes.
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
