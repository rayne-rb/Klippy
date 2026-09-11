# Headless sanity check for the Companion.
#
# Klippy itself cannot run headless (it drives real windows through DisplayServer),
# so this loads every script and the main scene instead: it catches parse errors,
# broken class_name references and stale resource paths, which is most of what a
# folder reshuffle can break.
extends SceneTree


func _init() -> void:
	var failures: Array[String] = []

	var autoloads := _autoload_names()
	var scripts := _find_scripts("res://")
	var checked := 0
	var skipped := 0

	for path in scripts:
		# Reloading the script that is currently executing always fails; skip the
		# tooling folder rather than report itself.
		if path.begins_with("res://tools/"):
			continue

		# --script replaces the main loop, so autoload singletons are never
		# registered and any script naming one fails to compile here even though it
		# is perfectly fine at runtime. Those are covered by the headless run in
		# tools/check.sh instead.
		if _references_autoload(path, autoloads):
			skipped += 1
			continue

		var script: Resource = load(path)
		if script == null:
			failures.append("could not load %s" % path)
			continue

		# load() can hand back a GDScript object that failed to compile, so ask it
		# to reload and read the error code rather than trusting a non-null result.
		if script is GDScript:
			checked += 1
			var err: int = (script as GDScript).reload()
			if err != OK:
				failures.append("parse error in %s (error %d)" % [path, err])

	print("Checked %d scripts (%d skipped as autoload-dependent)" % [checked, skipped])

	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	print("Main scene: %s" % main_scene)
	if not ResourceLoader.exists(main_scene):
		failures.append("main scene missing: %s" % main_scene)
	else:
		# Read the scene's references rather than instantiating it. Loading it would
		# compile its script, which names an autoload that does not exist under
		# --script, and the resulting error says nothing about the scene. Path
		# integrity is what a folder move actually threatens, and that is textual.
		failures.append_array(_check_scene_references(main_scene))

	for autoload_name in _autoload_names():
		var value: String = ProjectSettings.get_setting("autoload/%s" % autoload_name, "")
		var path := value.trim_prefix("*")
		if not ResourceLoader.exists(path):
			failures.append("autoload %s points at a missing script: %s" % [autoload_name, path])
		else:
			print("Autoload %s -> %s" % [autoload_name, path])

	print("")
	if failures.is_empty():
		print("VALIDATION PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		print("VALIDATION FAILED (%d)" % failures.size())
		quit(1)


## Confirms every res:// path a scene points at still exists.
func _check_scene_references(scene_path: String) -> Array[String]:
	var problems: Array[String] = []
	var file := FileAccess.open(scene_path, FileAccess.READ)
	if file == null:
		problems.append("could not read %s" % scene_path)
		return problems

	var source := file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile('path="(res://[^"]+)"')

	var found := 0
	for match in regex.search_all(source):
		var referenced := match.get_string(1)
		found += 1
		if not ResourceLoader.exists(referenced) and not FileAccess.file_exists(referenced):
			problems.append("%s points at a missing resource: %s" % [scene_path, referenced])
		else:
			print("  references %s" % referenced)

	if found == 0:
		problems.append("%s references nothing, which is unexpected" % scene_path)

	return problems


## True when the file mentions an autoload singleton by name.
func _references_autoload(path: String, autoloads: PackedStringArray) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var source := file.get_as_text()
	file.close()

	for name in autoloads:
		if source.contains(name):
			return true
	return false


func _autoload_names() -> PackedStringArray:
	var names := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var name: String = property.get("name", "")
		if name.begins_with("autoload/"):
			names.append(name.trim_prefix("autoload/"))
	return names


func _find_scripts(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var directory := DirAccess.open(root)
	if directory == null:
		return found

	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var full := root.path_join(entry) if root != "res://" else "res://" + entry
		if directory.current_is_dir():
			found.append_array(_find_scripts(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = directory.get_next()
	directory.list_dir_end()
	return found
