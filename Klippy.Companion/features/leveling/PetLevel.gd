class_name PetLevel
extends Node

## Klippy's XP and level. Starts at level 0; every [constant XP_PER_LEVEL]
## points of total XP earned advances one level. XP is never spent or reset
## on level-up — level is simply derived from the running total, so it's
## always reproducible from a single saved number.

signal xp_changed(value: float)
signal level_changed(new_level: int)

const XP_PER_LEVEL := 1000.0

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
