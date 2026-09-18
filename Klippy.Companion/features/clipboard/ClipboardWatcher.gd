class_name ClipboardWatcher
extends Node

## Notices what gets copied on this PC and sends it up.
##
## Godot has no "the clipboard changed" signal — no desktop platform offers a reliable
## one — so this polls. The interval is a compromise between noticing a copy promptly and
## asking the windowing system for the selection over and over: on X11 every check is a
## round trip to whichever application currently owns the clipboard.
##
## Nothing is read at all while the skill is off. That is the whole guarantee the switch
## makes, so it is checked first and nowhere else.

## Something was copied and accepted by the server.
signal captured(kind: String)

## A copy could not be sent. [param reason] is already a sentence for a human.
signal capture_failed(reason: String)

const POLL_SECONDS := 1.0

## How long after we write to the clipboard ourselves to stop reading it.
##
## Applying an entry puts content back on this PC's clipboard, which the next poll would
## otherwise see as a fresh copy and send straight back up. The digest guard below catches
## that for text, but an image makes the round trip through the OS and a re-encode, so it
## can come back with different bytes and slip past. A short deaf spell right after our
## own write catches both. The cost is that a copy made in the second or so after clicking
## Copy is missed, and in that moment the thing that just copied was almost certainly us.
const SUPPRESS_SECONDS := 2.5

## Images above this are not worth sending and the server would refuse them anyway.
const MAX_IMAGE_BYTES := 8 * 1024 * 1024

var _client: ClipboardClient
var _settings: ClipboardSettings
var _timer: Timer

## What we last saw, so an unchanged clipboard is not sent over and over. Text is hashed
## from its bytes; an image from its raw pixels, which avoids re-encoding a PNG on every
## poll just to find out nothing has changed.
var _last_digest := ""

var _suppress_until := 0.0
var _in_flight := false


func setup(client: ClipboardClient, settings: ClipboardSettings) -> void:
	_client = client
	_settings = settings


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()


## Called after we put something on this PC's clipboard, so we do not send it back.
func note_written(digest: String) -> void:
	_last_digest = digest
	_suppress_until = Time.get_unix_time_from_system() + SUPPRESS_SECONDS


## Forgets what was last seen, so the next poll sends whatever is there now. Used when the
## skill is switched on: whatever is on the clipboard at that moment is fair game, and the
## user has just said so.
func reset() -> void:
	_last_digest = ""


func _poll() -> void:
	if _settings == null or not _settings.enabled:
		return

	if not KlippyLink.is_connected_to_server():
		return

	# One copy at a time. A big image can take longer than the poll interval to upload,
	# and starting a second send of the same thing helps nobody.
	if _in_flight:
		return

	if Time.get_unix_time_from_system() < _suppress_until:
		return

	# Images first: an application offering a picture often offers a filename as text
	# alongside it, and the picture is what was meant.
	if DisplayServer.clipboard_has_image():
		_poll_image()
	elif DisplayServer.clipboard_has():
		_poll_text()


func _poll_text() -> void:
	var text := DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		return

	var digest := _digest(text.to_utf8_buffer())
	if digest == _last_digest:
		return

	_last_digest = digest
	_in_flight = true
	_client.post_text(text, _settings.visibility, func(ok: bool, error: String) -> void:
		_in_flight = false
		if ok:
			captured.emit("text")
		else:
			# Let the next poll try again rather than sitting on a digest that never
			# made it to the server.
			_last_digest = ""
			capture_failed.emit(error)
	)


func _poll_image() -> void:
	var image := DisplayServer.clipboard_get_image()
	if image == null or image.is_empty():
		return

	# Hashed from the raw pixels rather than an encoded PNG: this runs every second, and
	# encoding a screenshot each time to find out it is the same screenshot is the one
	# expensive thing this loop could do.
	var digest := _digest(image.get_data())
	if digest == _last_digest:
		return

	_last_digest = digest

	var png := image.save_png_to_buffer()
	if png.is_empty():
		capture_failed.emit("That image could not be encoded.")
		return

	if png.size() > MAX_IMAGE_BYTES:
		capture_failed.emit("That image is too big to share (%d MB)." % (png.size() / 1024 / 1024))
		return

	_in_flight = true
	_client.post_image(png, _settings.visibility, func(ok: bool, error: String) -> void:
		_in_flight = false
		if ok:
			captured.emit("image")
		else:
			_last_digest = ""
			capture_failed.emit(error)
	)


static func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
