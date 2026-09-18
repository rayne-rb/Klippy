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
const SUMMON_CONSUMABLE_ID := 7
const CONNECTION_ID := 8
const WARDROBE_ID := 9
const REMINDERS_ID := 10
const SUMMON_PORTALS_ID := 11
const BANISH_PORTALS_ID := 12
const SLEEP_ID := 13
const SKILLS_ID := 14
const MARKET_ID := 15
const SELL_PORTAL_ID := 16
const QUARRY_ID := 17
const FUN_ID := 18

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

const CONSUMABLE_WINDOW_SIZE := 60
const CONSUMABLE_MASS := 0.3
const MAX_CONSUMABLE_ITEMS := 8

# Jelly only turns up in the portal's random draw once Klippy has some levels
# on him (see [constant LevelUnlocks.JELLY_FOOD]), and even then rarely.
const JELLY_SPAWN_CHANCE := 0.05
const XP_GEM_SPAWN_CHANCE := 0.05
const COIN_SPAWN_CHANCE := 0.05

const HUNGRY_BOUNCE_AMPLITUDE := 28.0
const HUNGRY_BOUNCE_SPEED := 10.0
const HUNGRY_BOUNCES_PER_BURST := 5
const HUNGRY_BOUNCE_ENVELOPE_MIN_SCALE := 0.35
const HUNGRY_BURST_INTERVAL := 300.0
const VERY_HUNGRY_BURST_INTERVAL := 150.0

const WARDROBE_MENU_GAP := 8

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

# A hat sits well off the body's center, unlike every other cosmetic part
# (which stays within the body's own rotational silhouette) — rigidly
# attached and spinning with the body like everything else, its farthest
# point sweeps a bigger circle than the body's own radius as Klippy rotates.
# _apply_size() pads the window by this (scaled with current_size, same as
# roll_radius/mass) so that circle never exceeds the window bounds and clips.
# ~29px of padding (at the reference TEXTURE_SIZE scale) is the measured
# minimum for the current crown art; this leaves some headroom for it.
const HAT_SWING_MARGIN := 35.0

const PLAY_MIN_HEALTH := 60.0
const PLAY_DISTANCE_THRESHOLD := 400.0
const PLAY_MOOD_BOOST := 1.5
const PLAY_XP_REWARD := 0.1

## A sleeping Klippy wakes on either a hard-enough throw (checked where he
## enters [constant State.THROWN] and on every bounce) or being shaken while
## dragged: [constant SLEEP_WAKE_SHAKE_REVERSALS] fast direction reversals
## within a rolling [constant SLEEP_WAKE_SHAKE_WINDOW] window (see
## [method _on_drag_move]).
const SLEEP_WAKE_THROW_SPEED := 500.0
const SLEEP_WAKE_SHAKE_SPEED := 500.0
const SLEEP_WAKE_SHAKE_WINDOW := 0.6
const SLEEP_WAKE_SHAKE_REVERSALS := 3

var consumable_spawner: ConsumableSpawner

var active_consumable_items: Array[Window] = []
var consumable_window_pool: Array[Window] = []

var idle_base_y := 0
var bounce_timer := 0.0
var bouncing := false
var bounce_phase := 0.0
var bounce_cycles_done := 0

var play_tracking_active := false
var play_distance_traveled := 0.0

var _shake_prev_velocity := Vector2.ZERO
var _shake_reversal_count := 0
var _shake_window_timer := 0.0

var context_menu: PopupMenu
var quarry_menu: PopupMenu
var fun_menu: PopupMenu
var settings_window: SettingsPanel
var status_dialog: StatusDialog
var skills_dialog: SkillsDialog
var close_confirm_dialog: Window
var dev_tools_dialog: DevToolsDialog
var consumable_bag: ConsumableBagBody
var connection_dialog: PairingDialog
var reminder_dialog: ReminderDialog
var wardrobe: WardrobeBody
var wardrobe_dialog: WardrobeDialog

var remote_control: RemoteControl
var reminder_scheduler: ReminderScheduler

var blue_portal: TravelPortal
var red_portal: TravelPortal
var travel_portals: Array[TravelPortal] = []
var _portal_chain_cooldown := 0.0

var market_client: MarketClient
var market_mailbox: MarketMailbox
var market_dialog: MarketDialog
var sell_price_dialog: MarketSellDialog
var sell_portal: SellPortal
## Which consumable window is currently frozen in the sell portal awaiting a
## price decision, so the price dialog's confirm/cancel know which item to
## finish selling or hand back. Null whenever no sale is in progress.
var _pending_sale_window: Window

var detail: Sprite2D
var left_eye: Sprite2D
var right_eye: Sprite2D
var left_pupil: Sprite2D
var right_pupil: Sprite2D
var hat: Sprite2D

var current_body_id := BodyCatalog.DEFAULT
var current_expression_id := ExpressionCatalog.DEFAULT
var current_eyes_id := EyesCatalog.DEFAULT
var current_pupils_id := PupilsCatalog.DEFAULT
var current_hat_id := HatsCatalog.DEFAULT

var speech_bubble: SpeechBubble
var complaint_cooldown_timer: Timer
var stats: PetStats
var pet_level: PetLevel
var klippy_points: KlippyPoints

## Backs whatever consumable buff (jelly's bounciness, say) is currently active;
## [method _on_consumable_buff_expired] reverts everything it touched once it fires.
var consumable_buff_timer: Timer
var damage_immune := false
var bounce_xp_reward := 0.0
var bounce_mood_reward := 0.0

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
	detail = sprite.get_node(^"Detail") as Sprite2D
	left_eye = sprite.get_node(^"LeftEye") as Sprite2D
	right_eye = sprite.get_node(^"RightEye") as Sprite2D
	left_pupil = sprite.get_node(^"LeftPupil") as Sprite2D
	right_pupil = sprite.get_node(^"RightPupil") as Sprite2D
	hat = sprite.get_node(^"Hat") as Sprite2D
	_build_click_through_mask()
	_recompute_physical_properties()

	var save_data := SaveData.load_data()
	var klippy_data: Dictionary = save_data.get("klippy", {})
	var stats_data: Dictionary = save_data.get("stats", {})
	var settings_data: Dictionary = save_data.get("settings", {})
	var meta_data: Dictionary = save_data.get("meta", {})
	var consumable_bag_data: Dictionary = save_data.get("consumable_bag", {})
	var level_data: Dictionary = save_data.get("level", {})
	var points_data: Dictionary = save_data.get("klippy_points", {})
	var market_data: Dictionary = save_data.get("market", {})

	stats = PetStats.new()
	add_child(stats)
	stats.food = stats_data.get("food", PetStats.MAX_FOOD)
	stats.mood = stats_data.get("mood", PetStats.MOOD_MID)
	stats.health = stats_data.get("health", PetStats.MAX_HEALTH)
	stats.feeding_enabled = stats_data.get("feeding_enabled", false)
	stats.is_dead = stats_data.get("is_dead", false)
	stats.is_sleeping = stats_data.get("is_sleeping", false)
	if meta_data.has("saved_at"):
		var elapsed: float = Time.get_unix_time_from_system() - float(meta_data["saved_at"])
		stats.apply_offline_progress(elapsed)
	stats.feeding_enabled_changed.connect(_on_feeding_enabled_changed)

	pet_level = PetLevel.new()
	add_child(pet_level)
	pet_level.load_xp(level_data.get("xp", 0.0))

	klippy_points = KlippyPoints.new()
	add_child(klippy_points)
	klippy_points.load_points(int(points_data.get("points", 0)))

	market_client = MarketClient.new()
	add_child(market_client)

	market_mailbox = MarketMailbox.new()
	add_child(market_mailbox)
	market_mailbox.setup(klippy_points, market_data.get("applied_payouts", []), _save_state)

	consumable_spawner = ConsumableSpawner.new()
	add_child(consumable_spawner)
	consumable_spawner.setup(stats, self)
	consumable_spawner.availability_changed.connect(_update_feed_menu_state)

	# Lets the server and the phone drive the pet. Everything it can reach is
	# handed over explicitly here, so the pet keeps working with the link absent.
	remote_control = RemoteControl.new()
	add_child(remote_control)
	remote_control.setup(stats, consumable_spawner, _say, _set_dvd_mode)

	show_food_value = settings_data.get("show_food_value", false)
	show_mood_value = settings_data.get("show_mood_value", false)
	show_health_value = settings_data.get("show_health_value", false)
	monitor_border_wrap = settings_data.get("border_wrap", false)
	dev_tools_enabled = settings_data.get("dev_tools_enabled", false)
	vsync_enabled = settings_data.get("vsync_enabled", true)
	target_fps = settings_data.get("target_fps", 30)
	_apply_display_settings()

	quarry_menu = PopupMenu.new()
	quarry_menu.add_item("Connection", CONNECTION_ID)
	quarry_menu.add_item("Market", MARKET_ID)
	quarry_menu.add_check_item("Sell Portal", SELL_PORTAL_ID)
	quarry_menu.id_pressed.connect(_on_context_menu_id_pressed)
	RockyTheme.style_popup(quarry_menu)

	fun_menu = PopupMenu.new()
	fun_menu.add_item("Wardrobe", WARDROBE_ID)
	fun_menu.add_item("Summon Portals", SUMMON_PORTALS_ID)
	fun_menu.add_item("DVD", DVD_ID)
	fun_menu.id_pressed.connect(_on_context_menu_id_pressed)
	RockyTheme.style_popup(fun_menu)

	context_menu = PopupMenu.new()
	context_menu.add_item("Status", STATUS_ID)
	context_menu.add_check_item("Sleep", SLEEP_ID)
	context_menu.add_item("Summon Bag", FEED_ID)
	context_menu.add_item("Summon Consumable", SUMMON_CONSUMABLE_ID)
	context_menu.add_child(fun_menu)
	context_menu.add_submenu_node_item("Fun", fun_menu, FUN_ID)
	context_menu.add_child(quarry_menu)
	context_menu.add_submenu_node_item("Quarry", quarry_menu, QUARRY_ID)
	context_menu.add_item("Skills", SKILLS_ID)
	context_menu.add_item("Reminders", REMINDERS_ID)
	context_menu.add_item("Settings", SETTINGS_ID)
	context_menu.add_item("Close Klippy", CLOSE_ID)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	RockyTheme.style_popup(context_menu)
	add_child(context_menu)
	_on_feeding_enabled_changed(stats.feeding_enabled)
	stats.died.connect(_update_revive_item)
	stats.sleep_changed.connect(_on_sleep_changed)
	_update_sleep_menu_item(stats.is_sleeping)
	_update_revive_item()
	_update_dev_tools_item()

	# The market only means anything with somewhere to buy from and sell to.
	KlippyLink.state_changed.connect(_on_klippy_link_state_changed_for_market)
	_update_market_menu_state()

	_create_consumable_bag()
	_create_wardrobe()
	# The bag's art isn't a simple rectangle, so anywhere clever picked ahead
	# of time risks landing just outside it — dead center is the one point
	# guaranteed to be inside, and consumable-vs-consumable collision spreads the pile
	# back out over the following few ticks. They still need a tiny nudge
	# apart from each other first, though: exactly-coincident items have no
	# meaningful direction to push apart along, so left dead-on-top of one
	# another they'd just stay stacked forever.
	var bag_center := Vector2i(consumable_bag.get_window().size) / 2
	var jitter_index := 0
	for consumable_id in consumable_bag_data:
		var stored_count: int = int(consumable_bag_data[consumable_id])
		for i in stored_count:
			var jitter := Vector2(cos(jitter_index * 2.4), sin(jitter_index * 2.4)) * 5.0
			_spawn_contained_consumable(consumable_id, bag_center + Vector2i(jitter))
			jitter_index += 1

	var saved_size: int = klippy_data.get("size", current_size)
	if saved_size in SIZE_STEPS:
		_apply_size(saved_size)

	var saved_body_id: String = klippy_data.get("body_id", BodyCatalog.DEFAULT)
	current_body_id = saved_body_id if saved_body_id in BodyCatalog.ids() else BodyCatalog.DEFAULT
	var saved_expression_id: String = klippy_data.get("expression_id", ExpressionCatalog.DEFAULT)
	current_expression_id = saved_expression_id if saved_expression_id in ExpressionCatalog.ids() else ExpressionCatalog.DEFAULT
	var saved_eyes_id: String = klippy_data.get("eyes_id", EyesCatalog.DEFAULT)
	current_eyes_id = saved_eyes_id if saved_eyes_id in EyesCatalog.ids() else EyesCatalog.DEFAULT
	var saved_pupils_id: String = klippy_data.get("pupils_id", PupilsCatalog.DEFAULT)
	current_pupils_id = saved_pupils_id if saved_pupils_id in PupilsCatalog.ids() else PupilsCatalog.DEFAULT
	var saved_hat_id: String = klippy_data.get("hat_id", HatsCatalog.DEFAULT)
	current_hat_id = saved_hat_id if saved_hat_id in HatsCatalog.ids() else HatsCatalog.DEFAULT

	_apply_body(current_body_id)
	_apply_expression(current_expression_id)
	_apply_eyes(current_eyes_id)
	_apply_pupils(current_pupils_id)
	_apply_hat(current_hat_id)

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

	consumable_buff_timer = Timer.new()
	consumable_buff_timer.one_shot = true
	consumable_buff_timer.timeout.connect(_on_consumable_buff_expired)
	add_child(consumable_buff_timer)

	get_window().close_requested.connect(_on_quit_requested)


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
		status_dialog.setup(stats, pet_level, klippy_points)
		status_dialog.set_show_food_value(show_food_value)
		status_dialog.set_show_mood_value(show_mood_value)
		status_dialog.set_show_health_value(show_health_value)
		status_dialog.close_requested.connect(_on_status_closed)
	status_dialog.popup_centered()


func _on_status_closed() -> void:
	status_dialog.queue_free()
	status_dialog = null


func _open_skills() -> void:
	if skills_dialog == null:
		skills_dialog = SkillsDialog.new()
		add_child(skills_dialog)
		skills_dialog.close_requested.connect(_on_skills_closed)
	skills_dialog.popup_centered()


func _on_skills_closed() -> void:
	skills_dialog.queue_free()
	skills_dialog = null


func _open_dev_tools() -> void:
	if dev_tools_dialog == null:
		dev_tools_dialog = DevToolsDialog.new()
		add_child(dev_tools_dialog)
		dev_tools_dialog.setup(stats, pet_level, klippy_points)
		dev_tools_dialog.bounce_triggered.connect(trigger_bounce_now)
		dev_tools_dialog.close_requested.connect(_on_dev_tools_closed)
	dev_tools_dialog.popup_centered()


func _on_dev_tools_closed() -> void:
	dev_tools_dialog.queue_free()
	dev_tools_dialog = null


func _create_consumable_bag() -> void:
	var window := Window.new()
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	window.unfocusable = true

	var art_scale := ConsumableBagBody.TARGET_HEIGHT / ConsumableBagBody.BACK_TEXTURE.get_size().y
	var visual_size := Vector2(ConsumableBagBody.BACK_TEXTURE.get_size()) * art_scale
	var window_size := Vector2i(visual_size) + Vector2i.ONE * (ConsumableBagBody.WINDOW_MARGIN * 2)
	window.size = window_size
	window.content_scale_size = window_size

	var body := ConsumableBagBody.new()
	body.position = Vector2(window_size) / 2.0
	body.roll_radius = minf(visual_size.x, visual_size.y) * 0.45
	body.klippy = self
	window.add_child(body)

	add_child(window)

	var klippy_window := get_window()
	window.position = klippy_window.position + Vector2i(-window_size.x - 10, 0)
	window.visible = false

	body.grabbed.connect(_raise_contained_consumables)
	consumable_bag = body


func _toggle_consumable_bag() -> void:
	var window := consumable_bag.get_window()
	if window.visible:
		window.hide()
	else:
		window.show()
		_raise_contained_consumables()


func _create_wardrobe() -> void:
	var window := Window.new()
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	window.unfocusable = true

	var art_scale := WardrobeBody.TARGET_HEIGHT / WardrobeBody.TEXTURE.get_size().y
	var visual_size := Vector2(WardrobeBody.TEXTURE.get_size()) * art_scale
	var window_size := Vector2i(visual_size) + Vector2i.ONE * (WardrobeBody.WINDOW_MARGIN * 2)
	window.size = window_size
	window.content_scale_size = window_size

	var body := WardrobeBody.new()
	body.position = Vector2(window_size) / 2.0
	body.roll_radius = minf(visual_size.x, visual_size.y) * 0.45
	body.klippy = self
	window.add_child(body)

	add_child(window)

	var klippy_window := get_window()
	# Above-and-left of Klippy, distinct from the consumable bag's position (directly
	# left, same y) so the two spawnable props don't stack on top of each other.
	window.position = klippy_window.position + Vector2i(-window_size.x - 10, -window_size.y - 10)
	window.visible = false

	body.opened.connect(_open_cosmetic_picker)
	wardrobe = body


func _toggle_wardrobe() -> void:
	var window := wardrobe.get_window()
	if window.visible:
		window.hide()
		if wardrobe_dialog:
			wardrobe_dialog.close_all()
	else:
		window.show()


func _apply_body(id: String) -> void:
	sprite.texture = BodyCatalog.get_def(id).texture
	current_body_id = id
	_build_click_through_mask()


func _apply_expression(id: String) -> void:
	detail.texture = ExpressionCatalog.get_def(id).texture
	current_expression_id = id


func _apply_eyes(id: String) -> void:
	var def := EyesCatalog.get_def(id)
	left_eye.texture = def.texture
	right_eye.texture = def.right_texture
	current_eyes_id = id


func _apply_pupils(id: String) -> void:
	var def := PupilsCatalog.get_def(id)
	left_pupil.texture = def.texture
	right_pupil.texture = def.right_texture
	current_pupils_id = id


func _apply_hat(id: String) -> void:
	hat.texture = HatsCatalog.get_def(id).texture
	current_hat_id = id


func _open_cosmetic_picker() -> void:
	if wardrobe_dialog == null:
		wardrobe_dialog = WardrobeDialog.new()
		add_child(wardrobe_dialog)
		wardrobe_dialog.body_selected.connect(_apply_body)
		wardrobe_dialog.expression_selected.connect(_apply_expression)
		wardrobe_dialog.eyes_selected.connect(_apply_eyes)
		wardrobe_dialog.pupils_selected.connect(_apply_pupils)
		wardrobe_dialog.hat_selected.connect(_apply_hat)
	wardrobe_dialog.setup({
		"body": current_body_id,
		"expression": current_expression_id,
		"eyes": current_eyes_id,
		"pupils": current_pupils_id,
		"hat": current_hat_id,
	}, pet_level)
	wardrobe_dialog.popup()
	call_deferred("_reposition_wardrobe_dialog")


func _reposition_wardrobe_dialog() -> void:
	var anchor := wardrobe.get_window()
	wardrobe_dialog.position = anchor.position + Vector2i(
		anchor.size.x / 2 - wardrobe_dialog.size.x / 2,
		-wardrobe_dialog.size.y - WARDROBE_MENU_GAP
	)


func _raise_contained_consumables() -> void:
	for window in active_consumable_items:
		var body := window.get_child(0) as ConsumableBody
		if body.contained_in == consumable_bag:
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
	for window in active_consumable_items:
		var body := window.get_child(0) as ConsumableBody
		if body.contained_in == consumable_bag:
			contained_counts[body.consumable_type] = contained_counts.get(body.consumable_type, 0) + 1

	SaveData.save_data({
		"klippy": {
			"size": current_size,
			"body_id": current_body_id,
			"expression_id": current_expression_id,
			"eyes_id": current_eyes_id,
			"pupils_id": current_pupils_id,
			"hat_id": current_hat_id,
		},
		"stats": {
			"food": stats.food,
			"mood": stats.mood,
			"health": stats.health,
			"feeding_enabled": stats.feeding_enabled,
			"is_dead": stats.is_dead,
			"is_sleeping": stats.is_sleeping,
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
		"consumable_bag": contained_counts,
		"reminders": reminder_scheduler.to_save_data(),
		"level": {"xp": pet_level.xp},
		"klippy_points": {"points": klippy_points.points},
		"market": {"applied_payouts": market_mailbox.to_save_data()},
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
		SKILLS_ID:
			_open_skills()
		DVD_ID:
			_toggle_dvd_mode()
		FEED_ID:
			_toggle_consumable_bag()
		REVIVE_ID:
			stats.revive()
			_update_revive_item()
		DEV_TOOLS_ID:
			_open_dev_tools()
		SUMMON_CONSUMABLE_ID:
			_summon_consumable()
		SUMMON_PORTALS_ID:
			_summon_portals()
		BANISH_PORTALS_ID:
			_banish_portals()
		MARKET_ID:
			_open_market()
		SELL_PORTAL_ID:
			_toggle_sell_portal()
		CONNECTION_ID:
			_open_connection()
		WARDROBE_ID:
			_toggle_wardrobe()
		REMINDERS_ID:
			_open_reminders()
		SLEEP_ID:
			_toggle_sleep()


func _update_revive_item() -> void:
	var index := context_menu.get_item_index(REVIVE_ID)
	if stats.is_dead:
		if index == -1:
			context_menu.add_item("Revive", REVIVE_ID)
	elif index != -1:
		context_menu.remove_item(index)


func _toggle_sleep() -> void:
	stats.set_sleeping(not stats.is_sleeping)


## Only reached via the [signal PetStats.sleep_changed] signal, never the
## ready-time sync (see [method _update_sleep_menu_item]) — so this always
## speaks for a real transition, not just loading a save that was left asleep.
func _on_sleep_changed(sleeping: bool) -> void:
	_update_sleep_menu_item(sleeping)
	_say("Zzz..." if sleeping else Dialogue.random_wake_up())


func _update_sleep_menu_item(sleeping: bool) -> void:
	context_menu.set_item_checked(context_menu.get_item_index(SLEEP_ID), sleeping)


## Only called while actually sleeping (both wake paths check first), so this
## always represents a real wake rather than a no-op toggle.
func _wake_up() -> void:
	stats.set_sleeping(false)


func _on_feeding_enabled_changed(_enabled: bool) -> void:
	_update_feed_menu_state()


func _update_feed_menu_state() -> void:
	context_menu.set_item_disabled(context_menu.get_item_index(FEED_ID), not stats.feeding_enabled)
	var can_summon := stats.feeding_enabled and active_consumable_items.size() < MAX_CONSUMABLE_ITEMS
	context_menu.set_item_disabled(context_menu.get_item_index(SUMMON_CONSUMABLE_ID), not can_summon)


func _summon_consumable() -> void:
	_open_consumable_portal(_roll_summon_consumable_type)


## A bought item is already paid for by the time this is called (see
## [signal MarketDialog.item_purchased]), so it bypasses [constant
## MAX_CONSUMABLE_ITEMS] rather than risk vanishing a purchase the desktop
## happened to be too full to hold.
func _on_market_item_purchased(item_type: String) -> void:
	_open_consumable_portal(func() -> String: return item_type, true)


func _open_consumable_portal(type_provider: Callable, bypass_cap := false) -> void:
	if not bypass_cap and active_consumable_items.size() >= MAX_CONSUMABLE_ITEMS:
		return

	var portal := ConsumablePortal.new()
	# A brand-new Window defaults to the primary screen regardless of where
	# Klippy actually is, so on a multi-monitor setup the portal would open
	# wherever screen 0 is rather than next to the pet.
	portal.current_screen = get_window().current_screen
	add_child(portal)
	portal.opened.connect(_on_consumable_portal_opened.bind(portal, type_provider, bypass_cap))


## Spawns the consumable only once the portal is actually open (see
## [signal ConsumablePortal.opened]), then repositions/launches it out of the
## portal's center instead of [method _spawn_consumable_body]'s normal
## next-to-Klippy default.
func _on_consumable_portal_opened(portal: ConsumablePortal, type_provider: Callable, bypass_cap: bool) -> void:
	_spawn_consumable_body(type_provider.call(), bypass_cap)
	if active_consumable_items.is_empty():
		return

	var window: Window = active_consumable_items.back()
	var body := window.get_child(0) as ConsumableBody
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
	var blue_screen := get_window().current_screen
	var red_screen := blue_screen
	if DisplayServer.get_screen_count() > 1:
		var across := neighbor_screen_across(blue_screen, 1)
		if across == -1:
			across = neighbor_screen_across(blue_screen, -1)
		if across == -1:
			across = (blue_screen + 1) % DisplayServer.get_screen_count()
		red_screen = across
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
	fun_menu.set_item_disabled(fun_menu.get_item_index(SUMMON_PORTALS_ID), have_portals)
	var banish_index := fun_menu.get_item_index(BANISH_PORTALS_ID)
	if have_portals:
		if banish_index == -1:
			fun_menu.add_item("Banish Portals", BANISH_PORTALS_ID)
	elif banish_index != -1:
		fun_menu.remove_item(banish_index)


# --- Market --------------------------------------------------------------------

func _open_market() -> void:
	if market_dialog == null:
		market_dialog = MarketDialog.new()
		add_child(market_dialog)
		market_dialog.setup(market_client, klippy_points)
		market_dialog.item_purchased.connect(_on_market_item_purchased)
		market_dialog.close_requested.connect(_on_market_closed)
	market_dialog.popup_centered()
	market_dialog.refresh()


func _on_market_closed() -> void:
	market_dialog.queue_free()
	market_dialog = null


func _toggle_sell_portal() -> void:
	if sell_portal != null:
		_banish_sell_portal()
	else:
		_open_sell_portal()


func _open_sell_portal() -> void:
	sell_portal = SellPortal.new()
	sell_portal.current_screen = get_window().current_screen
	add_child(sell_portal)

	var bounds := DisplayServer.screen_get_usable_rect(sell_portal.current_screen)
	var spot := Vector2(bounds.position) + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.75)
	sell_portal.place(Vector2i(spot))

	_apply_sell_portal_to_active_items()
	quarry_menu.set_item_checked(quarry_menu.get_item_index(SELL_PORTAL_ID), true)


func _banish_sell_portal() -> void:
	if sell_portal == null:
		return

	if is_instance_valid(sell_portal):
		sell_portal.queue_free()
	sell_portal = null

	_apply_sell_portal_to_active_items()
	quarry_menu.set_item_checked(quarry_menu.get_item_index(SELL_PORTAL_ID), false)


## Keeps every already-spawned item in step with whichever sell portal is
## current, the same way [member ConsumableBody.bag] is pushed in rather than
## looked up — an item dropped before the portal opened still needs to become
## sellable the moment it does.
func _apply_sell_portal_to_active_items() -> void:
	for window in active_consumable_items:
		var body := window.get_child(0) as ConsumableBody
		body.sell_portal = sell_portal


func _on_klippy_link_state_changed_for_market(state: KlippyLink.State) -> void:
	_update_market_menu_state()
	# A sale needs the server on the other end of it, so a portal left open
	# through a disconnect would just be a promise nothing can keep.
	if state != KlippyLink.State.CONNECTED:
		_banish_sell_portal()


func _update_market_menu_state() -> void:
	var connected := KlippyLink.is_connected_to_server()
	quarry_menu.set_item_disabled(quarry_menu.get_item_index(MARKET_ID), not connected)
	quarry_menu.set_item_disabled(quarry_menu.get_item_index(SELL_PORTAL_ID), not connected)


## Fired by the item itself once it has drifted into the sell portal (see
## [signal ConsumableBody.sell_requested]). Freezes it in place rather than
## removing it yet, so a cancelled sale or a failed listing call can just hand
## it back.
func _on_consumable_sell_requested(window: Window) -> void:
	if sell_price_dialog == null:
		sell_price_dialog = MarketSellDialog.new()
		add_child(sell_price_dialog)
		sell_price_dialog.confirmed.connect(_on_sell_price_confirmed)
		sell_price_dialog.cancelled.connect(_on_sell_cancelled)

	var body := window.get_child(0) as ConsumableBody
	body.velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.set_physics_process(false)

	_pending_sale_window = window
	sell_price_dialog.open_for(ConsumableCatalog.get_def(body.consumable_type).display_name)


func _on_sell_price_confirmed(price: int) -> void:
	if _pending_sale_window == null:
		return
	var body := _pending_sale_window.get_child(0) as ConsumableBody
	market_client.sell(body.consumable_type, price, _on_sell_response)


func _on_sell_response(ok: bool, error: String) -> void:
	if ok:
		sell_price_dialog.hide()
		_finish_sale()
	else:
		sell_price_dialog.show_error(error)
		_return_pending_sale_item()


## The item actually leaves the desktop: pooled exactly like a normal
## consumption, minus any of the eating rewards — this was a sale, not a meal.
func _finish_sale() -> void:
	var window := _pending_sale_window
	_pending_sale_window = null
	if window == null or not is_instance_valid(window):
		return
	_retire_consumable_window(window)


## The listing call failed, or the user cancelled: give the item back rather
## than lose it, bounced out of the portal the same way a bought item bursts
## out of one.
func _return_pending_sale_item() -> void:
	var window := _pending_sale_window
	_pending_sale_window = null
	if window == null or not is_instance_valid(window):
		return

	var body := window.get_child(0) as ConsumableBody
	body.pending_sale = false
	body.set_physics_process(true)

	if sell_portal != null:
		var angle := randf() * TAU
		body.velocity = Vector2(cos(angle), sin(angle)) * 220.0
		body.state = PetBody.State.THROWN


func _on_sell_cancelled() -> void:
	_return_pending_sale_item()


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


## What the portal drops: almost always an apple, but a rare jelly once
## Klippy is levelled enough (see [constant LevelUnlocks.JELLY_FOOD]), and
## separately-rolled rare XP gems and coins regardless of level.
func _roll_summon_consumable_type() -> String:
	if pet_level.is_unlocked(LevelUnlocks.JELLY_FOOD) and randf() < JELLY_SPAWN_CHANCE:
		return ConsumableCatalog.JELLY
	if randf() < XP_GEM_SPAWN_CHANCE:
		return ConsumableCatalog.XP_GEM
	if randf() < COIN_SPAWN_CHANCE:
		return ConsumableCatalog.COIN
	return ConsumableCatalog.APPLE


func _spawn_consumable_body(consumable_type: String, force := false) -> void:
	if not force and active_consumable_items.size() >= MAX_CONSUMABLE_ITEMS:
		return

	var window: Window
	var body: ConsumableBody

	if not consumable_window_pool.is_empty():
		window = consumable_window_pool.pop_back()
		body = window.get_child(0) as ConsumableBody
	else:
		window = Window.new()
		window.borderless = true
		window.transparent = true
		window.always_on_top = true
		window.unfocusable = true
		var window_size := Vector2i(CONSUMABLE_WINDOW_SIZE, CONSUMABLE_WINDOW_SIZE)
		window.size = window_size
		window.content_scale_size = window_size

		body = ConsumableBody.new()
		body.position = Vector2(window_size) / 2.0
		body.roll_radius = CONSUMABLE_WINDOW_SIZE * 0.45

		var sprite2d := Sprite2D.new()
		body.add_child(sprite2d)
		window.add_child(body)

		add_child(window)
		body.consumed.connect(_on_consumable_item_consumed.bind(window))
		body.sell_requested.connect(_on_consumable_sell_requested.bind(window))

	body.mass = CONSUMABLE_MASS
	body.stats = stats
	body.klippy = self
	body.bag = consumable_bag
	body.contained_in = null
	body.sell_portal = sell_portal
	body.pending_sale = false
	# A pooled window's sprite still carries whatever consumable it last held, so this
	# has to be re-applied every spawn rather than only when the window is built.
	body.apply_consumable_type(consumable_type)
	body.velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.drag_spin_target = 0.0
	body.state = PetBody.State.IDLE
	body.sprite.rotation = 0.0
	body.set_physics_process(true)

	var klippy_window := get_window()
	window.position = klippy_window.position + Vector2i(klippy_window.size.x + 10, 0)
	window.show()

	active_consumable_items.append(window)
	_update_feed_menu_state()


func _on_consumable_item_consumed(window: Window) -> void:
	var body := window.get_child(0) as ConsumableBody
	var def := ConsumableCatalog.get_def(body.consumable_type)
	if def.xp_reward > 0.0:
		pet_level.add_xp(def.xp_reward)
	if def.points_reward > 0:
		klippy_points.add_points(def.points_reward)
	_apply_consumable_buff(def)
	_retire_consumable_window(window)


## Takes a consumable window off the desktop and back into the pool, shared by
## eating (see [method _on_consumable_item_consumed]) and selling (see [method
## _finish_sale]) — everything past "this item is done" is identical between
## the two, they just disagree on what "done" earns.
func _retire_consumable_window(window: Window) -> void:
	var body := window.get_child(0) as ConsumableBody
	body.set_physics_process(false)
	body.pending_sale = false
	window.hide()
	active_consumable_items.erase(window)
	if consumable_window_pool.size() < MAX_CONSUMABLE_ITEMS:
		consumable_window_pool.append(window)
	else:
		window.queue_free()
	_update_feed_menu_state()


## Starts (or refreshes, if one is already running) whatever timed buff
## [param def] carries. A consumable with no [member ConsumableDef.buff_duration] leaves
## Klippy untouched.
func _apply_consumable_buff(def: ConsumableDef) -> void:
	if def.buff_duration <= 0.0:
		return

	if def.bounce_damping_override >= 0.0:
		bounce_damping = def.bounce_damping_override
	damage_immune = def.damage_immune
	bounce_xp_reward = def.bounce_xp_reward
	bounce_mood_reward = def.bounce_mood_reward
	consumable_buff_timer.start(def.buff_duration)


func _on_consumable_buff_expired() -> void:
	bounce_damping = BOUNCE_DAMPING
	damage_immune = false
	bounce_xp_reward = 0.0
	bounce_mood_reward = 0.0


## Drops a consumable item at [param local_position] (relative to the bag window's
## top-left) and lets physics take it from there — whether it actually lands
## in the "stored" zone is discovered on the next physics tick, same as if a
## player had dropped it there by hand (see [method ConsumableBody._check_bag]).
func _spawn_contained_consumable(consumable_type: String, local_position: Vector2i) -> void:
	_spawn_consumable_body(consumable_type)
	if active_consumable_items.is_empty():
		return

	var window: Window = active_consumable_items.back()
	var bag_window := consumable_bag.get_window()
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
	# Padding is invisible (nothing is drawn out there normally) and kept out
	# of current_size/roll_radius/mass entirely — it exists purely so a worn
	# hat has room to swing through without the window clipping it.
	var margin := int(round(HAT_SWING_MARGIN * (new_size / TEXTURE_SIZE)))
	var window_size_v := new_size_v + Vector2i.ONE * (margin * 2)

	window.content_scale_size = window_size_v
	window.size = window_size_v
	window.position = Vector2i(old_center - Vector2(window_size_v) / 2.0)

	sprite.scale = Vector2.ONE * (new_size / TEXTURE_SIZE)
	position = Vector2(window_size_v) / 2.0
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
	if not stats.is_dead and not stats.is_sleeping:
		pet_level.apply_passive_gain(delta, stats.get_mood_status() == "Ecstatic")


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


## Shake-to-wake: counts fast reversals in drag direction, since a shake looks
## like velocity repeatedly flipping sign rather than a single hard flick.
## [member _shake_window_timer] ages the count out so slow, deliberate
## dragging never accumulates into an accidental wake.
func _on_drag_move(velocity: Vector2, delta: float) -> void:
	if not stats.is_sleeping:
		return

	_shake_window_timer -= delta
	if _shake_window_timer <= 0.0:
		_shake_reversal_count = 0

	if velocity.length() >= SLEEP_WAKE_SHAKE_SPEED and _shake_prev_velocity.dot(velocity) < 0.0:
		_shake_reversal_count += 1
		_shake_window_timer = SLEEP_WAKE_SHAKE_WINDOW
		if _shake_reversal_count >= SLEEP_WAKE_SHAKE_REVERSALS:
			_shake_reversal_count = 0
			_wake_up()

	_shake_prev_velocity = velocity


func _on_energetic_bounce(impact_speed: float) -> void:
	if stats.is_sleeping and impact_speed >= SLEEP_WAKE_THROW_SPEED:
		_wake_up()
	if impact_speed >= DAMAGE_SPEED_THRESHOLD and not damage_immune:
		stats.apply_throw_damage()
	if bounce_xp_reward > 0.0:
		pet_level.add_xp(bounce_xp_reward)
	if bounce_mood_reward > 0.0:
		stats.apply_play_boost(bounce_mood_reward)
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
		if stats.is_sleeping and velocity.length() >= SLEEP_WAKE_THROW_SPEED:
			_wake_up()


func _on_state_exit(old_state: State) -> void:
	if old_state != State.THROWN or not play_tracking_active:
		return

	play_tracking_active = false
	if play_distance_traveled >= PLAY_DISTANCE_THRESHOLD and stats.health > PLAY_MIN_HEALTH:
		stats.apply_play_boost(PLAY_MOOD_BOOST)
		pet_level.add_xp(PLAY_XP_REWARD)


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
	var rest_bounds := _screen_rest_bounds(window)
	var pos := Vector2(window.position) + velocity * delta

	var min_x := rest_bounds.position.x
	var max_x := rest_bounds.end.x
	var min_y := rest_bounds.position.y
	var max_y := rest_bounds.end.y

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
