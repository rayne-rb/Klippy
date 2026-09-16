class_name EyesCatalog
extends RefCounted

## Every eye pair Klippy can wear, keyed by [member CosmeticPartDef.id].
## Adding a new pair is adding one more block to
## [method _ensure_initialized] here — nothing that applies or saves a
## cosmetic needs to know the specific list.

const DEFAULT := "default"

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

	var default_eyes := CosmeticPartDef.new()
	default_eyes.id = DEFAULT
	default_eyes.display_name = "Default"
	default_eyes.texture = preload("res://assets/KlippyCosmetics/Eyes/Default/KlippyLeftEye.png")
	default_eyes.right_texture = preload("res://assets/KlippyCosmetics/Eyes/Default/KlippyRightEye.png")
	_defs[default_eyes.id] = default_eyes
