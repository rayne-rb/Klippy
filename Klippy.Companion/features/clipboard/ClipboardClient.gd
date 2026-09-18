class_name ClipboardClient
extends Node

## Talks to a Klippy Server's /api/clipboard endpoints over plain HTTP.
##
## Everything the clipboard moves goes this way rather than over the link. Writes want a
## real answer — too large, a duplicate, not yours — and the content itself has no
## business on a socket that archives every payload that crosses it. See
## LinkEvents.CLIPBOARD_ENTRY for the rest of that reasoning.
##
## Requests queue rather than overlap, same as [MarketClient]: one HTTPRequest node runs
## one call at a time, and dropping a copy because a refresh was in flight would lose
## something the user did.

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _busy := false
var _current_callback: Callable


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## The board: our own account's entries plus anything shared server-wide.
## [param on_done] is called with (ok: bool, entries: Array).
func list(on_done: Callable) -> void:
	_enqueue(HTTPClient.METHOD_GET, "/api/clipboard", PackedByteArray(), "",
		func(ok: bool, _code: int, body: PackedByteArray) -> void:
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if ok else null
			if ok and typeof(parsed) == TYPE_ARRAY:
				on_done.call(true, parsed)
			else:
				on_done.call(false, [])
	)


## Records something copied here. [param on_done] is called with (ok: bool, error: String).
func post_text(text: String, visibility: String, on_done: Callable) -> void:
	var body := JSON.stringify({"text": text, "visibility": visibility})
	_enqueue(HTTPClient.METHOD_POST, "/api/clipboard", body.to_utf8_buffer(), "application/json",
		func(ok: bool, code: int, _body: PackedByteArray) -> void:
			on_done.call(ok, "" if ok else _error_for(code))
	)


## The same for an image, posted as a raw PNG body — far simpler to produce from here
## than a multipart form, and the server takes it either way.
func post_image(png: PackedByteArray, visibility: String, on_done: Callable) -> void:
	var path := "/api/clipboard/image?visibility=%s" % visibility.uri_encode()
	_enqueue(HTTPClient.METHOD_POST, path, png, "image/png",
		func(ok: bool, code: int, _body: PackedByteArray) -> void:
			on_done.call(ok, "" if ok else _error_for(code))
	)


## One entry's content. [param on_done] is called with (ok: bool, body: PackedByteArray).
func fetch_content(entry_id: String, on_done: Callable) -> void:
	_enqueue(HTTPClient.METHOD_GET, "/api/clipboard/%s/content" % entry_id, PackedByteArray(), "",
		func(ok: bool, _code: int, body: PackedByteArray) -> void:
			on_done.call(ok, body)
	)


func delete_entry(entry_id: String, on_done: Callable) -> void:
	_enqueue(HTTPClient.METHOD_DELETE, "/api/clipboard/%s" % entry_id, PackedByteArray(), "",
		func(ok: bool, code: int, _body: PackedByteArray) -> void:
			on_done.call(ok, "" if ok else _error_for(code))
	)


## Asks one of our own devices to put [param entry_id] on its clipboard. The server
## refuses to carry this to a device in another account, so there is nothing to check here.
func apply_to(entry_id: String, target_device_id: String, on_done: Callable) -> void:
	var body := JSON.stringify({"targetDeviceId": target_device_id})
	_enqueue(HTTPClient.METHOD_POST, "/api/clipboard/%s/apply" % entry_id,
		body.to_utf8_buffer(), "application/json",
		func(ok: bool, code: int, _body: PackedByteArray) -> void:
			on_done.call(ok, "" if ok else _error_for(code))
	)


func _error_for(code: int) -> String:
	match code:
		401:
			return "Not connected to the server."
		403:
			return "This PC has not been approved into an account yet."
		404:
			return "That entry is gone."
		409:
			return "That device is not connected."
		400:
			return "The server would not take that."
		_:
			return "Could not reach the server."


func _enqueue(method: int, path: String, body: PackedByteArray, content_type: String,
		callback: Callable) -> void:
	_queue.append({
		"method": method,
		"path": path,
		"body": body,
		"content_type": content_type,
		"callback": callback,
	})
	_drain()


func _drain() -> void:
	if _busy or _queue.is_empty():
		return

	var request: Dictionary = _queue.pop_front()
	_current_callback = request["callback"]

	if not KlippyLink.is_connected_to_server():
		var callback: Callable = _current_callback
		callback.call(false, 0, PackedByteArray())
		_drain()
		return

	var headers := PackedStringArray(["Authorization: Bearer " + KlippyLink.auth_token()])
	var content_type: String = request["content_type"]
	if content_type != "":
		headers.append("Content-Type: " + content_type)

	_busy = true
	# request_raw throughout, not request: a PNG is bytes, and routing text through the
	# same call keeps one code path rather than two that must stay in step.
	var err := _http.request_raw(
		KlippyLink.server_url() + request["path"], headers, request["method"], request["body"])
	if err != OK:
		_busy = false
		var callback: Callable = _current_callback
		callback.call(false, 0, PackedByteArray())
		_drain()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_busy = false
	var callback: Callable = _current_callback

	if result != HTTPRequest.RESULT_SUCCESS:
		callback.call(false, response_code, PackedByteArray())
		_drain()
		return

	callback.call(response_code >= 200 and response_code < 300, response_code, body)
	_drain()
