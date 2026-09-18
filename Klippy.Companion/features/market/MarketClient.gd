class_name MarketClient
extends Node

## Talks to a Klippy Server's /api/market endpoints over plain HTTP. Listing and
## buying both want a real success-or-failure answer (insufficient room, the item
## already sold, the server rejected the price) — that is what HTTP gives cleanly.
## Only a payout to a seller who happens to be offline rides the link instead (see
## RemoteControl and LinkEvents.MARKET_PAYOUT).
##
## Requests queue rather than overlap: a single HTTPRequest node can only run one
## at a time, and dropping a sell or buy on the floor because a listings refresh
## was already in flight would lose the user's click rather than just delay it.

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _busy := false
var _current_callback: Callable


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Every active listing, server-wide. [param on_done] is called with (ok: bool, listings: Array).
func list_listings(on_done: Callable) -> void:
	_enqueue(HTTPClient.METHOD_GET, "/api/market/listings", "", func(ok: bool, _code: int, payload: Variant) -> void:
		if ok and typeof(payload) == TYPE_ARRAY:
			on_done.call(true, payload)
		else:
			on_done.call(false, [])
	)


## Lists [param item_type] for [param price] KP. [param on_done] is called with (ok: bool, error: String).
func sell(item_type: String, price: int, on_done: Callable) -> void:
	var body := JSON.stringify({"itemType": item_type, "price": price})
	_enqueue(HTTPClient.METHOD_POST, "/api/market/listings", body, func(ok: bool, code: int, _payload: Variant) -> void:
		on_done.call(ok, "" if ok else _error_for(code))
	)


## Buys [param listing_id]. [param on_done] is called with (ok, item_type, price, error).
func buy(listing_id: String, on_done: Callable) -> void:
	var path := "/api/market/listings/%s/buy" % listing_id
	_enqueue(HTTPClient.METHOD_POST, path, "", func(ok: bool, code: int, payload: Variant) -> void:
		if ok and typeof(payload) == TYPE_DICTIONARY:
			on_done.call(true, str(payload.get("itemType", "")), int(payload.get("price", 0)), "")
		else:
			on_done.call(false, "", 0, _error_for(code))
	)


func _error_for(code: int) -> String:
	match code:
		401:
			return "Not connected to the server."
		409:
			return "That item is no longer available."
		400:
			return "The server rejected that."
		_:
			return "Could not reach the server."


func _enqueue(method: int, path: String, body: String, callback: Callable) -> void:
	_queue.append({"method": method, "path": path, "body": body, "callback": callback})
	_drain()


func _drain() -> void:
	if _busy or _queue.is_empty():
		return

	var request: Dictionary = _queue.pop_front()
	_current_callback = request["callback"]

	if not KlippyLink.is_connected_to_server():
		var callback: Callable = _current_callback
		callback.call(false, 0, null)
		_drain()
		return

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + KlippyLink.auth_token(),
	])

	_busy = true
	var err := _http.request(
		KlippyLink.server_url() + request["path"], headers, request["method"], request["body"])
	if err != OK:
		_busy = false
		var callback: Callable = _current_callback
		callback.call(false, 0, null)
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
		callback.call(false, response_code, null)
		_drain()
		return

	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	callback.call(response_code >= 200 and response_code < 300, response_code, payload)
	_drain()
