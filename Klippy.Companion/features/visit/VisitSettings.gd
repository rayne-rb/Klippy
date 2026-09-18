class_name VisitSettings
extends RefCounted

## Which friends may walk onto this monitor without knocking first.
##
## Its own file rather than a corner of the pet's save data, for the same reason
## [LinkSettings] and [ClipboardSettings] keep one: the slice owns its storage.
##
## Empty by default, and it only ever fills up by somebody clicking "Always" on a knock.
## Your own machines are not in here and never need to be — a visit from another device
## of your own account is not a stranger at the door, so it is never asked about.
##
## Friends are remembered by device id, which is what the server routes a visit to and
## what it stays for as long as that PC stays paired here. A friend who re-pairs comes
## back as a new device and knocks again, which is the right way round: the name is a
## label their machine chose, and the id is the thing that was actually let in.

const PATH := "user://klippy_visits.cfg"
const SECTION := "visits"
const ALLOWED_KEY := "allowed"

## Device id -> the name to show when listing them, e.g. "Klippy on studio-pc (sam)".
var allowed: Dictionary = {}


static func load_settings() -> VisitSettings:
	var settings := VisitSettings.new()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return settings

	var stored: Variant = config.get_value(SECTION, ALLOWED_KEY, {})
	if typeof(stored) != TYPE_DICTIONARY:
		return settings

	# A file written by hand, or by a newer version, must not end up letting somebody in
	# on the strength of a value this cannot read.
	for id in stored:
		if typeof(id) == TYPE_STRING and str(id) != "":
			settings.allowed[str(id)] = str(stored[id])

	return settings


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, ALLOWED_KEY, allowed)
	config.save(PATH)


func is_allowed(device_id: String) -> bool:
	return allowed.has(device_id)


func allow(device_id: String, display_name: String) -> void:
	if device_id == "":
		return
	allowed[device_id] = display_name
	save()


func forget(device_id: String) -> void:
	if allowed.erase(device_id):
		save()


## The remembered friends, newest last, as [code]{id, name}[/code] — for the list that
## offers to forget them again.
func friends() -> Array[Dictionary]:
	var listed: Array[Dictionary] = []
	for id in allowed:
		listed.append({"id": str(id), "name": str(allowed[id])})
	return listed
