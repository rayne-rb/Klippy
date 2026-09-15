class_name DevToolsDialog
extends Window

signal bounce_triggered

const ADJUST_STEP := 10.0

var stats: PetStats


func setup(pet_stats: PetStats) -> void:
	stats = pet_stats
	var vbox := RockyTheme.setup_window(self, "Dev Tools", Vector2i(320, 280))

	_add_stat_row(vbox, "Food", stats.debug_adjust_food)
	_add_stat_row(vbox, "Mood", stats.debug_adjust_mood)
	_add_stat_row(vbox, "Health", stats.debug_adjust_health)

	var bounce_button := Button.new()
	bounce_button.text = "Trigger Bounce"
	bounce_button.theme_type_variation = "ButtonPrimary"
	bounce_button.pressed.connect(bounce_triggered.emit)
	vbox.add_child(bounce_button)


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
