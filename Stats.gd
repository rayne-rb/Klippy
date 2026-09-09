class_name PetStats
extends Node

signal hunger_changed(value: float)
signal feeding_enabled_changed(enabled: bool)

const MAX_HUNGER := 100.0
const HUNGER_INCREASE_RATE := 1.0
const FEED_AMOUNT := 40.0

var feeding_enabled := false
var hunger := 0.0


func _process(delta: float) -> void:
	if not feeding_enabled:
		return
	hunger = min(hunger + HUNGER_INCREASE_RATE * delta, MAX_HUNGER)
	hunger_changed.emit(hunger)


func feed() -> void:
	hunger = max(hunger - FEED_AMOUNT, 0.0)
	hunger_changed.emit(hunger)


func set_feeding_enabled(enabled: bool) -> void:
	feeding_enabled = enabled
	feeding_enabled_changed.emit(enabled)
