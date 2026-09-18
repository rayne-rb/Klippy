class_name ClipboardSettings
extends RefCounted

## Whether this PC shares its clipboard, and with whom.
##
## Its own file rather than a corner of the pet's save data, for the same reason
## [LinkSettings] keeps one: the slice owns its storage, so turning the skill off can
## never disturb the pet and vice versa.
##
## Off by default, and private by default when switched on. A clipboard carries
## passwords, card numbers and half-written messages, so neither of those defaults is
## one to be clever about.

const PATH := "user://klippy_clipboard.cfg"
const SECTION := "clipboard"

## Only this account's devices see what is copied here.
const VISIBILITY_GROUP := "group"

## Everyone on the server sees it, whichever account they are in.
const VISIBILITY_SERVER := "server"

var enabled := false
var visibility := VISIBILITY_GROUP


static func load_settings() -> ClipboardSettings:
	var settings := ClipboardSettings.new()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return settings

	settings.enabled = bool(config.get_value(SECTION, "enabled", false))
	settings.visibility = str(config.get_value(SECTION, "visibility", VISIBILITY_GROUP))

	# A file written by a newer version, or edited by hand, must not leave this sharing
	# more widely than the user last chose.
	if settings.visibility != VISIBILITY_SERVER:
		settings.visibility = VISIBILITY_GROUP

	return settings


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "enabled", enabled)
	config.set_value(SECTION, "visibility", visibility)
	config.save(PATH)


func is_shared_server_wide() -> bool:
	return visibility == VISIBILITY_SERVER
