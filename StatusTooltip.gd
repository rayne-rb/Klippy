class_name StatusTooltip
extends Window

const VERTICAL_GAP := 8

var anchor_window: Window
var label: Label


func _ready() -> void:
	borderless = true
	transparent = true
	unfocusable = true
	always_on_top = true
	wrap_controls = true

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	label = Label.new()
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)
	add_child(panel)

	hide()


func show_status(text: String, anchor: Window) -> void:
	anchor_window = anchor
	set_text(text)
	show()


func hide_status() -> void:
	hide()


func set_text(text: String) -> void:
	label.text = text
	call_deferred("_reposition")


func _process(_delta: float) -> void:
	if visible and anchor_window:
		_reposition()


func _reposition() -> void:
	position = anchor_window.position + Vector2i(
		anchor_window.size.x / 2 - size.x / 2,
		-size.y - VERTICAL_GAP
	)
