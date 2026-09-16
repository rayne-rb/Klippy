class_name HatsCatalog
extends RefCounted

## Every hat Klippy can wear, keyed by [member CosmeticPartDef.id]. Unlike
## body/expression/eyes/pupils, a hat is optional: [constant DEFAULT] is
## "None" (no texture at all) rather than a specific art asset. Whether a
## slot allows going bare isn't a flag on [CosmeticPartDef] — it's simply
## whether that slot's catalog bothers registering a no-texture entry, which
## only hats do today.

const DEFAULT := "none"
const CROWN := "crown"

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

	var none_hat := CosmeticPartDef.new()
	none_hat.id = DEFAULT
	none_hat.display_name = "None"
	_defs[none_hat.id] = none_hat

	var crown_hat := CosmeticPartDef.new()
	crown_hat.id = CROWN
	crown_hat.display_name = "Crown"
	crown_hat.texture = preload("res://assets/KlippyCosmetics/Hats/KlippyCrown.png")
	crown_hat.required_level = LevelUnlocks.CROWN_HAT
	_defs[crown_hat.id] = crown_hat
