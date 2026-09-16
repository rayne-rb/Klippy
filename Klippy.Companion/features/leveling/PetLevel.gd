class_name PetLevel
extends Node

## Klippy's XP and level. Starts at level 0; every [constant XP_PER_LEVEL]
## points of total XP earned advances one level. XP is never spent or reset
## on level-up — level is simply derived from the running total, so it's
## always reproducible from a single saved number.

signal xp_changed(value: float)
signal level_changed(new_level: int)

const XP_PER_LEVEL := 1000.0

const PASSIVE_XP_PER_MINUTE := 0.1
const ECSTATIC_PASSIVE_XP_PER_MINUTE := 0.2

var xp := 0.0
var level := 0


func load_xp(saved_xp: float) -> void:
	xp = max(saved_xp, 0.0)
	level = int(xp / XP_PER_LEVEL)


func add_xp(amount: float) -> void:
	if amount == 0.0:
		return
	xp = max(xp + amount, 0.0)
	xp_changed.emit(xp)
	_recompute_level()


## Passive trickle of XP for simply being alive, ticked every frame with the
## elapsed [param delta] rather than a once-a-minute timer, so it stays smooth
## and needs no separate catch-up logic. Doubles while [param ecstatic] (mood
## status "Ecstatic") holds.
func apply_passive_gain(delta: float, ecstatic: bool) -> void:
	var rate_per_minute := ECSTATIC_PASSIVE_XP_PER_MINUTE if ecstatic else PASSIVE_XP_PER_MINUTE
	add_xp(rate_per_minute / 60.0 * delta)


## True once Klippy has reached the level something is gated behind.
func is_unlocked(required_level: int) -> bool:
	return level >= required_level


## XP earned so far within the current level, for progress display.
func xp_into_level() -> float:
	return xp - level * XP_PER_LEVEL


func debug_adjust_xp(delta: float) -> void:
	add_xp(delta)


## Jumps a whole level at a time by snapping XP to that level's threshold,
## rather than needing 1000 XP button presses to test an unlock.
func debug_adjust_level(delta: int) -> void:
	var new_level := maxi(level + delta, 0)
	xp = new_level * XP_PER_LEVEL
	xp_changed.emit(xp)
	_recompute_level()


func _recompute_level() -> void:
	var new_level := int(xp / XP_PER_LEVEL)
	if new_level == level:
		return
	level = new_level
	level_changed.emit(level)
