class_name SpeechBubble
extends Window

## The balloon above Klippy's head.
##
## Two ways to speak:
##   - [method say]: a passing remark that fades away on its own after a moment.
##   - [method announce_reminder]: a reminder, which stays on screen until the
##     user clicks it, poking them again every
##     [constant REMINDER_REPEAT_INTERVAL] until they do.

signal dismissed

const SAY_DURATION := 2.5
const REMINDER_REPEAT_INTERVAL := 8.0
const VERTICAL_GAP := 8

const TAIL_HEIGHT := 12.0
const TAIL_WIDTH := 9.0
const TAIL_OVERLAP := 3.0

const REMINDER_MIN_WIDTH := 230.0

const BG_COLOR := Color("fff8e1")
const BORDER_COLOR := Color("3b3b3b")
const ACCENT_COLOR := Color("d9772a")
const MESSAGE_COLOR := Color(0.08, 0.08, 0.08)
const HINT_COLOR := Color(0.2, 0.2, 0.2, 0.55)

enum BubbleMode { IDLE, SAY, REMINDER }

var bubble_mode := BubbleMode.IDLE
var anchor_window: Window
var root: VBoxContainer
var panel: PanelContainer
var tail: Tail
var hide_timer: Timer
var repeat_timer: Timer
var tail_up := false
var _pop_tween: Tween


func _ready() -> void:
	borderless = true
	transparent = true
	unfocusable = true
	always_on_top = true
	wrap_controls = true

	root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(_on_panel_input)
	root.add_child(panel)

	tail = Tail.new()
	tail.custom_minimum_size = Vector2(0, TAIL_HEIGHT)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tail)

	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = SAY_DURATION
	hide_timer.timeout.connect(_on_say_expired)
	add_child(hide_timer)

	repeat_timer = Timer.new()
	repeat_timer.wait_time = REMINDER_REPEAT_INTERVAL
	repeat_timer.timeout.connect(_on_repeat_tick)
	add_child(repeat_timer)

	hide()


## A passing remark. Fades on its own; a reminder already on screen keeps the
## bubble until it is clicked, so anything said while one is up is dropped.
func say(text: String, anchor: Window) -> void:
	if bubble_mode == BubbleMode.REMINDER:
		return
	_speak(text, anchor, BubbleMode.SAY)
	hide_timer.start()


## Puts a reminder up and keeps it there. It repeats with a little poke every
## [constant REMINDER_REPEAT_INTERVAL] until the user clicks it.
func announce_reminder(message: String, anchor: Window) -> void:
	_speak(message, anchor, BubbleMode.REMINDER)
	repeat_timer.start()


func _speak(text: String, anchor: Window, new_mode: BubbleMode) -> void:
	bubble_mode = new_mode
	anchor_window = anchor
	hide_timer.stop()
	_build_content(new_mode, text)
	show()
	call_deferred("_reposition")
	_animate_in()


func _process(_delta: float) -> void:
	if visible and anchor_window:
		_reposition()


func _reposition() -> void:
	var centered_x := anchor_window.position.x + anchor_window.size.x / 2 - size.x / 2
	var above_y := anchor_window.position.y - size.y - VERTICAL_GAP

	# Stay on screen: if Klippy lives near the top edge, flip to hang below him
	# instead of sliding off the top of the desktop.
	var workrect := DisplayServer.screen_get_usable_rect(anchor_window.current_screen)
	var min_x := workrect.position.x
	var max_x := maxi(workrect.position.x + workrect.size.x - size.x, min_x)
	var want_tail_up := above_y < workrect.position.y
	if want_tail_up != tail_up:
		tail_up = want_tail_up
		tail.points_up = tail_up
		root.move_child(tail, 0 if tail_up else 1)
		tail.queue_redraw()

	var x := clampi(centered_x, min_x, max_x)
	var y := (
		anchor_window.position.y + anchor_window.size.y + VERTICAL_GAP
		if tail_up
		else above_y
	)
	position = Vector2i(x, y)


func _build_content(new_mode: BubbleMode, text: String) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()

	var message := Label.new()
	message.text = text
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color", MESSAGE_COLOR)

	if new_mode != BubbleMode.REMINDER:
		message.add_theme_font_size_override("font_size", 15)
		panel.add_child(message)
		return

	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(REMINDER_MIN_WIDTH, 0)
	message.add_theme_font_size_override("font_size", 16)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(header)

	var icon := ClockIcon.new()
	icon.custom_minimum_size = Vector2(16, 16)
	header.add_child(icon)

	var title := Label.new()
	title.text = "REMINDER"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(title)

	content.add_child(message)

	var hint := Label.new()
	hint.text = "click to dismiss"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	content.add_child(hint)


func _animate_in() -> void:
	if _pop_tween:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_interval(0.02)
	_pop_tween.tween_callback(_start_pop)


func _start_pop() -> void:
	root.pivot_offset = Vector2(root.size.x / 2.0, root.size.y)
	root.scale = Vector2.ONE * 0.4
	root.modulate.a = 0.0
	if _pop_tween:
		_pop_tween.kill()
	_pop_tween = create_tween().set_parallel(true)
	_pop_tween.tween_property(root, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(root, "modulate:a", 1.0, 0.15)


## The nag: a short poke to pull the eye back to a reminder still not clicked.
func _on_repeat_tick() -> void:
	if bubble_mode != BubbleMode.REMINDER or not visible:
		return

	if _pop_tween:
		_pop_tween.kill()
	root.pivot_offset = Vector2(root.size.x / 2.0, root.size.y)
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(root, "scale", Vector2.ONE * 1.1, 0.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(root, "rotation", 0.05, 0.1)
	_pop_tween.chain().set_parallel(true)
	_pop_tween.tween_property(root, "scale", Vector2.ONE, 0.25)
	_pop_tween.tween_property(root, "rotation", 0.0, 0.25)


func _on_say_expired() -> void:
	hide()
	if bubble_mode == BubbleMode.SAY:
		bubble_mode = BubbleMode.IDLE


func _on_panel_input(event: InputEvent) -> void:
	if bubble_mode != BubbleMode.REMINDER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dismiss_reminder()


func dismiss_reminder() -> void:
	if bubble_mode != BubbleMode.REMINDER:
		return
	bubble_mode = BubbleMode.IDLE
	repeat_timer.stop()
	if _pop_tween:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(root, "modulate:a", 0.0, 0.15)
	_pop_tween.tween_callback(hide)
	dismissed.emit()


class Tail:
	extends Control

	var points_up := false

	func _draw() -> void:
		var cx := size.x / 2.0
		var overlap := -SpeechBubble.TAIL_OVERLAP
		var tip_y := size.y
		if points_up:
			overlap = size.y + SpeechBubble.TAIL_OVERLAP
			tip_y = 0.0

		var left := Vector2(cx - SpeechBubble.TAIL_WIDTH, overlap)
		var right := Vector2(cx + SpeechBubble.TAIL_WIDTH, overlap)
		var tip := Vector2(cx, tip_y)
		draw_colored_polygon(PackedVector2Array([left, right, tip]), SpeechBubble.BG_COLOR)
		# Only the slanted sides get an outline; the wide edge sits over the
		# panel's own border and hides it, which is what makes the two read as
		# one shape.
		draw_line(left, tip, SpeechBubble.BORDER_COLOR, 2.0)
		draw_line(right, tip, SpeechBubble.BORDER_COLOR, 2.0)


class ClockIcon:
	extends Control

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 1.5
		draw_arc(center, radius, 0, TAU, 24, SpeechBubble.ACCENT_COLOR, 2.0, true)
		draw_line(center, center + Vector2(0, -radius * 0.55), SpeechBubble.ACCENT_COLOR, 2.0, true)
		draw_line(center, center + Vector2(radius * 0.45, radius * 0.2), SpeechBubble.ACCENT_COLOR, 2.0, true)
