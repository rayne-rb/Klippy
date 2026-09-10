class_name DevToolsDialog
extends Window

const ADJUST_STEP := 10.0

var stats: PetStats


func _ready() -> void:
	title = "Dev Tools"
	size = Vector2i(260, 190)
	close_requested.connect(hide)


func setup(pet_stats: PetStats) -> void:
	stats = pet_stats

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

	_add_stat_row(vbox, "Food", stats.debug_adjust_food)
	_add_stat_row(vbox, "Mood", stats.debug_adjust_mood)
	_add_stat_row(vbox, "Health", stats.debug_adjust_health)


func _add_stat_row(parent: VBoxContainer, label_text: String, adjust: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)

	var decrease_button := Button.new()
	decrease_button.text = "-%d" % int(ADJUST_STEP)
	decrease_button.pressed.connect(adjust.bind(-ADJUST_STEP))
	row.add_child(decrease_button)

	var increase_button := Button.new()
	increase_button.text = "+%d" % int(ADJUST_STEP)
	increase_button.pressed.connect(adjust.bind(ADJUST_STEP))
	row.add_child(increase_button)
