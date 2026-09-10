class_name SettingsPanel
extends Window

signal show_food_toggled(enabled: bool)
signal show_mood_toggled(enabled: bool)
signal show_health_toggled(enabled: bool)
signal dev_tools_toggled(enabled: bool)
signal size_selected(size: int)

var stats: PetStats
var size_steps: Array


func _ready() -> void:
	title = "Settings"
	size = Vector2i(300, 280)
	close_requested.connect(hide)


func setup(pet_stats: PetStats, initial: Dictionary, sizes: Array) -> void:
	stats = pet_stats
	size_steps = sizes

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

	var feeding_check := CheckBox.new()
	feeding_check.text = "Enable feeding"
	feeding_check.set_pressed_no_signal(stats.feeding_enabled)
	feeding_check.toggled.connect(_on_feeding_toggled)
	vbox.add_child(feeding_check)

	var show_food_check := CheckBox.new()
	show_food_check.text = "Show food value"
	show_food_check.set_pressed_no_signal(initial.get("show_food", false))
	show_food_check.toggled.connect(_on_show_food_toggled)
	vbox.add_child(show_food_check)

	var show_mood_check := CheckBox.new()
	show_mood_check.text = "Show mood value"
	show_mood_check.set_pressed_no_signal(initial.get("show_mood", false))
	show_mood_check.toggled.connect(_on_show_mood_toggled)
	vbox.add_child(show_mood_check)

	var show_health_check := CheckBox.new()
	show_health_check.text = "Show health value"
	show_health_check.set_pressed_no_signal(initial.get("show_health", false))
	show_health_check.toggled.connect(_on_show_health_toggled)
	vbox.add_child(show_health_check)

	var dev_tools_check := CheckBox.new()
	dev_tools_check.text = "Enable Dev Tools"
	dev_tools_check.set_pressed_no_signal(initial.get("dev_tools_enabled", false))
	dev_tools_check.toggled.connect(_on_dev_tools_toggled)
	vbox.add_child(dev_tools_check)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	vbox.add_child(size_row)

	var size_label := Label.new()
	size_label.text = "Size"
	size_row.add_child(size_label)

	var size_option := OptionButton.new()
	for i in size_steps.size():
		size_option.add_item("%d x %d" % [size_steps[i], size_steps[i]], i)
	size_option.select(maxi(size_steps.find(initial.get("size", size_steps[0])), 0))
	size_option.item_selected.connect(_on_size_selected)
	size_row.add_child(size_option)


func _on_feeding_toggled(enabled: bool) -> void:
	stats.set_feeding_enabled(enabled)


func _on_show_food_toggled(enabled: bool) -> void:
	show_food_toggled.emit(enabled)


func _on_show_mood_toggled(enabled: bool) -> void:
	show_mood_toggled.emit(enabled)


func _on_show_health_toggled(enabled: bool) -> void:
	show_health_toggled.emit(enabled)


func _on_dev_tools_toggled(enabled: bool) -> void:
	dev_tools_toggled.emit(enabled)


func _on_size_selected(index: int) -> void:
	size_selected.emit(size_steps[index])
