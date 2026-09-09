class_name SaveData
extends RefCounted

const SAVE_PATH := "user://klippy_save.cfg"


static func save_data(data: Dictionary) -> void:
	var config := ConfigFile.new()
	for section in data:
		for key in data[section]:
			config.set_value(section, key, data[section][key])
	config.save(SAVE_PATH)


static func load_data() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return {}

	var data := {}
	for section in config.get_sections():
		data[section] = {}
		for key in config.get_section_keys(section):
			data[section][key] = config.get_value(section, key)
	return data
