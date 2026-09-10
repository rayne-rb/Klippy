class_name PetStats
extends Node

signal food_changed(value: float)
signal mood_changed(value: float)
signal feeding_enabled_changed(enabled: bool)
signal died

const MAX_FOOD := 100.0
const FOOD_DECAY_RATE := (MAX_FOOD * 0.1) / 3600.0

const MAX_MOOD := 100.0
const MOOD_MID := 50.0
const MOOD_INCREASE_RATE := 5.0 / 3600.0
const MOOD_DECREASE_RATE := 5.0 / 3600.0

const WELL_FED_THRESHOLD := 95.0
const WELL_FED_MOOD_CAP := 80.0
const FED_THRESHOLD := 75.0
const FED_MOOD_CAP := 60.0
const VERY_HUNGRY_THRESHOLD := 50.0
const HUNGRY_MOOD_FLOOR := 40.0
const STARVING_THRESHOLD := 25.0
const VERY_HUNGRY_MOOD_FLOOR := 20.0
const STARVING_MOOD_FLOOR := 0.0

var feeding_enabled := false
var food := MAX_FOOD
var mood := MOOD_MID
var is_dead := false


func _process(delta: float) -> void:
	_advance(delta)


func apply_offline_progress(elapsed_seconds: float) -> void:
	_advance(elapsed_seconds)


func _advance(delta: float) -> void:
	if not feeding_enabled or is_dead or delta <= 0.0:
		return

	food = max(food - FOOD_DECAY_RATE * delta, 0.0)
	food_changed.emit(food)
	if food <= 0.0:
		is_dead = true
		died.emit()
		return

	_update_mood(delta)


func _update_mood(delta: float) -> void:
	var food_percent := food / MAX_FOOD * 100.0
	var target: float
	var rate: float

	if food_percent > WELL_FED_THRESHOLD:
		target = WELL_FED_MOOD_CAP
		rate = MOOD_INCREASE_RATE
	elif food_percent > FED_THRESHOLD:
		target = FED_MOOD_CAP
		rate = MOOD_INCREASE_RATE
	elif food_percent > VERY_HUNGRY_THRESHOLD:
		target = HUNGRY_MOOD_FLOOR
		rate = MOOD_DECREASE_RATE
	elif food_percent > STARVING_THRESHOLD:
		target = VERY_HUNGRY_MOOD_FLOOR
		rate = MOOD_DECREASE_RATE
	else:
		target = STARVING_MOOD_FLOOR
		rate = MOOD_DECREASE_RATE

	if is_equal_approx(mood, target):
		return

	mood = move_toward(mood, target, rate * delta)
	mood_changed.emit(mood)


func feed(amount: float) -> void:
	if is_dead:
		return
	food = min(food + amount, MAX_FOOD)
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


func get_mood_status() -> String:
	if mood > 80.0:
		return "Ecstatic"
	elif mood > 60.0:
		return "Happy"
	elif mood > 40.0:
		return "Content"
	elif mood > 20.0:
		return "Sad"
	else:
		return "Miserable"
