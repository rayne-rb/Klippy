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
signal hat_selected(id: String)

## One entry per row: {container, ids_fn, get_def_fn, index, field_button,
## changed_signal, label}. Built generically over these instead of writing
## four near-identical row/cycle/picker blocks, since all four categories
## (body/expression/eyes/pupils) share the exact same id/display_name/texture
## shape.
var _rows: Array[Dictionary] = []
var _row_list: VBoxContainer
var _picker: CosmeticPickerDialog
var _active_row_index := -1
var _pet_level: PetLevel


func _ready() -> void:
	_row_list = RockyTheme.setup_window(self, "Wardrobe")
	# setup_window() wires close_requested to the plain hide() every other
	# dialog wants; this one also has a picker sub-window to take down.
	close_requested.disconnect(hide)
	close_requested.connect(close_all)

	# Built once up front rather than lazily per-open, so reopening this
	# dialog (see setup()) never has to worry about tearing an in-progress
	# picker down along with the row list.
	_picker = CosmeticPickerDialog.new()
	add_child(_picker)
	_picker.item_selected.connect(_on_picker_item_selected)


## Closes the row list and whichever category's picker grid happened to be
## left open — [member _picker] is a separate sub-[Window], so hiding this
## one alone wouldn't take it down too. Named distinctly rather than
## overriding [method Window.hide]: Godot only dispatches its own internal
## calls to the native method, so a same-named override would silently miss
## those (and the engine treats it as an error here regardless).
func close_all() -> void:
	_picker.hide()
	hide()


func setup(initial: Dictionary, pet_level: PetLevel) -> void:
	_pet_level = pet_level
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
	_add_row("Hats", Callable(HatsCatalog, "ids"), Callable(HatsCatalog, "get_def"),
		initial.get("hat", HatsCatalog.DEFAULT), hat_selected)


## Only options Klippy's current level has reached — locked options (see
## [member CosmeticPartDef.required_level]) simply don't appear yet, rather
## than showing as a disabled/mystery entry.
func _unlocked_ids(ids_fn: Callable, get_def_fn: Callable) -> Array:
	var unlocked := []
	for id in ids_fn.call():
		var def: CosmeticPartDef = get_def_fn.call(id)
		if _pet_level.is_unlocked(def.required_level):
			unlocked.append(id)
	return unlocked


func _add_row(label_text: String, ids_fn: Callable, get_def_fn: Callable,
		initial_id: String, changed_signal: Signal) -> void:
	var row_index := _rows.size()
	var ids: Array = _unlocked_ids(ids_fn, get_def_fn)
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
	var ids: Array = _unlocked_ids(row.ids_fn, row.get_def_fn)
	var def: CosmeticPartDef = row.get_def_fn.call(ids[row.index])
	(row.field_button as Button).text = def.display_name


func _on_arrow_pressed(row_index: int, direction: int) -> void:
	var row: Dictionary = _rows[row_index]
	var ids: Array = _unlocked_ids(row.ids_fn, row.get_def_fn)
	row.index = wrapi(row.index + direction, 0, ids.size())
	_refresh_row(row_index)
	(row.changed_signal as Signal).emit(ids[row.index])


func _on_field_pressed(row_index: int) -> void:
	_active_row_index = row_index
	var row: Dictionary = _rows[row_index]
	_picker.open_for(row.label, _unlocked_ids(row.ids_fn, row.get_def_fn), row.get_def_fn)


func _on_picker_item_selected(id: String) -> void:
	var row: Dictionary = _rows[_active_row_index]
	var ids: Array = _unlocked_ids(row.ids_fn, row.get_def_fn)
	row.index = ids.find(id)
	_refresh_row(_active_row_index)
	(row.changed_signal as Signal).emit(id)
