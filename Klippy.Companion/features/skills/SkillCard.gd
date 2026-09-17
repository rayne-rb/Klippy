class_name SkillCard
extends PanelContainer

## The shape every entry in the Skills window takes: what it is called, one line
## about what it does, a single button, and a status line saying why that button is
## (or is not) available right now.
##
## A skill extends this and fills it in from its own [method _ready], so the list
## reads as a set however many of them there end up being, and adding one is a file
## in this folder plus a line in [SkillsDialog].

## The card's button was pressed. What that means is the skill's business.
signal action_pressed

## What a wrapping label inside the card has to work with: the dialog's width less
## its margins and the card's own.
const TEXT_WIDTH := 290

var title_label: Label
var description_label: Label
var action_button: Button
var status_label: Label

## Room between the description and the status line for anything a skill needs of
## its own — a picker, a toggle. Empty cards show nothing here.
var extra: VBoxContainer


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = RockyTheme.FIELD_BG
	style.border_color = RockyTheme.FIELD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", RockyTheme.ACCENT)
	header.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	action_button = Button.new()
	action_button.theme_type_variation = "ButtonPrimary"
	action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_button.pressed.connect(func() -> void: action_pressed.emit())
	header.add_child(action_button)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label reports its height for whatever width it currently has, and a
	# window that wraps to its content asks before it has laid anything out — without
	# a width to start from the card comes out absurdly tall. Same reason the Connection
	# dialog pins its hint.
	description_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	vbox.add_child(description_label)

	extra = VBoxContainer.new()
	extra.add_theme_constant_override("separation", 6)
	vbox.add_child(extra)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", RockyTheme.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	vbox.add_child(status_label)


func set_title(text: String) -> void:
	title_label.text = text


func set_description(text: String) -> void:
	description_label.text = text


## The one button: what it says, and whether it can be pressed at all.
func set_action(text: String, enabled: bool) -> void:
	action_button.text = text
	action_button.disabled = not enabled


## The line underneath. Always says something — a card that can't be used owes the
## user a reason more than it owes them a greyed-out button.
func set_status(text: String) -> void:
	status_label.text = text
