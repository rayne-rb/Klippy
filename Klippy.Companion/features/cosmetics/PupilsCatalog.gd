class_name PupilsCatalog
extends RefCounted

## Every pupil pair Klippy can wear, keyed by [member CosmeticPartDef.id].
## Adding a new pair is adding one more block to
## [method _ensure_initialized] here — nothing that applies or saves a
## cosmetic needs to know the specific list.

const DEFAULT := "default"
const CLEAN_MARBLE := "clean_marble"
const OBSIDIAN := "obsidian"

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

	var default_pupils := CosmeticPartDef.new()
	default_pupils.id = DEFAULT
	default_pupils.display_name = "Default"
	default_pupils.texture = preload("res://assets/KlippyCosmetics/Pupils/Default/KlippyLeftPupil.png")
	default_pupils.right_texture = preload("res://assets/KlippyCosmetics/Pupils/Default/KlippyRightPupil.png")
	_defs[default_pupils.id] = default_pupils

	var marble_pupils := CosmeticPartDef.new()
	marble_pupils.id = CLEAN_MARBLE
	marble_pupils.display_name = "Clean Marble"
	marble_pupils.texture = preload("res://assets/KlippyCosmetics/Pupils/CleanMarble/KlippyLeftPupil.png")
	marble_pupils.right_texture = preload("res://assets/KlippyCosmetics/Pupils/CleanMarble/KlippyRightPupil.png")
	marble_pupils.required_level = LevelUnlocks.MARBLE_COSMETICS
	_defs[marble_pupils.id] = marble_pupils

	var obsidian_pupils := CosmeticPartDef.new()
	obsidian_pupils.id = OBSIDIAN
	obsidian_pupils.display_name = "Obsidian"
	obsidian_pupils.texture = preload("res://assets/KlippyCosmetics/Pupils/Obsidian/KlippyLeftPupil.png")
	obsidian_pupils.right_texture = preload("res://assets/KlippyCosmetics/Pupils/Obsidian/KlippyRightPupil.png")
	_defs[obsidian_pupils.id] = obsidian_pupils
