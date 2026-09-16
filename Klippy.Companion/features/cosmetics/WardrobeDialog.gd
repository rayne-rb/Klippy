class_name WardrobeDialog
extends Window

## Lets the user pick Klippy's body/expression/eyes/pupils independently. Each
## row shows the current pick, with </> to cycle through that category's
## options — or the pick itself can be clicked to open
## [CosmeticPickerDialog] for a searchable, thumbnail-grid look at every
## option in that category.

signal body_selected(id: String)
signal expression_selected(id: String)
signal eyes_selected(id: String)
signal pupils_selected(id: String)

## One entry per row: {container, ids_fn, get_def_fn, index, field_button,
## changed_signal, label}. Built generically over these instead of writing
## four near-identical row/cycle/picker blocks, since all four categories
## (body/expression/eyes/pupils) share the exact same id/display_name/texture
## shape.
var _rows: Array[Dictionary] = []
var _row_list: VBoxContainer
var _picker: CosmeticPickerDialog
var _active_row_index := -1


func _ready() -> void:
	title = "Wardrobe"
	# Fixed rather than fit-to-content: reset_size() (see setup()) would need
	# to run after the freshly-added rows' first layout pass, which happens on
	# the next idle frame, not synchronously within setup() itself.
	size = Vector2i(340, 240)
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	_row_list = VBoxContainer.new()
	_row_list.add_theme_constant_override("separation", 8)
	margin.add_child(_row_list)

	# Built once up front rather than lazily per-open, so reopening this
	# dialog (see setup()) never has to worry about tearing an in-progress
	# picker down along with the row list.
	_picker = CosmeticPickerDialog.new()
	add_child(_picker)
	_picker.item_selected.connect(_on_picker_item_selected)


func setup(initial: Dictionary) -> void:
	for row in _rows:
		var container := row.container as Control
		_row_list.remove_child(container)
		container.queue_free()
	_rows.clear()

	_add_row("Body", Callable(BodyCatalog, "ids"), Callable(BodyCatalog, "get_def"),
		initial.get("body", BodyCatalog.DEFAULT), body_selected)
	_add_row("Expression", Callable(ExpressionCatalog, "ids"), Callable(ExpressionCatalog, "get_def"),
		initial.get("expression", ExpressionCatalog.DEFAULT), expression_selected)
	_add_row("Eyes", Callable(EyesCatalog, "ids"), Callable(EyesCatalog, "get_def"),
		initial.get("eyes", EyesCatalog.DEFAULT), eyes_selected)
	_add_row("Pupils", Callable(PupilsCatalog, "ids"), Callable(PupilsCatalog, "get_def"),
		initial.get("pupils", PupilsCatalog.DEFAULT), pupils_selected)


func _add_row(label_text: String, ids_fn: Callable, get_def_fn: Callable,
		initial_id: String, changed_signal: Signal) -> void:
	var row_index := _rows.size()
	var ids: Array = ids_fn.call()
	var index := maxi(ids.find(initial_id), 0)

	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	_row_list.add_child(container)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80, 0)
	container.add_child(label)

	var prev_button := Button.new()
	prev_button.text = "<"
	prev_button.pressed.connect(_on_arrow_pressed.bind(row_index, -1))
	container.add_child(prev_button)

	var field_button := Button.new()
	field_button.custom_minimum_size = Vector2(140, 0)
	field_button.pressed.connect(_on_field_pressed.bind(row_index))
	container.add_child(field_button)

	var next_button := Button.new()
	next_button.text = ">"
	next_button.pressed.connect(_on_arrow_pressed.bind(row_index, 1))
	container.add_child(next_button)

	_rows.append({
		"container": container,
		"ids_fn": ids_fn,
		"get_def_fn": get_def_fn,
		"index": index,
		"field_button": field_button,
		"changed_signal": changed_signal,
		"label": label_text,
	})
	_refresh_row(row_index)


func _refresh_row(row_index: int) -> void:
	var row: Dictionary = _rows[row_index]
	var ids: Array = row.ids_fn.call()
	var def: CosmeticPartDef = row.get_def_fn.call(ids[row.index])
	(row.field_button as Button).text = def.display_name


func _on_arrow_pressed(row_index: int, direction: int) -> void:
	var row: Dictionary = _rows[row_index]
	var ids: Array = row.ids_fn.call()
	row.index = wrapi(row.index + direction, 0, ids.size())
	_refresh_row(row_index)
	(row.changed_signal as Signal).emit(ids[row.index])


func _on_field_pressed(row_index: int) -> void:
	_active_row_index = row_index
	var row: Dictionary = _rows[row_index]
	_picker.open_for(row.label, row.ids_fn.call(), row.get_def_fn)


func _on_picker_item_selected(id: String) -> void:
	var row: Dictionary = _rows[_active_row_index]
	var ids: Array = row.ids_fn.call()
	row.index = ids.find(id)
	_refresh_row(_active_row_index)
	(row.changed_signal as Signal).emit(id)
