class_name ExpressionCatalog
extends RefCounted

## Every face detail Klippy can wear, keyed by [member CosmeticPartDef.id].
## Adding a new expression is adding one more block to
## [method _ensure_initialized] here — nothing that applies or saves a
## cosmetic needs to know the specific list.

const DEFAULT := "default"
const CLEAN_MARBLE := "clean_marble"

static var _defs: Dictionary = {}
static var _initialized := false


static func get_def(id: String) -> CosmeticPartDef:
	_ensure_initialized()
	return _defs.get(id, _defs[DEFAULT])


static func ids() -> Array:
	_ensure_initialized()
	return _defs.keys()


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	var default_expression := CosmeticPartDef.new()
	default_expression.id = DEFAULT
	default_expression.display_name = "Default"
	default_expression.texture = preload("res://assets/KlippyCosmetics/Expressions/Default/KlippyIconicSmile.png")
	_defs[default_expression.id] = default_expression

	var marble_expression := CosmeticPartDef.new()
	marble_expression.id = CLEAN_MARBLE
	marble_expression.display_name = "Clean Marble"
	marble_expression.texture = preload("res://assets/KlippyCosmetics/Expressions/CleanMarble/KlippyIconicSmile.png")
	_defs[marble_expression.id] = marble_expression
