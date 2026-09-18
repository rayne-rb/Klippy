class_name ClipboardImageWriter
extends RefCounted

## Puts an image on this PC's clipboard.
##
## Text is one call — [method DisplayServer.clipboard_set] — but an image is not, because
## Godot has no matching setter. 4.7.1 exposes [method DisplayServer.clipboard_get_image]
## and [method DisplayServer.clipboard_has_image] and nothing that writes one, so this
## hands the job to whatever the platform already has for it.
##
## The image goes to a file first in every case. The Linux tools read a picture from a
## path or from standard input, and Godot can start a process but cannot pipe to one, so a
## path is the only door open.
##
## Verified on X11 with xclip. The Wayland, Windows and macOS branches are written from
## their documented behaviour and have not been run — there is no such machine here.

## Where the picture is handed over. Overwritten each time rather than accumulating.
const SCRATCH_PATH := "user://clipboard_apply.png"


## Puts [param png] on the clipboard. Returns "" when it worked, or a sentence saying why
## it did not.
static func write(png: PackedByteArray) -> String:
	var file := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	if file == null:
		return "Could not write the image to a temporary file."

	file.store_buffer(png)
	file.close()

	var path := ProjectSettings.globalize_path(SCRATCH_PATH)
	var command := _command_for(path)

	if command.is_empty():
		return "Putting an image on the clipboard is not supported on this system."

	var output := []
	var code := OS.execute(command["program"], command["arguments"], output, true)

	if code != 0:
		return "%s could not put the image on the clipboard." % command["program"]

	return ""


## The program and arguments that will take a PNG at [param path] and make it the
## clipboard's contents, or an empty dictionary when nothing here can.
static func _command_for(path: String) -> Dictionary:
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			# DisplayServer knows which session this actually is, which beats reading
			# WAYLAND_DISPLAY and guessing.
			if DisplayServer.get_name() == "wayland":
				# wl-copy reads the picture from standard input and nowhere else, so a
				# shell has to do the redirect that OS.execute cannot.
				return {
					"program": "sh",
					"arguments": ["-c", "wl-copy --type image/png < %s" % path.c_escape()],
				}

			return {
				"program": "xclip",
				"arguments": ["-selection", "clipboard", "-t", "image/png", "-i", path],
			}

		"Windows":
			# -STA because the Windows clipboard API is only callable from a
			# single-threaded apartment. SetImage copies the picture onto the clipboard
			# rather than lending it, so it outlives this process.
			return {
				"program": "powershell",
				"arguments": [
					"-NoProfile",
					"-STA",
					"-Command",
					"Add-Type -AssemblyName System.Windows.Forms,System.Drawing; " +
					"[System.Windows.Forms.Clipboard]::SetImage(" +
					"[System.Drawing.Image]::FromFile('%s'))" % path,
				],
			}

		"macOS":
			return {
				"program": "osascript",
				"arguments": [
					"-e",
					'set the clipboard to (read (POSIX file "%s") as «class PNGf»)' % path,
				],
			}

	return {}


## Whether an image can be put on the clipboard at all here, so a button can say so
## before it is pressed rather than after.
static func is_supported() -> bool:
	return not _command_for("").is_empty()
