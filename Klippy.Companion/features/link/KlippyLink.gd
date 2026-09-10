extends Node

## The Companion's end of the link. Registered as an autoload, so any slice can reach
## it as [code]KlippyLink[/code] without being handed a reference.
##
## It owns the whole path to being connected: find a server, pair with it if we have
## not before, hold a WebSocket open, and put received events on a signal for whoever
## cares. Slices publish with [method publish] and listen with [signal event_received];
## none of them need to know any of this happened.
##
## Deliberately no class_name: the autoload name is the global identifier, and
## declaring both would collide.

## An event arrived. [param payload] is the decoded payload object, empty if there was none.
signal event_received(type: String, payload: Dictionary, source: String)

## The connection state changed. See [enum State].
signal state_changed(state: State)

## A pairing code the user needs to confirm on the server.
signal pairing_code_ready(code: String)

## Pairing could not be completed. Discovery starts over shortly after.
signal pairing_failed(reason: String)

enum State {
	OFFLINE,     ## Nothing going on yet.
	SEARCHING,   ## Looking for a server on the network.
	PAIRING,     ## Waiting for a human to approve us.
	CONNECTING,  ## Opening the socket.
	CONNECTED,   ## Live.
}

const PING_INTERVAL := 20.0
const RECONNECT_DELAY := 3.0
## Giving up on a stored address and searching again costs a few seconds, so only do
## it after the address has actually stopped working a couple of times.
const FAILURES_BEFORE_REDISCOVERY := 2

var state: State = State.OFFLINE

var _settings: LinkSettings
var _discovery: ServerDiscovery
var _pairing: PairingClient
var _socket: WebSocketPeer
var _token_check: HTTPRequest
var _ping_timer := 0.0
var _reconnect_timer := 0.0
var _consecutive_failures := 0
var _pending_reconnect := false


func _ready() -> void:
	_settings = LinkSettings.load_settings()

	_discovery = ServerDiscovery.new()
	_discovery.name = "ServerDiscovery"
	_discovery.server_found.connect(_on_server_found)
	add_child(_discovery)

	_pairing = PairingClient.new()
	_pairing.name = "PairingClient"
	_pairing.code_ready.connect(func(code: String) -> void:
		print("[link] pairing code %s - approve it on the server" % code)
		pairing_code_ready.emit(code))
	_pairing.paired.connect(_on_paired)
	_pairing.failed.connect(_on_pairing_failed)
	add_child(_pairing)

	_token_check = HTTPRequest.new()
	_token_check.name = "TokenCheck"
	_token_check.timeout = 8.0
	_token_check.request_completed.connect(_on_token_checked)
	add_child(_token_check)

	if _settings.is_paired():
		_connect_socket()
	else:
		_start_searching()


## True once the socket is open and events will actually go somewhere.
func is_connected_to_server() -> bool:
	return state == State.CONNECTED


## Sends an event to the server, which routes it to the other devices.
## Silently does nothing when offline: events are moments, not a queue to catch up on.
func publish(type: String, payload: Variant = null) -> void:
	if state != State.CONNECTED or _socket == null:
		return

	var envelope := {"type": type}
	if payload != null:
		envelope["payload"] = payload

	_socket.send_text(JSON.stringify(envelope))


## Throws away the current pairing and goes looking for a server again.
func forget_pairing() -> void:
	_settings.clear()
	_close_socket()
	_start_searching()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	print("[link] %s" % State.keys()[state].to_lower())
	state_changed.emit(state)


# --- Discovery ---------------------------------------------------------------

func _start_searching() -> void:
	_set_state(State.SEARCHING)
	_discovery.start()


func _on_server_found(beacon: Dictionary) -> void:
	_discovery.stop()

	var server_id: String = beacon.get("serverId", "")

	# Already paired with this server, just at a different address: adopt the new
	# one rather than making the user pair again after a DHCP lease changed.
	print("[link] found '%s' at %s" % [beacon.get("name", "?"), beacon.get("baseUrl", "?")])

	if _settings.is_paired() and _settings.server_id == server_id:
		_settings.base_url = beacon.get("baseUrl", "")
		_settings.ws_url = beacon.get("wsUrl", "")
		_settings.save()
		_connect_socket()
		return

	# A different server, or none stored: pair from scratch.
	_settings.server_id = server_id
	_settings.base_url = beacon.get("baseUrl", "")
	_settings.ws_url = beacon.get("wsUrl", "")

	_set_state(State.PAIRING)
	_pairing.begin(_settings.base_url, _device_name(), _platform())


func _on_paired(device_id: String, token: String) -> void:
	_settings.device_id = device_id
	_settings.token = token
	_settings.save()
	_connect_socket()


func _on_pairing_failed(reason: String) -> void:
	push_warning("Klippy pairing failed: %s" % reason)
	pairing_failed.emit(reason)
	# Back to searching: the server may come back, or the user may approve next time.
	_schedule_reconnect()


# --- Socket ------------------------------------------------------------------

## Confirms the stored token is still good before opening a socket with it.
##
## A revoked device, or a server whose database was rebuilt, otherwise leaves us
## retrying a dead credential forever with no way out but the Connection dialog.
## The socket handshake cannot tell us why it failed, but this endpoint can.
func _connect_socket() -> void:
	if not _settings.is_paired():
		_start_searching()
		return

	_close_socket()
	_set_state(State.CONNECTING)

	var headers := PackedStringArray(["Authorization: Bearer " + _settings.token])
	var err := _token_check.request(_settings.base_url + "/api/link/hello", headers)
	if err != OK:
		_on_connection_lost()


func _on_token_checked(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		# The server is unreachable rather than refusing us; keep the pairing.
		_on_connection_lost()
		return

	if response_code == 401:
		print("[link] the server no longer recognises this device; pairing again")
		_settings.clear()
		_start_searching()
		return

	if response_code != 200:
		_on_connection_lost()
		return

	_open_socket()


func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	var url := "%s?token=%s" % [_settings.ws_url, _settings.token.uri_encode()]
	var err := _socket.connect_to_url(url)
	if err != OK:
		push_warning("Klippy link could not open %s (error %d)" % [_settings.ws_url, err])
		_socket = null
		_on_connection_lost()
		return

	set_process(true)


func _close_socket() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_ping_timer = 0.0


func _process(delta: float) -> void:
	if _pending_reconnect:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_pending_reconnect = false
			if _consecutive_failures >= FAILURES_BEFORE_REDISCOVERY:
				_consecutive_failures = 0
				_start_searching()
			else:
				_connect_socket()
		return

	if _socket == null:
		return

	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state != State.CONNECTED:
				_consecutive_failures = 0
				_set_state(State.CONNECTED)
			_drain_packets()
			_maybe_ping(delta)
		WebSocketPeer.STATE_CLOSED:
			_on_connection_lost()
		_:
			pass


func _drain_packets() -> void:
	while _socket != null and _socket.get_available_packet_count() > 0:
		var text := _socket.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		var envelope: Dictionary = parsed
		var type: String = envelope.get("type", "")
		if type == "":
			continue

		# Keepalives never leave this node.
		if type == LinkEvents.LINK_PING:
			publish(LinkEvents.LINK_PONG)
			continue
		if type == LinkEvents.LINK_PONG:
			continue

		var payload: Dictionary = {}
		if typeof(envelope.get("payload")) == TYPE_DICTIONARY:
			payload = envelope["payload"]

		event_received.emit(type, payload, str(envelope.get("source", "")))


func _maybe_ping(delta: float) -> void:
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		publish(LinkEvents.LINK_PING)


func _on_connection_lost() -> void:
	_consecutive_failures += 1
	_close_socket()
	_schedule_reconnect()


func _schedule_reconnect() -> void:
	_set_state(State.OFFLINE)
	_pending_reconnect = true
	_reconnect_timer = RECONNECT_DELAY
	set_process(true)


# --- Identity ----------------------------------------------------------------

func _device_name() -> String:
	# HOSTNAME is a shell variable and is usually not exported to a windowed app, so
	# fall back through the ones that are before giving up on naming the machine.
	for variable in ["HOSTNAME", "COMPUTERNAME", "HOST", "USER", "USERNAME"]:
		var value := OS.get_environment(variable)
		if value != "":
			return "Klippy on %s" % value
	return "Klippy on this PC"


func _platform() -> String:
	return "%s / Godot %s" % [OS.get_name(), Engine.get_version_info().get("string", "4")]
