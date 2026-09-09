class_name SettingsPanel
extends Window

var stats: PetStats
var food_label: Label


func _ready() -> void:
	title = "Settings"
	size = Vector2i(300, 200)
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

	var feeding_check := CheckBox.new()
	feeding_check.text = "Enable feeding"
	feeding_check.toggled.connect(_on_feeding_toggled)
	vbox.add_child(feeding_check)

	var show_food_check := CheckBox.new()
	show_food_check.text = "Show food value"
	show_food_check.toggled.connect(_on_show_food_toggled)
	vbox.add_child(show_food_check)

	food_label = Label.new()
	food_label.visible = false
	vbox.add_child(food_label)

	stats.food_changed.connect(_on_food_changed)
	_on_food_changed(stats.food)


func _on_feeding_toggled(enabled: bool) -> void:
	stats.set_feeding_enabled(enabled)


func _on_show_food_toggled(enabled: bool) -> void:
	food_label.visible = enabled


func _on_food_changed(value: float) -> void:
	food_label.text = "Food: %.1f / %.0f" % [value, PetStats.MAX_FOOD]
