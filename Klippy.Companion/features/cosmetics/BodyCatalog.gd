class_name BodyCatalog
extends RefCounted

## Every body Klippy can wear, keyed by [member CosmeticPartDef.id]. Adding a
## new body is adding one more block to [method _ensure_initialized] here —
## nothing that applies or saves a cosmetic needs to know the specific list.

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

	var default_body := CosmeticPartDef.new()
	default_body.id = DEFAULT
	default_body.display_name = "Default"
	default_body.texture = preload("res://assets/KlippyCosmetics/Bodies/Default/KlippyBody.png")
	_defs[default_body.id] = default_body

	var marble_body := CosmeticPartDef.new()
	marble_body.id = CLEAN_MARBLE
	marble_body.display_name = "Clean Marble"
	marble_body.texture = preload("res://assets/KlippyCosmetics/Bodies/CleanMarble/KlippyBody.png")
	_defs[marble_body.id] = marble_body
