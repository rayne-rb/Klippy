class_name ReminderDialog
extends Window

## Where reminders are made, kept deliberately bare: a message and how many
## minutes from now it should fire. Styled as a bubble to match the one Klippy
## speaks in. Pending reminders are listed underneath, each with a remove
## button, so there is one place to see what Klippy will nag about.

const DEFAULT_MINUTES := 10
const MAX_MINUTES := 7 * 24 * 60

const BG_COLOR := Color("fff8e1")
const BORDER_COLOR := Color("3b3b3b")
const ACCENT_COLOR := Color("d9772a")
const FIELD_COLOR := Color("ffffff")
const FIELD_BORDER_COLOR := Color("e0d5b8")
const TEXT_COLOR := Color(0.08, 0.08, 0.08)
const MUTED_COLOR := Color(0.35, 0.35, 0.35, 0.8)

var scheduler: ReminderScheduler
var message_edit: LineEdit
var minutes_spin: SpinBox
var pending_box: VBoxContainer


func _ready() -> void:
	title = "Reminders"
	# No system chrome: the bubble is drawn by us, so the corners can be round.
	borderless = true
	transparent = true
	size = Vector2i(360, 302)
	close_requested.connect(hide)


func setup(reminder_scheduler: ReminderScheduler) -> void:
	scheduler = reminder_scheduler
	_build()
	message_edit.grab_focus()
	scheduler.reminders_changed.connect(_refresh_pending)
	_refresh_pending()


func _build() -> void:
	# Transparent margin around the panel gives the drop shadow room to breathe.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var panel := PanelContainer.new()
	var style := _bubble_style(BG_COLOR, BORDER_COLOR, 18, 0)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Reminders"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_button := Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.add_theme_color_override("font_color", MUTED_COLOR)
	close_button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	close_button.add_theme_stylebox_override("hover", _bubble_style(Color(0, 0, 0, 0.06), Color(0, 0, 0, 0), 8, 6))
	close_button.add_theme_stylebox_override("pressed", _bubble_style(Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 8, 6))
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)

	message_edit = LineEdit.new()
	message_edit.placeholder_text = "Remind me to..."
	message_edit.max_length = 80
	_style_field(message_edit)
	vbox.add_child(message_edit)

	var when_row := HBoxContainer.new()
	when_row.add_theme_constant_override("separation", 8)
	vbox.add_child(when_row)

	var in_label := Label.new()
	in_label.text = "in"
	in_label.add_theme_color_override("font_color", TEXT_COLOR)
	when_row.add_child(in_label)

	minutes_spin = SpinBox.new()
	minutes_spin.min_value = 1
	minutes_spin.max_value = MAX_MINUTES
	minutes_spin.step = 1
	minutes_spin.value = DEFAULT_MINUTES
	minutes_spin.suffix = " min"
	minutes_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_field(minutes_spin.get_line_edit())
	when_row.add_child(minutes_spin)

	var add_button := Button.new()
	add_button.text = "Remind me"
	add_button.focus_mode = Control.FOCUS_NONE
	add_button.add_theme_color_override("font_color", Color.WHITE)
	add_button.add_theme_color_override("font_hover_color", Color.WHITE)
	add_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	add_button.add_theme_stylebox_override("normal", _bubble_style(ACCENT_COLOR, Color(0, 0, 0, 0), 10, 10))
	add_button.add_theme_stylebox_override("hover", _bubble_style(ACCENT_COLOR.lightened(0.1), Color(0, 0, 0, 0), 10, 10))
	add_button.add_theme_stylebox_override("pressed", _bubble_style(ACCENT_COLOR.darkened(0.12), Color(0, 0, 0, 0), 10, 10))
	add_button.pressed.connect(_on_add_pressed)
	when_row.add_child(add_button)

	vbox.add_child(HSeparator.new())

	var pending_title := Label.new()
	pending_title.text = "Pending"
	pending_title.add_theme_font_size_override("font_size", 12)
	pending_title.add_theme_color_override("font_color", MUTED_COLOR)
	vbox.add_child(pending_title)

	pending_box = VBoxContainer.new()
	pending_box.add_theme_constant_override("separation", 4)
	vbox.add_child(pending_box)


## Rounded soft box shared by everything in the dialog; `pad` sets content
## margins, `0` border alpha drops the outline entirely.
func _bubble_style(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	if pad > 0:
		style.set_content_margin_all(pad)
	return style


## White rounded input look, shared by the message field and the spinner.
func _style_field(edit: LineEdit) -> void:
	edit.add_theme_color_override("font_color", TEXT_COLOR)
	edit.add_theme_stylebox_override("normal", _bubble_style(FIELD_COLOR, FIELD_BORDER_COLOR, 10, 8))
	edit.add_theme_stylebox_override("focus", _bubble_style(FIELD_COLOR, ACCENT_COLOR, 10, 8))


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
		empty.add_theme_color_override("font_color", MUTED_COLOR)
		pending_box.add_child(empty)
		return

	for reminder in scheduler.reminders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		pending_box.add_child(row)

		var entry := Label.new()
		entry.text = "%s — %s" % [_format_due(reminder), reminder.get("message", "")]
		entry.add_theme_font_size_override("font_size", 12)
		entry.add_theme_color_override("font_color", TEXT_COLOR)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(entry)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.focus_mode = Control.FOCUS_NONE
		remove_button.add_theme_font_size_override("font_size", 11)
		remove_button.add_theme_color_override("font_color", TEXT_COLOR)
		remove_button.add_theme_stylebox_override("normal", _bubble_style(FIELD_COLOR, FIELD_BORDER_COLOR, 8, 6))
		remove_button.add_theme_stylebox_override("hover", _bubble_style(Color(0.9, 0.55, 0.2, 0.25), FIELD_BORDER_COLOR, 8, 6))
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
