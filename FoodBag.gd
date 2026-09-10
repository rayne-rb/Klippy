class_name FoodBag
extends Node

signal contents_changed

const DISPLAY_NAMES := {
	"standard": "Standard Food",
}

var _counts: Dictionary = {}


func store(food_type: String, amount: int = 1) -> void:
	_counts[food_type] = _counts.get(food_type, 0) + amount
	contents_changed.emit()


func retrieve(food_type: String) -> bool:
	var count: int = _counts.get(food_type, 0)
	if count <= 0:
		return false
	if count == 1:
		_counts.erase(food_type)
	else:
		_counts[food_type] = count - 1
	contents_changed.emit()
	return true


func get_counts() -> Dictionary:
	return _counts.duplicate()


func load_counts(data: Dictionary) -> void:
	_counts.clear()
	for food_type in data:
		var count := int(data[food_type])
		if count > 0:
			_counts[food_type] = count
	contents_changed.emit()


static func get_display_name(food_type: String) -> String:
	return DISPLAY_NAMES.get(food_type, food_type.capitalize())
