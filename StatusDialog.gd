class_name StatusDialog
extends Window

var stats: PetStats
var food_status_label: Label
var food_value_label: Label
var mood_status_label: Label
var mood_value_label: Label


func _ready() -> void:
	title = "Status"
	size = Vector2i(250, 160)
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

	food_status_label = Label.new()
	vbox.add_child(food_status_label)

	food_value_label = Label.new()
	food_value_label.visible = false
	vbox.add_child(food_value_label)

	mood_status_label = Label.new()
	vbox.add_child(mood_status_label)

	mood_value_label = Label.new()
	mood_value_label.visible = false
	vbox.add_child(mood_value_label)

	stats.food_changed.connect(_on_food_changed)
	stats.mood_changed.connect(_on_mood_changed)
	_on_food_changed(stats.food)
	_on_mood_changed(stats.mood)


func set_show_food_value(enabled: bool) -> void:
	food_value_label.visible = enabled


func set_show_mood_value(enabled: bool) -> void:
	mood_value_label.visible = enabled


func _on_food_changed(value: float) -> void:
	food_status_label.text = "Food: %s" % stats.get_status()
	food_value_label.text = "%.1f / %.0f" % [value, PetStats.MAX_FOOD]


func _on_mood_changed(value: float) -> void:
	mood_status_label.text = "Mood: %s" % stats.get_mood_status()
	mood_value_label.text = "%.1f / %.0f" % [value, PetStats.MAX_MOOD]
