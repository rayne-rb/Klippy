class_name KlippyPoints
extends Node

## Klippy Points (KP): a currency earned through play and spent on future
## purchases. Tracked as a plain running total alongside [PetStats] rather
## than inside it, since it isn't a vital — nothing decays it over time.

signal points_changed(value: int)

var points := 0


func load_points(saved_points: int) -> void:
	points = maxi(saved_points, 0)


func add_points(amount: int) -> void:
	if amount == 0:
		return
	points = maxi(points + amount, 0)
	points_changed.emit(points)


## Spends [param amount] if affordable, reporting whether it went through so
## callers can gate a purchase on the result instead of pre-checking the balance.
func spend_points(amount: int) -> bool:
	if amount <= 0 or amount > points:
		return false
	points -= amount
	points_changed.emit(points)
	return true


func debug_adjust_points(delta: int) -> void:
	add_points(delta)
