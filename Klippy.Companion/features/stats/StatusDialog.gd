class_name StatusDialog
extends Window

var stats: PetStats
var pet_level: PetLevel
var _vbox: VBoxContainer
var level_label: Label
var xp_bar: ProgressBar
var food_status_label: Label
var food_value_label: Label
var mood_status_label: Label
var mood_value_label: Label
var health_status_label: Label
var health_value_label: Label


func _ready() -> void:
	_vbox = RockyTheme.setup_window(self, "Status")


func setup(pet_stats: PetStats, level: PetLevel) -> void:
	stats = pet_stats
	pet_level = level

	level_label = Label.new()
	_vbox.add_child(level_label)

	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 14)
	xp_bar.show_percentage = false
	xp_bar.max_value = PetLevel.XP_PER_LEVEL
	_vbox.add_child(xp_bar)

	pet_level.level_changed.connect(_on_level_changed)
	pet_level.xp_changed.connect(_on_xp_changed)
	_update_level_label()

	food_status_label = Label.new()
	_vbox.add_child(food_status_label)

	food_value_label = Label.new()
	food_value_label.visible = false
	_vbox.add_child(food_value_label)

	mood_status_label = Label.new()
	_vbox.add_child(mood_status_label)

	mood_value_label = Label.new()
	mood_value_label.visible = false
	_vbox.add_child(mood_value_label)

	health_status_label = Label.new()
	_vbox.add_child(health_status_label)

	health_value_label = Label.new()
	health_value_label.visible = false
	_vbox.add_child(health_value_label)

	stats.food_changed.connect(_on_food_changed)
	stats.mood_changed.connect(_on_mood_changed)
	stats.health_changed.connect(_on_health_changed)
	_on_food_changed(stats.food)
	_on_mood_changed(stats.mood)
	_on_health_changed(stats.health)


func set_show_food_value(enabled: bool) -> void:
	food_value_label.visible = enabled


func set_show_mood_value(enabled: bool) -> void:
	mood_value_label.visible = enabled


func set_show_health_value(enabled: bool) -> void:
	health_value_label.visible = enabled


func _on_food_changed(value: float) -> void:
	food_status_label.text = "Food: %s" % stats.get_status()
	food_value_label.text = "%.1f / %.0f" % [value, PetStats.MAX_FOOD]


func _on_mood_changed(value: float) -> void:
	mood_status_label.text = "Mood: %s" % stats.get_mood_status()
	mood_value_label.text = "%.1f / %.0f" % [value, PetStats.MAX_MOOD]


func _on_health_changed(value: float) -> void:
	health_status_label.text = "Health: %s" % stats.get_health_status()
	health_value_label.text = "%.1f / %.0f" % [value, PetStats.MAX_HEALTH]


func _on_level_changed(_new_level: int) -> void:
	_update_level_label()


func _on_xp_changed(_value: float) -> void:
	_update_level_label()


func _update_level_label() -> void:
	level_label.text = "Level %d (%.1f / %.0f XP)" % [
		pet_level.level, pet_level.xp_into_level(), PetLevel.XP_PER_LEVEL
	]
	xp_bar.value = pet_level.xp_into_level()
