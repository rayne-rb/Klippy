class_name ReminderDialog
extends Window

## Where reminders are made. A message plus a datetime — the fields start out
## ten minutes from now, and the quick buttons rewrite the time fields relative
## to now for the common cases. Pending reminders are listed underneath, each
## with a remove button, so there is one place to see what Klippy will nag
## about.

const DEFAULT_AHEAD_MINUTES := 10

const QUICK_OPTIONS := [
	{"label": "+1 min", "seconds": 60},
	{"label": "+5 min", "seconds": 300},
	{"label": "+30 min", "seconds": 1800},
	{"label": "+1 h", "seconds": 3600},
]

var scheduler: ReminderScheduler
var message_edit: LineEdit
var day_spin: SpinBox
var month_spin: SpinBox
var year_spin: SpinBox
var hour_spin: SpinBox
var minute_spin: SpinBox
var second_spin: SpinBox
var warning_label: Label
var pending_box: VBoxContainer


func _ready() -> void:
	title = "Reminders"
	size = Vector2i(370, 470)
	close_requested.connect(hide)


func setup(reminder_scheduler: ReminderScheduler) -> void:
	scheduler = reminder_scheduler
	_build()
	_reset_fields_to_now(DEFAULT_AHEAD_MINUTES * 60)
	scheduler.reminders_changed.connect(_refresh_pending)
	_refresh_pending()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	message_edit = LineEdit.new()
	message_edit.placeholder_text = "Stand up and stretch!"
	message_edit.max_length = 80
	vbox.add_child(message_edit)

	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 8)
	vbox.add_child(date_row)
	day_spin = _add_field(date_row, "Day", 1, 31)
	month_spin = _add_field(date_row, "Month", 1, 12)
	year_spin = _add_field(date_row, "Year", Time.get_date_dict_from_system().year, Time.get_date_dict_from_system().year + 10)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	vbox.add_child(time_row)
	hour_spin = _add_field(time_row, "Hour", 0, 23)
	minute_spin = _add_field(time_row, "Minute", 0, 59)
	second_spin = _add_field(time_row, "Second", 0, 59)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	vbox.add_child(quick_row)
	for option in QUICK_OPTIONS:
		var button := Button.new()
		button.text = option.label
		button.pressed.connect(_on_quick_pressed.bind(float(option.seconds)))
		quick_row.add_child(button)

	var add_button := Button.new()
	add_button.text = "Add Reminder"
	add_button.pressed.connect(_on_add_pressed)
	vbox.add_child(add_button)

	warning_label = Label.new()
	warning_label.add_theme_font_size_override("font_size", 11)
	warning_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.1))
	warning_label.hide()
	vbox.add_child(warning_label)

	vbox.add_child(HSeparator.new())

	var pending_title := Label.new()
	pending_title.text = "Pending"
	pending_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(pending_title)

	pending_box = VBoxContainer.new()
	pending_box.add_theme_constant_override("separation", 4)
	vbox.add_child(pending_box)


func _add_field(row: HBoxContainer, label_text: String, min_value: int, max_value: int) -> SpinBox:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	column.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.custom_minimum_size = Vector2(70, 0)
	column.add_child(spin)
	return spin


func _on_quick_pressed(seconds: float) -> void:
	_reset_fields_to_now(seconds)


func _on_add_pressed() -> void:
	var message := message_edit.text.strip_edges()
	if message.is_empty():
		message = "Reminder"

	var due_at := _selected_unix()
	if due_at <= Time.get_unix_time_from_system():
		warning_label.text = "That time already passed — pick one in the future."
		warning_label.show()
		return

	warning_label.hide()
	scheduler.add_reminder(message, due_at)
	message_edit.text = ""
	_reset_fields_to_now(DEFAULT_AHEAD_MINUTES * 60)


func _refresh_pending() -> void:
	if pending_box == null:
		return

	for child in pending_box.get_children():
		pending_box.remove_child(child)
		child.queue_free()

	if scheduler.reminders.is_empty():
		var empty := Label.new()
		empty.text = "Nothing scheduled."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		pending_box.add_child(empty)
		return

	for reminder in scheduler.reminders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		pending_box.add_child(row)

		var entry := Label.new()
		entry.text = "%s — %s" % [_format_due(reminder), reminder.get("message", "")]
		entry.add_theme_font_size_override("font_size", 12)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(entry)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(scheduler.remove_reminder.bind(int(reminder.get("id", -1))))
		row.add_child(remove_button)


## Reads the date/time fields as the user's local wall clock and converts that
## to a unix timestamp (the Time helpers round-trip through UTC, so the local
## offset has to be added and subtracted by hand).
func _selected_unix() -> float:
	var as_utc := Time.get_unix_time_from_datetime_dict({
		"year": int(year_spin.value),
		"month": int(month_spin.value),
		"day": int(day_spin.value),
		"hour": int(hour_spin.value),
		"minute": int(minute_spin.value),
		"second": int(second_spin.value),
	})
	return as_utc - float(_utc_offset_minutes()) * 60.0


func _reset_fields_to_now(ahead_seconds: float) -> void:
	var local := _local_dict(Time.get_unix_time_from_system() + ahead_seconds)
	day_spin.value = local.day
	month_spin.value = local.month
	year_spin.value = local.year
	hour_spin.value = local.hour
	minute_spin.value = local.minute
	second_spin.value = local.second


func _local_dict(unix_time: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(unix_time) + int(_utc_offset_minutes()) * 60)


func _format_due(reminder: Dictionary) -> String:
	var due_at := float(reminder.get("due_at", 0.0))
	var delta := due_at - Time.get_unix_time_from_system()
	var local := _local_dict(due_at)

	var relative: String
	if delta < 60.0:
		relative = "now"
	elif delta < 3600.0:
		relative = "in %dm" % int(delta / 60.0)
	elif delta < 86400.0:
		relative = "in %dh %02dm" % [int(delta / 3600.0), int(fmod(delta, 3600.0) / 60.0)]
	else:
		relative = "in %dd %dh" % [int(delta / 86400.0), int(fmod(delta, 86400.0) / 3600.0)]

	var today := Time.get_date_dict_from_system()
	var is_today := int(local.year) == int(today.year) and int(local.month) == int(today.month) and int(local.day) == int(today.day)
	if is_today:
		return "%s (%02d:%02d)" % [relative, local.hour, local.minute]
	return "%s (%04d-%02d-%02d %02d:%02d)" % [
		relative, local.year, local.month, local.day, local.hour, local.minute,
	]


## The engine's time helpers round-trip through UTC, so the local offset —
## minutes east of UTC, DST included — has to be added and subtracted by hand.
func _utc_offset_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))
