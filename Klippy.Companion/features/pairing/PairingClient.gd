class_name PairingClient
extends Node

## Walks the pairing handshake with a server that has just been discovered.
##
## We ask to be let in, are handed a short code, and then poll while a human confirms
## that same code on the server's Devices page. The token only ever arrives once, so
## the moment it does it goes straight to the caller to be saved.

signal code_ready(code: String)
signal paired(device_id: String, token: String)
signal failed(reason: String)

const POLL_INTERVAL := 1.5
## Slightly longer than the server's five minute request lifetime, so the server's
## own expiry is what ends this rather than a race between two timeouts.
const MAX_POLLS := 220

var _http: HTTPRequest
var _base_url := ""
var _request_id := ""
var _polls := 0
var _poll_timer := 0.0
var _polling := false
var _awaiting_response := false


func _ready() -> void:
	_http = HTTPRequest.new()
	# Pairing bodies are tiny; keep the timeout short so a server that vanished
	# mid-handshake does not hold us up.
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	set_process(false)


func begin(base_url: String, device_name: String, platform: String) -> void:
	_base_url = base_url.rstrip("/")
	_request_id = ""
	_polls = 0
	_poll_timer = 0.0
	_polling = false

	var body := JSON.stringify({
		"deviceKind": "companion",
		"deviceName": device_name,
		"platform": platform,
	})

	_send(HTTPClient.METHOD_POST, "/api/pairing/requests", body)


func cancel() -> void:
	_polling = false
	set_process(false)


func _send(method: int, path: String, body: String = "") -> void:
	if _awaiting_response:
		return

	_awaiting_response = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(_base_url + path, headers, method, body)
	if err != OK:
		_awaiting_response = false
		failed.emit("could not reach %s (error %d)" % [_base_url, err])


func _process(delta: float) -> void:
	if not _polling or _awaiting_response:
		return

	_poll_timer += delta
	if _poll_timer < POLL_INTERVAL:
		return

	_poll_timer = 0.0
	_polls += 1
	if _polls > MAX_POLLS:
		_polling = false
		set_process(false)
		failed.emit("nobody approved the pairing in time")
		return

	_send(HTTPClient.METHOD_GET, "/api/pairing/requests/%s" % _request_id)


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_awaiting_response = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_polling = false
		set_process(false)
		failed.emit("the server stopped responding (result %d)" % result)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_polling = false
		set_process(false)
		failed.emit("the server sent something unreadable")
		return

	var payload: Dictionary = parsed

	if _request_id == "":
		_on_request_created(response_code, payload)
	else:
		_on_poll_result(response_code, payload)


func _on_request_created(response_code: int, payload: Dictionary) -> void:
	if response_code != 200 or not payload.has("requestId"):
		failed.emit("the server refused the pairing request (HTTP %d)" % response_code)
		return

	_request_id = payload["requestId"]
	_polling = true
	set_process(true)
	code_ready.emit(payload.get("code", "??????"))


## Reads a string field that the server may legitimately have no value for.
##
## Dictionary.get() falls back to its default only when the key is *missing*, and a
## server that writes nulls sends the key with a null value instead, which then fails
## to assign to a String. Anything that is not a string reads as absent.
static func _text(payload: Dictionary, key: String) -> String:
	var value: Variant = payload.get(key)
	return value if value is String else ""


func _on_poll_result(response_code: int, payload: Dictionary) -> void:
	if response_code != 200:
		_polling = false
		set_process(false)
		failed.emit("the pairing request went away (HTTP %d)" % response_code)
		return

	match payload.get("status", ""):
		"pending":
			return
		"approved":
			_polling = false
			set_process(false)
			var token := _text(payload, "token")
			if token == "":
				# Approved, but the one-shot token was already collected or the
				# server restarted before we polled. Nothing usable; start over.
				failed.emit("the pairing was approved but the token was lost; try again")
			else:
				paired.emit(_text(payload, "deviceId"), token)
		"denied":
			_polling = false
			set_process(false)
			failed.emit("the pairing was declined")
		_:
			_polling = false
			set_process(false)
			failed.emit("the pairing request expired")
