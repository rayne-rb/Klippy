class_name CosmeticPickerDialog
extends Window

## A searchable thumbnail grid for browsing every option in one cosmetic
## category, opened from [WardrobeDialog] when a field is clicked instead of
## cycled with its arrows.

signal item_selected(id: String)

const COLUMNS := 4
const CELL_SIZE := Vector2(96, 96)

var _category_label: Label
var _search: LineEdit
var _grid: GridContainer


func _ready() -> void:
	# setup_window()'s own header title is fixed at construction time, but
	# this dialog's heading changes per [method open_for] call, so it gets
	# its own label underneath instead (the header still supplies the ✕).
	var vbox := RockyTheme.setup_window(self, "", 440)

	_category_label = Label.new()
	_category_label.add_theme_color_override("font_color", RockyTheme.ACCENT)
	_category_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_category_label)

	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.text_changed.connect(_on_search_changed)
	vbox.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	# Built once up front (see WardrobeDialog._ready()), not shown until the
	# first real [method open_for] call.
	hide()


## [param get_def_fn] is a [Callable] to a catalog's static `get_def(id)`.
func open_for(category_label: String, ids: Array, get_def_fn: Callable) -> void:
	_category_label.text = category_label
	_search.text = ""

	# remove_child() first: queue_free() alone only defers removal to end of
	# frame, so a reopen before that flush would briefly see old and new
	# items in the grid together (get_child_count(), the search filter).
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	for id in ids:
		var def: CosmeticPartDef = get_def_fn.call(id)
		var item := Button.new()
		item.custom_minimum_size = CELL_SIZE
		item.text = def.display_name
		item.icon = def.texture
		item.expand_icon = true
		item.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		item.pressed.connect(_on_item_pressed.bind(id))
		_grid.add_child(item)

	popup_centered()


func _on_item_pressed(id: String) -> void:
	item_selected.emit(id)
	hide()


func _on_search_changed(query: String) -> void:
	var lowered := query.to_lower()
	for child in _grid.get_children():
		var button := child as Button
		button.visible = lowered.is_empty() or button.text.to_lower().contains(lowered)
