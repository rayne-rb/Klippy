class_name LinkSettings
extends RefCounted

## Where the Companion remembers which server it is paired with.
##
## Deliberately a separate file from the pet's save data: the link slice owns its own
## storage, so wiping a pairing cannot disturb the pet's stats and vice versa.

const PATH := "user://klippy_link.cfg"
const SECTION := "link"

var server_id := ""
var base_url := ""
var ws_url := ""
var device_id := ""
var token := ""


func is_paired() -> bool:
	return token != "" and ws_url != ""


static func load_settings() -> LinkSettings:
	var settings := LinkSettings.new()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return settings

	settings.server_id = config.get_value(SECTION, "server_id", "")
	settings.base_url = config.get_value(SECTION, "base_url", "")
	settings.ws_url = config.get_value(SECTION, "ws_url", "")
	settings.device_id = config.get_value(SECTION, "device_id", "")
	settings.token = config.get_value(SECTION, "token", "")
	return settings


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "server_id", server_id)
	config.set_value(SECTION, "base_url", base_url)
	config.set_value(SECTION, "ws_url", ws_url)
	config.set_value(SECTION, "device_id", device_id)
	config.set_value(SECTION, "token", token)
	config.save(PATH)


## Forgets the pairing so the next start goes looking for a server again.
func clear() -> void:
	server_id = ""
	base_url = ""
	ws_url = ""
	device_id = ""
	token = ""
	save()
