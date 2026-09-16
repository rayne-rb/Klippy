class_name FoodCatalog
extends RefCounted

## Every food kind Klippy can be fed, keyed by [member FoodDef.id]. Adding a
## new food is adding one more [method _register] call here — nothing that
## spawns, saves, or feeds food needs to know the specific list.

const APPLE := "apple"
const JELLY := "jelly"

static var _defs: Dictionary = {}
static var _initialized := false


static func get_def(id: String) -> FoodDef:
	_ensure_initialized()
	return _defs.get(id, _defs[APPLE])


static func ids() -> Array:
	_ensure_initialized()
	return _defs.keys()


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	var apple := FoodDef.new()
	apple.id = APPLE
	apple.display_name = "Apple"
	apple.texture = preload("res://assets/Food/KlippyAppleFood.png")
	apple.feed_amount = 5.0
	_defs[apple.id] = apple

	var jelly := FoodDef.new()
	jelly.id = JELLY
	jelly.display_name = "Jelly"
	jelly.texture = preload("res://assets/Food/KlippyJellyFood.png")
	jelly.feed_amount = 5.0
	jelly.buff_duration = 20.0
	jelly.bounce_damping_override = 0.95
	jelly.damage_immune = true
	jelly.bounce_xp_reward = 0.1
	jelly.bounce_mood_reward = 0.5
	_defs[jelly.id] = jelly
