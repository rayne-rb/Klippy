class_name SpeechBubble
extends Window

const DURATION := 2.5
const VERTICAL_GAP := 8

var anchor_window: Window
var label: Label
var hide_timer: Timer


func _ready() -> void:
	borderless = true
	transparent = true
	unfocusable = true
	always_on_top = true
	wrap_controls = true

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 0.88)
	style.border_color = Color(0.2, 0.2, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	panel.add_child(label)
	add_child(panel)

	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = DURATION
	hide_timer.timeout.connect(hide)
	add_child(hide_timer)

	hide()


func say(text: String, anchor: Window) -> void:
	anchor_window = anchor
	label.text = text
	show()
	hide_timer.start()
	call_deferred("_reposition")


func _process(_delta: float) -> void:
	if visible and anchor_window:
		_reposition()


func _reposition() -> void:
	position = anchor_window.position + Vector2i(
		anchor_window.size.x / 2 - size.x / 2,
		-size.y - VERTICAL_GAP
	)
