class_name LinkStatusChip
extends PanelContainer

## A small pill saying where the Companion stands with the server: a coloured dot
## and a word. It reads [code]KlippyLink[/code] itself and follows
## [signal KlippyLink.state_changed], so anywhere it is dropped stays current
## without the host dialog knowing the link exists.
##
## Shrink-to-fit by default, so it sits as a badge rather than stretching across
## whatever container it lands in.

const CONNECTED_FILL := Color("dcebd9")
const CONNECTED_EDGE := Color("8bb183")
const CONNECTED_DOT := Color("4c8a46")

const WORKING_FILL := Color("f4e4cd")
const WORKING_EDGE := Color("d9b686")
const WORKING_DOT := Color("c2601f")

const OFFLINE_FILL := Color("e7e0d2")
const OFFLINE_EDGE := Color("cfc4ac")
const OFFLINE_DOT := Color("a89f90")

const DOT_SIZE := 8

var _dot: Panel
var _label: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_dot)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	row.add_child(_label)

	KlippyLink.state_changed.connect(_on_state_changed)
	_on_state_changed(KlippyLink.state)


func _on_state_changed(state: KlippyLink.State) -> void:
	match state:
		KlippyLink.State.CONNECTED:
			_apply("Connected", CONNECTED_FILL, CONNECTED_EDGE, CONNECTED_DOT)
		KlippyLink.State.CONNECTING:
			_apply("Connecting", WORKING_FILL, WORKING_EDGE, WORKING_DOT)
		KlippyLink.State.PAIRING:
			_apply("Pairing", WORKING_FILL, WORKING_EDGE, WORKING_DOT)
		KlippyLink.State.SEARCHING:
			_apply("Searching", WORKING_FILL, WORKING_EDGE, WORKING_DOT)
		_:
			_apply("Not connected", OFFLINE_FILL, OFFLINE_EDGE, OFFLINE_DOT)


func _apply(text: String, fill: Color, edge: Color, dot: Color) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", RockyTheme.TEXT)

	var pill := StyleBoxFlat.new()
	pill.bg_color = fill
	pill.border_color = edge
	pill.set_border_width_all(1)
	# Radius past half the pill's height just rounds to a capsule, which is what
	# a chip wants at whatever height the font ends up giving it.
	pill.set_corner_radius_all(99)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 3
	pill.content_margin_bottom = 3
	add_theme_stylebox_override("panel", pill)

	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = dot
	dot_style.set_corner_radius_all(DOT_SIZE / 2)
	_dot.add_theme_stylebox_override("panel", dot_style)
