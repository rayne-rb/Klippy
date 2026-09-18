class_name GuestLink
extends Node

## The Companion's second link: the one that reaches *another user's* server.
##
## A visit pairs this device with the friend's server as a "visitor" device (one
## human approval on their Devices page, remembered by [VisitSettings]) and then
## holds a socket there. On that server, this device and the friend's companion are
## just two devices, so the friend's server does all the routing — visit events go
## in targeted at the friend's companion and come back the same way. No server ever
## gained a feature for this; the link was already a hub.
##
## The surface deliberately mirrors [KlippyLink] — publish/event_received, a State
## enum, presence — so the visit slice can talk over either link without caring
## which. Unlike the main link it connects only on demand: while no friend portal
## exists there is nothing to say to the friend's server, so [member stay_connected]
## is false and the socket is left closed.

## An event arrived from the friend's server. [param payload] is the decoded
## payload object, empty if there was none.
signal event_received(type: String, payload: Dictionary, source: String)

## The connection state changed. See [enum State].
signal state_changed(state: State)

## A pairing code the user needs to confirm — on the *friend's* server UI.
signal pairing_code_ready(code: String)

## Pairing could not be completed.
signal pairing_failed(reason: String)

signal peers_changed

enum State {
	OFFLINE,
	PAIRING,
	CONNECTING,
	CONNECTED,
}

const PING_INTERVAL := 20.0
const RECONNECT_DELAY := 3.0

var state: State = State.OFFLINE

## Keep the socket alive (and reopen it when it drops) even with nothing to say.
## True from the moment a friend portal exists until it is banished.
var stay_connected := false

## The other devices currently on the friend's server, as {id, kind, name}.
var peers: Array[Dictionary] = []

## This device's id as the friend's server assigned it. Only meaningful while connected.
var device_id := ""

var _settings: VisitSettings
var _pairing: PairingClient
var _socket: WebSocketPeer
var _token_check: HTTPRequest
var _ping_timer := 0.0
var _reconnect_timer := 0.0
var _pending_reconnect := false


func _ready() -> void:
	_settings = VisitSettings.load_settings()

	_pairing = PairingClient.new()
	_pairing.name = "PairingClient"
	_pairing.code_ready.connect(func(code: String) -> void:
		print("[visit] pairing code %s - approve it on the friend's server" % code)
		pairing_code_ready.emit(code))
	_pairing.paired.connect(_on_paired)
	_pairing.failed.connect(_on_pairing_failed)
	add_child(_pairing)

	_token_check = HTTPRequest.new()
	_token_check.name = "TokenCheck"
	_token_check.timeout = 8.0
	_token_check.request_completed.connect(_on_token_checked)
	add_child(_token_check)

	set_process(false)


func is_paired() -> bool:
	return _settings.is_paired()


func is_connected_to_server() -> bool:
	return state == State.CONNECTED


func server_name() -> String:
	return _settings.server_name


## Sends an event to the friend's server, routed to the one device [param target]
## names. Visit traffic is always between two specific companions, so unlike the
## main link there is no broadcast path here: a missing target drops the event.
func publish(type: String, payload: Variant = null, target: String = "") -> void:
	if state != State.CONNECTED or _socket == null or target == "":
		return

	var envelope := {"type": type}
	if payload != null:
		envelope["payload"] = payload
	envelope["target"] = target

	_socket.send_text(JSON.stringify(envelope))


## The friend's companion to address visit events at, or "" when none is online.
func host_target() -> String:
	for peer in peers:
		if peer.get("kind", "") == LinkEvents.KIND_COMPANION:
			return str(peer.get("id", ""))
	return ""


## Pairs with [param base_url] as a visitor. [param ws_url] and [param server_id]
## and [param server_name] come off the same discovery beacon; they are remembered
## only once the human on the other end approves the code.
func begin_pairing(beacon: Dictionary) -> void:
	_settings.server_id = str(beacon.get("serverId", ""))
	_settings.base_url = str(beacon.get("baseUrl", ""))
	_settings.ws_url = str(beacon.get("wsUrl", ""))
	_settings.server_name = str(beacon.get("name", ""))

	_set_state(State.PAIRING)
	_pairing.begin(_settings.base_url, KlippyLink.device_name(), KlippyLink.platform_name(),
			LinkEvents.KIND_VISITOR)


## Drops the stored pairing and goes offline. Any friend portal out there is now
## pointing at a server that will not have us back until someone approves again.
func forget_pairing() -> void:
	_settings.clear()
	_close_socket()
	_set_state(State.OFFLINE)


## Abandon an in-flight handshake. Once the pairing is through and the socket is
## live this does nothing — that connection is a visit, not a handshake.
func cancel_pairing() -> void:
	if state != State.PAIRING:
		return

	_pairing.cancel()
	stay_connected = false
	_set_state(State.OFFLINE)


## Opens (or reopens) the socket if paired and [member stay_connected] is set.
func ensure_connected() -> void:
	if not stay_connected or not _settings.is_paired():
		return
	if state == State.CONNECTED or state == State.CONNECTING or state == State.PAIRING:
		return

	_close_socket()
	_set_state(State.CONNECTING)

	var headers := PackedStringArray(["Authorization: Bearer " + _settings.token])
	var err := _token_check.request(_settings.base_url + "/api/link/hello", headers)
	if err != OK:
		_on_connection_lost()


## Hangs up and stops caring until the next [method ensure_connected].
func disconnect_from_server() -> void:
	stay_connected = false
	_pending_reconnect = false
	_close_socket()
	_set_state(State.OFFLINE)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	print("[visit] %s" % State.keys()[state].to_lower())

	if state != State.CONNECTED and not peers.is_empty():
		peers.clear()
		peers_changed.emit()

	state_changed.emit(state)


func _on_paired(device_id: String, token: String) -> void:
	_settings.device_id = device_id
	_settings.token = token
	_settings.save()
	ensure_connected()


func _on_pairing_failed(reason: String) -> void:
	push_warning("Visit pairing failed: %s" % reason)
	pairing_failed.emit(reason)
	_set_state(State.OFFLINE)


func _on_token_checked(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	if not stay_connected:
		_set_state(State.OFFLINE)
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		_on_connection_lost()
		return

	if response_code == 401:
		# The friend's server stopped recognising us (revoked, or their database was
		# rebuilt). The pairing is dead; the next summon asks to be let in again.
		print("[visit] the friend's server no longer recognises this device")
		_settings.clear()
		_set_state(State.OFFLINE)
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
		push_warning("Visit link could not open %s (error %d)" % [_settings.ws_url, err])
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
			ensure_connected()
		return

	if _socket == null:
		return

	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state != State.CONNECTED:
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

		if type == LinkEvents.LINK_PING:
			publish(LinkEvents.LINK_PONG, null, str(envelope.get("source", "")))
			continue
		if type == LinkEvents.LINK_PONG:
			continue

		var payload: Dictionary = {}
		if typeof(envelope.get("payload")) == TYPE_DICTIONARY:
			payload = envelope["payload"]

		_track_presence(type, payload)

		event_received.emit(type, payload, str(envelope.get("source", "")))


func _track_presence(type: String, payload: Dictionary) -> void:
	match type:
		LinkEvents.LINK_WELCOME:
			device_id = str(payload.get("deviceId", ""))
			peers.clear()
			for entry in payload.get("peers", []):
				if typeof(entry) == TYPE_DICTIONARY:
					peers.append(_peer_from(entry))
			peers_changed.emit()

		LinkEvents.DEVICE_CONNECTED:
			var arrival := _peer_from(payload)
			if arrival["id"] == "":
				return
			for index in peers.size():
				if peers[index]["id"] == arrival["id"]:
					peers[index] = arrival
					peers_changed.emit()
					return
			peers.append(arrival)
			peers_changed.emit()

		LinkEvents.DEVICE_DISCONNECTED:
			var gone := str(payload.get("deviceId", ""))
			for index in peers.size():
				if peers[index]["id"] == gone:
					peers.remove_at(index)
					peers_changed.emit()
					return


func _peer_from(payload: Dictionary) -> Dictionary:
	return {
		"id": str(payload.get("deviceId", "")),
		"kind": str(payload.get("deviceKind", "")),
		"name": str(payload.get("deviceName", "")),
	}


func _maybe_ping(delta: float) -> void:
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		# The server answers pings itself; no target means the server never sees
		# this one reach a device, which is exactly right for a keepalive.
		publish(LinkEvents.LINK_PING, null, _host_or_self_target())


## Keepalives ride the same publish path as everything else, which demands a
## target. The server consumes ping/pong itself before routing, so any connected
## device's id will do — but when we have none, aim at the host companion anyway;
## an unsent ping costs nothing.
func _host_or_self_target() -> String:
	if device_id != "":
		return device_id
	return host_target()


func _on_connection_lost() -> void:
	_close_socket()
	if not stay_connected:
		_set_state(State.OFFLINE)
		return

	# Out on a visit the socket is the pet's lifeline home — VisitSession watches
	# for the state falling out of CONNECTED and brings him back. Here, just keep
	# trying to get the socket back.
	_set_state(State.OFFLINE)
	_pending_reconnect = true
	_reconnect_timer = RECONNECT_DELAY
	set_process(true)
