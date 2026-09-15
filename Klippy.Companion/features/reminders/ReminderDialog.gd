class_name ReminderDialog
extends Window

## Where reminders are made, kept deliberately bare: a message and how many
## minutes from now it should fire. Pending reminders are listed underneath,
## each with a remove button, so there is one place to see what Klippy will
## nag about.

const DEFAULT_MINUTES := 10
const MAX_MINUTES := 7 * 24 * 60

var scheduler: ReminderScheduler
var message_edit: LineEdit
var minutes_spin: SpinBox
var pending_box: VBoxContainer


func _ready() -> void:
	title = "Reminders"
	size = Vector2i(340, 300)
	close_requested.connect(hide)


func setup(reminder_scheduler: ReminderScheduler) -> void:
	scheduler = reminder_scheduler
	_build()
	message_edit.grab_focus()
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
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	message_edit = LineEdit.new()
	message_edit.placeholder_text = "Remind me to..."
	message_edit.max_length = 80
	vbox.add_child(message_edit)

	var when_row := HBoxContainer.new()
	when_row.add_theme_constant_override("separation", 8)
	vbox.add_child(when_row)

	var in_label := Label.new()
	in_label.text = "in"
	when_row.add_child(in_label)

	minutes_spin = SpinBox.new()
	minutes_spin.min_value = 1
	minutes_spin.max_value = MAX_MINUTES
	minutes_spin.step = 1
	minutes_spin.value = DEFAULT_MINUTES
	minutes_spin.suffix = " min"
	minutes_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when_row.add_child(minutes_spin)

	var add_button := Button.new()
	add_button.text = "Remind me"
	add_button.pressed.connect(_on_add_pressed)
	when_row.add_child(add_button)

	vbox.add_child(HSeparator.new())

	var pending_title := Label.new()
	pending_title.text = "Pending"
	pending_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(pending_title)

	pending_box = VBoxContainer.new()
	pending_box.add_theme_constant_override("separation", 4)
	vbox.add_child(pending_box)


func _on_add_pressed() -> void:
	var message := message_edit.text.strip_edges()
	if message.is_empty():
		message = "Reminder"

	scheduler.add_reminder(message, Time.get_unix_time_from_system() + minutes_spin.value * 60.0)
	message_edit.clear()


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


func _format_due(reminder: Dictionary) -> String:
	var delta := maxf(float(reminder.get("due_at", 0.0)) - Time.get_unix_time_from_system(), 0.0)
	if delta < 60.0:
		return "now"
	if delta < 3600.0:
		return "in %dm" % int(delta / 60.0)
	if delta < 86400.0:
		return "in %dh %02dm" % [int(delta / 3600.0), int(fmod(delta, 3600.0) / 60.0)]
	return "in %dd %dh" % [int(delta / 86400.0), int(fmod(delta, 86400.0) / 3600.0)]
