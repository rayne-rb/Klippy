class_name RockyTheme
extends RefCounted

## The look every menu and dialog shares: warm stone panels with charcoal
## outlines and terracotta accents, like Klippy himself. Text is dark on
## light throughout, so nothing can ever read white-on-white.
##
## [method setup_window] turns a plain Window into a chromeless bubble with
## a title row and close button, and [method theme] carries the shared
## control styles so each dialog only builds its content.

const PANEL_BG := Color("efe8db")
const PANEL_BORDER := Color("46413a")
const FIELD_BG := Color("fbf8f1")
const FIELD_BORDER := Color("cfc4ac")
const TEXT := Color("2e2a25")
const MUTED := Color("6e6558")
const DISABLED := Color("a89f90")
const ACCENT := Color("c2601f")
const ACCENT_HOVER := Color("d8722a")
const ACCENT_PRESSED := Color("a84f16")
const HOVER_FILL := Color("e2d8c6")
const SHADOW := Color(0.0, 0.0, 0.0, 0.18)

static var _theme: Theme


## The shared control theme. Buttons come out as friendly stone pebbles;
## set `theme_type_variation = "ButtonPrimary"` for the one accent button
## in a dialog (usually the action you want the eye to land on).
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = 14

		var focus_off := StyleBoxEmpty.new()

		for type in ["Button", "OptionButton"]:
			_theme.set_stylebox("normal", type, _box(Color("f6f1e7"), FIELD_BORDER, 10, 8))
			_theme.set_stylebox("hover", type, _box(HOVER_FILL, ACCENT, 10, 8))
			_theme.set_stylebox("pressed", type, _box(Color("d9cdb4"), ACCENT, 10, 8))
			_theme.set_stylebox("disabled", type, _box(Color("e7e0d2"), Color("d5cbb6"), 10, 8))
			_theme.set_stylebox("focus", type, focus_off)
			for item in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				_theme.set_color(item, type, TEXT)
			_theme.set_color("font_disabled_color", type, MUTED)

		_theme.set_type_variation("ButtonPrimary", "Button")
		_theme.set_stylebox("normal", "ButtonPrimary", _box(ACCENT, Color(0, 0, 0, 0), 10, 8))
		_theme.set_stylebox("hover", "ButtonPrimary", _box(ACCENT_HOVER, Color(0, 0, 0, 0), 10, 8))
		_theme.set_stylebox("pressed", "ButtonPrimary", _box(ACCENT_PRESSED, Color(0, 0, 0, 0), 10, 8))
		_theme.set_stylebox("disabled", "ButtonPrimary", _box(DISABLED, Color(0, 0, 0, 0), 10, 8))
		_theme.set_stylebox("focus", "ButtonPrimary", focus_off)
		for item in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_theme.set_color(item, "ButtonPrimary", Color.WHITE)
		_theme.set_color("font_disabled_color", "ButtonPrimary", Color("f3ece2"))

		_theme.set_stylebox("normal", "LineEdit", _box(FIELD_BG, FIELD_BORDER, 10, 8))
		_theme.set_stylebox("focus", "LineEdit", _box(FIELD_BG, ACCENT, 10, 8))
		_theme.set_stylebox("read_only", "LineEdit", _box(Color("e7e0d2"), FIELD_BORDER, 10, 8))
		_theme.set_color("font_color", "LineEdit", TEXT)
		_theme.set_color("font_placeholder_color", "LineEdit", MUTED)
		_theme.set_color("caret_color", "LineEdit", TEXT)

		_theme.set_color("font_color", "Label", TEXT)

		for type in ["CheckBox", "CheckButton"]:
			_theme.set_color("font_color", type, TEXT)
			_theme.set_color("font_hover_color", type, TEXT)
			_theme.set_color("font_pressed_color", type, TEXT)
			_theme.set_color("font_hover_pressed_color", type, TEXT)
			_theme.set_color("font_disabled_color", type, MUTED)
			# The engine's default focus ring is a loud orange band across the
			# whole row; on the stone panel a checked box is emphasis enough.
			_theme.set_stylebox("focus", type, StyleBoxEmpty.new())

		_theme.set_stylebox("panel", "PopupMenu", _box(PANEL_BG, PANEL_BORDER, 12, 6))
		_theme.set_stylebox("hover", "PopupMenu", _box(HOVER_FILL, Color(0, 0, 0, 0), 8, 0))
		_theme.set_color("font_color", "PopupMenu", TEXT)
		_theme.set_color("font_hover_color", "PopupMenu", TEXT)
		_theme.set_color("font_disabled_color", "PopupMenu", DISABLED)
		_theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
		_theme.set_constant("v_separation", "PopupMenu", 6)

		var line := StyleBoxLine.new()
		line.color = Color("d8cdb8")
		line.thickness = 1
		_theme.set_stylebox("separator", "PopupMenu", line)
		_theme.set_stylebox("separator", "HSeparator", line)

	return _theme


## Turns a plain Window into a chromeless bubble: rounded stone panel, soft
## shadow, and a title row with a close button that emits the window's
## `close_requested`. The window wraps its content, so dialogs are exactly as
## tall as what's inside them — no dead space — and every dialog shares the
## same `width` so the cards read as a set. Returns the container to put the
## dialog's content in.
static func setup_window(win: Window, title: String, width := 340) -> VBoxContainer:
	win.title = title
	win.borderless = true
	win.transparent = true
	win.wrap_controls = true
	win.min_size = Vector2i(width, 0)
	win.theme = theme()
	win.close_requested.connect(win.hide)

	var margin := MarginContainer.new()
	# Anchored to the full rect so the panel stretches to the window's width
	# (the window itself wraps to the content's minimum size; `min_size` gives
	# every dialog the same card width even when its content is narrow).
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	win.add_child(margin)

	var panel := PanelContainer.new()
	var style := _box(PANEL_BG, PANEL_BORDER, 18, 0)
	style.shadow_color = SHADOW
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

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", ACCENT)
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(spacer)

	# Borderless window has no OS titlebar to drag, so the header itself
	# drags it: hold left mouse on the title row and move the mouse.
	var drag := {"active": false, "offset": Vector2i()}
	header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			drag.active = event.pressed
			if event.pressed:
				drag.offset = DisplayServer.mouse_get_position() - win.position
		elif event is InputEventMouseMotion and drag.active:
			win.position = DisplayServer.mouse_get_position() - drag.offset
	)

	var close_button := Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.add_theme_color_override("font_color", MUTED)
	close_button.add_theme_color_override("font_hover_color", TEXT)
	close_button.add_theme_stylebox_override("hover", _box(HOVER_FILL, Color(0, 0, 0, 0), 8, 6))
	close_button.add_theme_stylebox_override("pressed", _box(Color("d9cdb4"), Color(0, 0, 0, 0), 8, 6))
	close_button.pressed.connect(func() -> void: win.close_requested.emit())
	header.add_child(close_button)

	return vbox


## Popup menus (the context menu, OptionButton dropdowns) need the window
## made transparent for their rounded panel and the theme attached directly,
## since they may sit outside a themed dialog.
static func style_popup(menu: PopupMenu) -> void:
	menu.transparent = true
	menu.theme = theme()


static func _box(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	if pad > 0:
		style.set_content_margin_all(pad)
	return style
