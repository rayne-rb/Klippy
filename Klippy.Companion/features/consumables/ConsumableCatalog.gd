class_name ConsumableCatalog
extends RefCounted

## Every consumable kind Klippy can be fed or summon from a portal, keyed by
## [member ConsumableDef.id]. Adding a new consumable is adding one more
## [method _register] call here — nothing that spawns, saves, or feeds
## consumables needs to know the specific list.

const APPLE := "apple"
const JELLY := "jelly"
const XP_GEM := "xp_gem"
const COIN := "coin"

static var _defs: Dictionary = {}
static var _initialized := false


static func get_def(id: String) -> ConsumableDef:
	_ensure_initialized()
	return _defs.get(id, _defs[APPLE])


static func ids() -> Array:
	_ensure_initialized()
	return _defs.keys()


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	var apple := ConsumableDef.new()
	apple.id = APPLE
	apple.display_name = "Apple"
	apple.texture = preload("res://assets/Consumables/KlippyAppleFood.png")
	apple.feed_amount = 5.0
	_defs[apple.id] = apple

	var jelly := ConsumableDef.new()
	jelly.id = JELLY
	jelly.display_name = "Jelly"
	jelly.texture = preload("res://assets/Consumables/KlippyJellyFood.png")
	jelly.feed_amount = 5.0
	jelly.buff_duration = 20.0
	jelly.bounce_damping_override = 0.95
	jelly.damage_immune = true
	jelly.bounce_xp_reward = 0.1
	jelly.bounce_mood_reward = 0.5
	_defs[jelly.id] = jelly

	var xp_gem := ConsumableDef.new()
	xp_gem.id = XP_GEM
	xp_gem.display_name = "XP Gem"
	xp_gem.texture = preload("res://assets/Consumables/KlippyXpGem.png")
	# A gem, not a snack — no hunger benefit, just the XP.
	xp_gem.feed_amount = 0.0
	xp_gem.xp_reward = 100.0
	_defs[xp_gem.id] = xp_gem

	var coin := ConsumableDef.new()
	coin.id = COIN
	coin.display_name = "Coin"
	coin.texture = preload("res://assets/Consumables/KlippyCoin.png")
	# Currency, not a snack — no hunger benefit, just Klippy Points.
	coin.feed_amount = 0.0
	coin.points_reward = 10
	_defs[coin.id] = coin
