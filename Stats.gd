class_name PetStats
extends Node

signal food_changed(value: float)
signal mood_changed(value: float)
signal health_changed(value: float)
signal feeding_enabled_changed(enabled: bool)
signal died

const MAX_FOOD := 100.0
const FOOD_DECAY_RATE := (MAX_FOOD * 0.1) / 3600.0

const MAX_HEALTH := 100.0
const THROW_HEALTH_LOSS := 0.1
const STARVATION_HEALTH_DECAY_RATE := 20.0 / 3600.0
const HEALING_FOOD_THRESHOLD := 50.0
const HEALTH_REGEN_RATE := 20.0 / 3600.0

const MAX_MOOD := 100.0
const MOOD_MID := 50.0
const MOOD_INCREASE_RATE := 30.0 / 3600.0
const MOOD_DECREASE_RATE := 30.0 / 3600.0

const WELL_FED_THRESHOLD := 95.0
const WELL_FED_MOOD_CAP := 80.0
const FED_THRESHOLD := 75.0
const FED_MOOD_CAP := 60.0
const VERY_HUNGRY_THRESHOLD := 50.0
const HUNGRY_MOOD_FLOOR := 40.0
const STARVING_THRESHOLD := 25.0
const VERY_HUNGRY_MOOD_FLOOR := 20.0
const STARVING_MOOD_FLOOR := 0.0

const LOW_HEALTH_MOOD_THRESHOLD := 50.0
const CRITICAL_HEALTH_THRESHOLD := 25.0
const POOR_HEALTH_MOOD_TARGET := 40.0
const CRITICAL_HEALTH_MOOD_TARGET := 20.0

var feeding_enabled := false
var food := MAX_FOOD
var mood := MOOD_MID
var health := MAX_HEALTH
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
		health = max(health - STARVATION_HEALTH_DECAY_RATE * delta, 0.0)
		health_changed.emit(health)
		if health <= 0.0:
			is_dead = true
			died.emit()
			return
	else:
		_apply_healing(delta)

	_update_mood(delta)


func _apply_healing(delta: float) -> void:
	var food_percent := food / MAX_FOOD * 100.0
	if food_percent <= HEALING_FOOD_THRESHOLD or health >= MAX_HEALTH:
		return

	var health_gain: float = min(HEALTH_REGEN_RATE * delta, MAX_HEALTH - health)
	if health_gain <= 0.0:
		return

	health += health_gain
	health_changed.emit(health)

	food = max(food - health_gain, 0.0)
	food_changed.emit(food)


func _update_mood(delta: float) -> void:
	var food_percent := food / MAX_FOOD * 100.0
	var target: float

	if food_percent > WELL_FED_THRESHOLD:
		target = WELL_FED_MOOD_CAP
	elif food_percent > FED_THRESHOLD:
		target = FED_MOOD_CAP
	elif food_percent > VERY_HUNGRY_THRESHOLD:
		target = HUNGRY_MOOD_FLOOR
	elif food_percent > STARVING_THRESHOLD:
		target = VERY_HUNGRY_MOOD_FLOOR
	else:
		target = STARVING_MOOD_FLOOR

	var health_percent := health / MAX_HEALTH * 100.0
	if health_percent < LOW_HEALTH_MOOD_THRESHOLD:
		var health_target := (
			CRITICAL_HEALTH_MOOD_TARGET if health_percent < CRITICAL_HEALTH_THRESHOLD
			else POOR_HEALTH_MOOD_TARGET
		)
		target = min(target, health_target)

	if is_equal_approx(mood, target):
		return

	var rate := MOOD_INCREASE_RATE if target > mood else MOOD_DECREASE_RATE
	mood = move_toward(mood, target, rate * delta)
	mood_changed.emit(mood)


func apply_throw_damage() -> void:
	if is_dead:
		return
	health = max(health - THROW_HEALTH_LOSS, 0.0)
	health_changed.emit(health)
	if health <= 0.0:
		is_dead = true
		died.emit()


func debug_adjust_food(delta: float) -> void:
	food = clamp(food + delta, 0.0, MAX_FOOD)
	food_changed.emit(food)


func debug_adjust_mood(delta: float) -> void:
	mood = clamp(mood + delta, 0.0, MAX_MOOD)
	mood_changed.emit(mood)


func debug_adjust_health(delta: float) -> void:
	health = clamp(health + delta, 0.0, MAX_HEALTH)
	health_changed.emit(health)
	if health <= 0.0 and not is_dead:
		is_dead = true
		died.emit()


func revive() -> void:
	if not is_dead:
		return
	is_dead = false
	food = MAX_FOOD
	health = MAX_HEALTH
	food_changed.emit(food)
	health_changed.emit(health)


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
		return "Starving"
	elif percent <= 25.0:
		return "Critical"
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


func get_health_status() -> String:
	var percent := health / MAX_HEALTH * 100.0
	if percent <= 0.0:
		return "Dead"
	elif percent < 25.0:
		return "Critical"
	elif percent < 50.0:
		return "Poor Health"
	elif percent < 75.0:
		return "Chipped"
	else:
		return "Healthy"
