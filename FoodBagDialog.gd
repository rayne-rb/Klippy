class_name FoodBagDialog
extends Window

signal take_requested(food_type: String)

var food_bag: FoodBag
var list_container: VBoxContainer
var empty_label: Label


func _ready() -> void:
	title = "Food Bag"
	size = Vector2i(260, 220)
	close_requested.connect(hide)


func setup(bag: FoodBag) -> void:
	food_bag = bag

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

	empty_label = Label.new()
	empty_label.text = "The bag is empty."
	vbox.add_child(empty_label)

	list_container = VBoxContainer.new()
	list_container.add_theme_constant_override("separation", 6)
	vbox.add_child(list_container)

	food_bag.contents_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in list_container.get_children():
		child.queue_free()

	var counts := food_bag.get_counts()
	empty_label.visible = counts.is_empty()

	for food_type in counts:
		_add_item_row(food_type, counts[food_type])


func _add_item_row(food_type: String, count: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	list_container.add_child(row)

	var icon := TextureRect.new()
	icon.texture = FoodBody.make_texture(food_type)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var label := Label.new()
	label.text = "%s x%d" % [FoodBag.get_display_name(food_type), count]
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var take_button := Button.new()
	take_button.text = "Take"
	take_button.pressed.connect(_on_take_pressed.bind(food_type))
	row.add_child(take_button)


func _on_take_pressed(food_type: String) -> void:
	take_requested.emit(food_type)
