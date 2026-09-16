class_name DevToolsDialog
extends Window

signal bounce_triggered

const ADJUST_STEP := 10.0
const XP_ADJUST_STEP := 100.0

var stats: PetStats
var pet_level: PetLevel
var level_label: Label


func setup(pet_stats: PetStats, level: PetLevel) -> void:
	stats = pet_stats
	pet_level = level
	var vbox := RockyTheme.setup_window(self, "Dev Tools")

	_add_stat_row(vbox, "Food", stats.debug_adjust_food)
	_add_stat_row(vbox, "Mood", stats.debug_adjust_mood)
	_add_stat_row(vbox, "Health", stats.debug_adjust_health)

	level_label = Label.new()
	vbox.add_child(level_label)
	pet_level.level_changed.connect(_on_level_changed)
	pet_level.xp_changed.connect(_on_xp_changed)
	_update_level_label()

	_add_stat_row(vbox, "XP", pet_level.debug_adjust_xp, XP_ADJUST_STEP)
	_add_int_stat_row(vbox, "Level", pet_level.debug_adjust_level)

	var bounce_button := Button.new()
	bounce_button.text = "Trigger Bounce"
	bounce_button.theme_type_variation = "ButtonPrimary"
	bounce_button.pressed.connect(bounce_triggered.emit)
	vbox.add_child(bounce_button)


func _add_stat_row(parent: VBoxContainer, label_text: String, adjust: Callable, step := ADJUST_STEP) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)

	var decrease_button := Button.new()
	decrease_button.text = "-%d" % int(step)
	decrease_button.pressed.connect(adjust.bind(-step))
	row.add_child(decrease_button)

	var increase_button := Button.new()
	increase_button.text = "+%d" % int(step)
	increase_button.pressed.connect(adjust.bind(step))
	row.add_child(increase_button)


## Same layout as [method _add_stat_row], but for a callable that takes an
## int delta (like [method PetLevel.debug_adjust_level]) rather than a float.
func _add_int_stat_row(parent: VBoxContainer, label_text: String, adjust: Callable, step := 1) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)

	var decrease_button := Button.new()
	decrease_button.text = "-%d" % step
	decrease_button.pressed.connect(adjust.bind(-step))
	row.add_child(decrease_button)

	var increase_button := Button.new()
	increase_button.text = "+%d" % step
	increase_button.pressed.connect(adjust.bind(step))
	row.add_child(increase_button)


func _on_level_changed(_new_level: int) -> void:
	_update_level_label()


func _on_xp_changed(_value: float) -> void:
	_update_level_label()


func _update_level_label() -> void:
	level_label.text = "Level %d (%.1f / %.0f XP)" % [
		pet_level.level, pet_level.xp_into_level(), PetLevel.XP_PER_LEVEL
	]
