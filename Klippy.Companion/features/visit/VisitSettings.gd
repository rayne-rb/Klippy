class_name VisitSettings
extends RefCounted

## Where the Companion remembers its standing invitation to another user's server —
## the pairing the friend portal reuses so a visit never needs a second approval.
##
## A separate file from the main link's [LinkSettings] on purpose: the two pairings
## point at different servers owned by different people, and forgetting one must
## never disturb the other.

const PATH := "user://klippy_visit.cfg"
const SECTION := "visit"

var server_id := ""
var base_url := ""
var ws_url := ""
var device_id := ""
var token := ""

## The server's advertised name, kept only so dialogs can say whose monitor this
## is without going back online.
var server_name := ""


func is_paired() -> bool:
	return token != "" and ws_url != ""


static func load_settings() -> VisitSettings:
	var settings := VisitSettings.new()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return settings

	settings.server_id = config.get_value(SECTION, "server_id", "")
	settings.base_url = config.get_value(SECTION, "base_url", "")
	settings.ws_url = config.get_value(SECTION, "ws_url", "")
	settings.device_id = config.get_value(SECTION, "device_id", "")
	settings.token = config.get_value(SECTION, "token", "")
	settings.server_name = config.get_value(SECTION, "server_name", "")
	return settings


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "server_id", server_id)
	config.set_value(SECTION, "base_url", base_url)
	config.set_value(SECTION, "ws_url", ws_url)
	config.set_value(SECTION, "device_id", device_id)
	config.set_value(SECTION, "token", token)
	config.set_value(SECTION, "server_name", server_name)
	config.save(PATH)


## Forgets the pairing so the next visit asks to be let in all over again.
func clear() -> void:
	server_id = ""
	base_url = ""
	ws_url = ""
	device_id = ""
	token = ""
	server_name = ""
	save()
