class_name AudioRelaySkill
extends SkillCard

## Plays this PC's sound on a paired phone.
##
## The Companion does none of the work and carries none of the audio: the server
## captures and encodes it, the phone receives it over UDP and plays it. All this
## card does is ask a chosen phone to start listening ([constant
## LinkEvents.AUDIO_CAST_REQUEST], addressed to that phone alone) and read
## [constant LinkEvents.AUDIO_CAST_STATE] to say what came of it.
##
## Asking the phone rather than telling the server to push a stream at it is
## deliberate: the phone is the only end that knows whether it can play right now,
## and that stays true however the relay was set off.

## The phone gives up on its own negotiation at 10s, so anything past that is an
## answer that is not coming.
const ANSWER_TIMEOUT := 12.0

const CHANNELS := 2

var _picker: OptionButton
var _timeout: Timer
var _state_fetch: HTTPRequest

## Connected phones, as the link describes them.
var _targets: Array[Dictionary] = []
var _selected_id := ""

## Device id we are waiting on, and what we asked it for. Empty when not waiting.
var _waiting_for := ""
var _waiting_enabled := false

## Device id -> is the audio actually arriving there, from the last cast state.
var _listeners: Dictionary = {}

## Shown once in place of the ready line when the last attempt went nowhere.
var _note := ""


func _ready() -> void:
	super._ready()
	set_title("Audio Relay")
	set_description("Play this PC's sound on your phone — speaker or headphones.")

	# Only worth showing when there is actually a choice to make.
	_picker = OptionButton.new()
	_picker.visible = false
	_picker.item_selected.connect(_on_target_picked)
	extra.add_child(_picker)

	_timeout = Timer.new()
	_timeout.one_shot = true
	_timeout.wait_time = ANSWER_TIMEOUT
	_timeout.timeout.connect(_on_answer_timeout)
	add_child(_timeout)

	_state_fetch = HTTPRequest.new()
	_state_fetch.timeout = 5.0
	_state_fetch.request_completed.connect(_on_state_fetched)
	add_child(_state_fetch)

	action_pressed.connect(_on_action_pressed)
	KlippyLink.peers_changed.connect(_on_peers_changed)
	KlippyLink.state_changed.connect(_on_link_state_changed)
	KlippyLink.event_received.connect(_on_event_received)

	_on_peers_changed()
	_fetch_state()


func _on_action_pressed() -> void:
	var target := _selected()
	if target.is_empty():
		return

	_note = ""
	var device_id: String = target["id"]
	var start := not _listeners.has(device_id)

	var payload := {"enabled": start}
	if start:
		payload["channels"] = CHANNELS

	KlippyLink.publish(LinkEvents.AUDIO_CAST_REQUEST, payload, device_id)

	_waiting_for = device_id
	_waiting_enabled = start
	_timeout.start()
	_refresh()


func _on_event_received(type: String, payload: Dictionary, _source: String) -> void:
	if type != LinkEvents.AUDIO_CAST_STATE:
		return
	_read_cast_state(payload)
	_refresh()


## A cast already running when this card opened was announced before it existed —
## [constant LinkEvents.AUDIO_CAST_STATE] goes out when something changes, not on a
## timer — so the current picture is asked for once, directly.
func _fetch_state() -> void:
	var base_url := KlippyLink.server_url()
	if base_url != "":
		# Authenticated: the answer names devices, and the server only tells a caller
		# about the ones in its own account.
		var headers := PackedStringArray(["Authorization: Bearer " + KlippyLink.auth_token()])
		_state_fetch.request(base_url + "/api/audio/state", headers)


func _on_state_fetched(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_read_cast_state(parsed)
	_refresh()


func _read_cast_state(payload: Dictionary) -> void:
	_listeners.clear()
	for entry in payload.get("listeners", []):
		if typeof(entry) == TYPE_DICTIONARY:
			_listeners[str(entry.get("deviceId", ""))] = bool(entry.get("isReceiving", false))

	# The wait ends when the world matches what we asked for, whoever brought that
	# about — the phone may equally have been started from its own screen.
	if _waiting_for != "" and _listeners.has(_waiting_for) == _waiting_enabled:
		_stop_waiting()


func _on_peers_changed() -> void:
	_targets = KlippyLink.peers_of_kind(LinkEvents.KIND_MOBILE)

	var names := PackedStringArray()
	for target in _targets:
		names.append(target["name"])

	_picker.clear()
	for name in names:
		_picker.add_item(name)
	_picker.visible = _targets.size() > 1

	# Keep the phone the user picked if it is still here; otherwise fall back to
	# the first one rather than leaving the card pointing at nothing.
	var index := _index_of(_selected_id)
	if index == -1:
		index = 0 if not _targets.is_empty() else -1
	if index != -1:
		_selected_id = _targets[index]["id"]
		_picker.select(index)
	else:
		_selected_id = ""

	_refresh()


func _on_target_picked(index: int) -> void:
	if index >= 0 and index < _targets.size():
		_selected_id = _targets[index]["id"]
		_note = ""
	_refresh()


func _on_link_state_changed(_state: KlippyLink.State) -> void:
	if KlippyLink.is_connected_to_server():
		_fetch_state()
	else:
		# Nothing known about a cast survives the link dropping: the server stops
		# capturing for a device it can no longer reach.
		_listeners.clear()
		_stop_waiting()
	_refresh()


func _on_answer_timeout() -> void:
	var name := _name_of(_waiting_for)
	_note = "%s didn't answer. Check Klippy is open on it and try again." % name
	_stop_waiting()
	_refresh()


func _stop_waiting() -> void:
	_waiting_for = ""
	_timeout.stop()


func _refresh() -> void:
	if not KlippyLink.is_connected_to_server():
		set_action("Relay", false)
		set_status("Klippy isn't connected to a server.")
		return

	if _targets.is_empty():
		set_action("Relay", false)
		set_status("No phone is connected. Open Klippy on your phone.")
		return

	var target := _selected()
	var name: String = target.get("name", "")

	if _waiting_for != "":
		set_action("Relay" if _waiting_enabled else "Stop", false)
		set_status("Asking %s to %s…" % [_name_of(_waiting_for), "listen" if _waiting_enabled else "stop"])
		return

	if _listeners.has(target.get("id", "")):
		set_action("Stop", true)
		set_status("Playing on %s." % name if _listeners[target["id"]]
			else "%s has the stream; waiting for the audio to arrive." % name)
		return

	set_action("Relay", true)
	set_status(_note if _note != "" else "Ready to play on %s." % name)


func _selected() -> Dictionary:
	var index := _index_of(_selected_id)
	return _targets[index] if index != -1 else {}


func _index_of(device_id: String) -> int:
	for index in _targets.size():
		if _targets[index]["id"] == device_id:
			return index
	return -1


## The name the link gave a device, falling back to its id when it has gone.
func _name_of(device_id: String) -> String:
	var index := _index_of(device_id)
	return _targets[index]["name"] if index != -1 else "The phone"
