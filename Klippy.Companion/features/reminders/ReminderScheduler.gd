class_name ReminderScheduler
extends Node

## Keeps track of pending reminders, announces each one the moment it is due,
## and serializes them for the pet's save file so they survive a restart.
## Overdue reminders found in a save fire right away on the next frame — the
## user still gets them, just late.

signal reminder_due(reminder: Dictionary)
signal reminders_changed

var reminders: Array[Dictionary] = []
var _next_id := 1


## Pulls the reminders persisted by [method to_save_data] back in.
func setup(data: Dictionary) -> void:
	for entry in data.get("pending", []):
		var reminder := _normalize(entry)
		if not reminder.is_empty():
			reminders.append(reminder)
			_next_id = maxi(_next_id, int(reminder.get("id", 0)) + 1)


func _process(_delta: float) -> void:
	if reminders.is_empty():
		return

	var now := Time.get_unix_time_from_system()
	for i in range(reminders.size() - 1, -1, -1):
		if float(reminders[i].get("due_at", 0.0)) > now:
			continue
		var reminder := reminders[i]
		reminders.remove_at(i)
		# Fired means delivered: the nagging until it is clicked is the speech
		# bubble's business, so the reminder itself leaves the store here.
		reminders_changed.emit()
		reminder_due.emit(reminder)


func add_reminder(message: String, due_at: float) -> Dictionary:
	var reminder := {"id": _next_id, "message": message, "due_at": due_at}
	_next_id += 1
	reminders.append(reminder)
	reminders.sort_custom(_is_earlier)
	reminders_changed.emit()
	return reminder


func remove_reminder(id: int) -> void:
	for i in reminders.size():
		if int(reminders[i].get("id", -1)) == id:
			reminders.remove_at(i)
			reminders_changed.emit()
			return


func to_save_data() -> Dictionary:
	return {"pending": reminders.duplicate(true)}


func _is_earlier(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("due_at", 0.0)) < float(b.get("due_at", 0.0))


## Turns a loaded entry back into a well-formed reminder, dropping anything an
## outdated save could have mangled rather than surfacing a half-empty bubble.
func _normalize(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}

	var message := str(entry.get("message", "")).strip_edges()
	var due_at := float(entry.get("due_at", 0.0))
	if message.is_empty() or due_at <= 0.0:
		return {}

	return {"id": int(entry.get("id", 0)), "message": message, "due_at": due_at}
