class_name StatusDialog
extends Window

var stats: PetStats
var food_label: Label
var mood_label: Label


func _ready() -> void:
	title = "Status"
	size = Vector2i(250, 120)
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

	food_label = Label.new()
	vbox.add_child(food_label)

	mood_label = Label.new()
	vbox.add_child(mood_label)

	stats.food_changed.connect(_on_food_changed)
	stats.mood_changed.connect(_on_mood_changed)
	_on_food_changed(stats.food)
	_on_mood_changed(stats.mood)


func _on_food_changed(_value: float) -> void:
	food_label.text = "Food: %s" % stats.get_status()


func _on_mood_changed(_value: float) -> void:
	mood_label.text = "Mood: %s" % stats.get_mood_status()
