class_name PetStats
extends Node

signal food_changed(value: float)
signal feeding_enabled_changed(enabled: bool)
signal died

const MAX_FOOD := 100.0
const FOOD_DECAY_RATE := (MAX_FOOD * 0.1) / 3600.0
const FEED_AMOUNT := 40.0

var feeding_enabled := false
var food := MAX_FOOD
var is_dead := false


func _process(delta: float) -> void:
	if not feeding_enabled or is_dead:
		return
	food = max(food - FOOD_DECAY_RATE * delta, 0.0)
	food_changed.emit(food)
	if food <= 0.0:
		is_dead = true
		died.emit()


func apply_offline_decay(elapsed_seconds: float) -> void:
	if not feeding_enabled or is_dead or elapsed_seconds <= 0.0:
		return
	food = max(food - FOOD_DECAY_RATE * elapsed_seconds, 0.0)
	if food <= 0.0:
		is_dead = true


func feed() -> void:
	if is_dead:
		return
	food = min(food + FEED_AMOUNT, MAX_FOOD)
	food_changed.emit(food)


func set_feeding_enabled(enabled: bool) -> void:
	feeding_enabled = enabled
	feeding_enabled_changed.emit(enabled)


func get_status() -> String:
	var percent := food / MAX_FOOD * 100.0
	if percent <= 0.0:
		return "Dead"
	elif percent <= 25.0:
		return "Starving"
	elif percent <= 50.0:
		return "Very Hungry"
	elif percent <= 75.0:
		return "Hungry"
	else:
		return "Full"
