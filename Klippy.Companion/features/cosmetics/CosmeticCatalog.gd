class_name CosmeticCatalog
extends RefCounted

## Every look Klippy can wear, keyed by [member CosmeticSetDef.id]. Adding a
## new preset is adding one more block to [method _ensure_initialized] here —
## nothing that applies or saves a cosmetic needs to know the specific list.

const DEFAULT := "default"
const CLEAN_MARBLE := "clean_marble"

static var _defs: Dictionary = {}
static var _initialized := false


static func get_def(id: String) -> CosmeticSetDef:
	_ensure_initialized()
	return _defs.get(id, _defs[DEFAULT])


static func ids() -> Array:
	_ensure_initialized()
	return _defs.keys()


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	var default_set := CosmeticSetDef.new()
	default_set.id = DEFAULT
	default_set.display_name = "Default"
	default_set.body_texture = preload("res://assets/KlippyCosmetics/Bodies/Default/KlippyBody.png")
	default_set.expression_texture = preload("res://assets/KlippyCosmetics/Expressions/Default/KlippyIconicSmile.png")
	default_set.left_eye_texture = preload("res://assets/KlippyCosmetics/Eyes/Default/KlippyLeftEye.png")
	default_set.right_eye_texture = preload("res://assets/KlippyCosmetics/Eyes/Default/KlippyRightEye.png")
	default_set.left_pupil_texture = preload("res://assets/KlippyCosmetics/Pupils/Default/KlippyLeftPupil.png")
	default_set.right_pupil_texture = preload("res://assets/KlippyCosmetics/Pupils/Default/KlippyRightPupil.png")
	_defs[default_set.id] = default_set

	var marble_set := CosmeticSetDef.new()
	marble_set.id = CLEAN_MARBLE
	marble_set.display_name = "Clean Marble"
	marble_set.body_texture = preload("res://assets/KlippyCosmetics/Bodies/CleanMarble/KlippyBody.png")
	marble_set.expression_texture = preload("res://assets/KlippyCosmetics/Expressions/CleanMarble/KlippyIconicSmile.png")
	# No CleanMarble eyes/pupils art exists yet — reuse Default's rather than
	# adding null-fallback branching to the apply code for a gap that
	# disappears the moment that art exists.
	marble_set.left_eye_texture = default_set.left_eye_texture
	marble_set.right_eye_texture = default_set.right_eye_texture
	marble_set.left_pupil_texture = default_set.left_pupil_texture
	marble_set.right_pupil_texture = default_set.right_pupil_texture
	_defs[marble_set.id] = marble_set
