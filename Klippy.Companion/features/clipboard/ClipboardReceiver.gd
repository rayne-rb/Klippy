class_name ClipboardReceiver
extends Node

## Puts an entry on this PC's clipboard when another of your devices asks.
##
## The request ([constant LinkEvents.CLIPBOARD_APPLY]) carries an entry id and nothing
## else. The content is fetched here, with this PC's own token, which is what makes the
## whole path safe to expose: being asked to apply an entry is not the same as being
## handed one, and a device can only ever end up with something it could have read anyway.
##
## The server will not route this event across accounts, so anything arriving here came
## from a device of yours.

## Something was applied. [param digest] is over the same bytes [ClipboardWatcher] hashes,
## so it can tell this apart from a fresh copy.
signal applied(digest: String, kind: String)

## An apply could not be completed. [param reason] is already a sentence.
signal apply_failed(reason: String)

var _client: ClipboardClient


func setup(client: ClipboardClient) -> void:
	_client = client


func _ready() -> void:
	KlippyLink.event_received.connect(_on_event_received)


func _on_event_received(type: String, payload: Dictionary, _source: String) -> void:
	if type != LinkEvents.CLIPBOARD_APPLY or _client == null:
		return

	var entry_id := str(payload.get("entryId", ""))
	if entry_id == "":
		return

	_client.fetch_content(entry_id, func(ok: bool, body: PackedByteArray) -> void:
		if not ok:
			apply_failed.emit("Could not fetch what was sent.")
			return

		# A PNG announces itself in its first eight bytes, which is a surer test than
		# anything the request could have claimed about itself.
		if _is_png(body):
			var error := ClipboardImageWriter.write(body)
			if error != "":
				apply_failed.emit(error)
				return

			var image := Image.new()
			if image.load_png_from_buffer(body) == OK:
				applied.emit(_digest(image.get_data()), "image")
			return

		var text := body.get_string_from_utf8()
		DisplayServer.clipboard_set(text)
		applied.emit(_digest(text.to_utf8_buffer()), "text")
	)


static func _is_png(bytes: PackedByteArray) -> bool:
	return (bytes.size() > 8
		and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47
		and bytes[4] == 0x0D and bytes[5] == 0x0A and bytes[6] == 0x1A and bytes[7] == 0x0A)


static func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
