class_name VisitDialog
extends Window

## Where a visit starts: find the friend's server on the network, ask to be let
## in, and show the code somebody over there has to approve. One approval per
## friend, ever — the pairing is remembered by [VisitSettings] and every later
## "Summon Friend Portal" goes straight through.
##
## Not a status dialog like [PairingDialog]: this one exists only for the first
## handshake. Forgetting the pairing afterwards lives in the friend portal's own
## right-click menu, where the door is.

signal visit_ready

const SCAN_DURATION := 2.5
## Same default the phone types on behalf of the user, so nobody types a port.
const DEFAULT_SERVER_PORT := 5068
const IDENTITY_TIMEOUT := 8.0

var _session: VisitSession
var _vbox: VBoxContainer
var _discovery: ServerDiscovery
var _manual_edit: LineEdit
var _manual_button: Button
var _manual_status: Label
var _manual_http: HTTPRequest
var _manual_fetching := false


func setup(session: VisitSession) -> void:
	_session = session
	_vbox = RockyTheme.setup_window(self, "Visit a Friend")

	if _session.has_pairing():
		_show_paired()
	else:
		_show_scanning()


func _exit_tree() -> void:
	_stop_scan()


func _stop_scan() -> void:
	if _discovery != null:
		_discovery.stop()
		_discovery.queue_free()
		_discovery = null


func _clear() -> void:
	# The manual-entry widgets are rebuilt per view; drop the refs before their
	# owners are freed so an identity response that lands mid-rebuild (scan
	# again clicked while a fetch was in flight) finds nothing to crash on.
	_manual_edit = null
	_manual_button = null
	_manual_status = null
	for child in _vbox.get_children():
		_vbox.remove_child(child)
		child.queue_free()


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", RockyTheme.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _show_scanning() -> void:
	_clear()

	var status := Label.new()
	status.text = "Looking for other Klippy servers on this network..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(status)
	_vbox.add_child(_hint(
			"Anyone else running one will turn up here. Pick whose monitor your pet should visit."))

	var scan := ServerDiscovery.new()
	add_child(scan)
	scan.scan_finished.connect(_on_scan_finished)
	_discovery = scan
	# Our own server is already where our phone looks; the friend portal is for
	# everybody else's.
	scan.scan(SCAN_DURATION)


func _on_scan_finished(beacons: Array[Dictionary]) -> void:
	_stop_scan()

	var own_server_id := LinkSettings.load_settings().server_id

	_clear()

	var found := false
	for beacon in beacons:
		if str(beacon.get("serverId", "")) == own_server_id:
			continue

		found = true
		var button := Button.new()
		button.text = str(beacon.get("name", "Unnamed server"))
		button.pressed.connect(_on_server_picked.bind(beacon))
		_vbox.add_child(button)
		_vbox.add_child(_hint(str(beacon.get("baseUrl", ""))))

	if not found:
		_vbox.add_child(_hint(
				"No other Klippy servers answered. Discovery only reaches the local"
				+ " network — if your friend's server is behind a NAT or a VPN, type"
				+ " its address below."))

	var again := Button.new()
	again.text = "Scan again"
	again.pressed.connect(_show_scanning)
	_vbox.add_child(again)

	_add_manual_entry_section()


func _on_server_picked(beacon: Dictionary) -> void:
	_stop_scan()
	_session.begin_pairing(beacon)

	_clear()

	var code := Label.new()
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 40)
	_vbox.add_child(code)

	var waiting := Label.new()
	waiting.text = "Waiting to be let in..."
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(waiting)
	_vbox.add_child(_hint(
			"Ask your friend to approve this code on their server's Devices page."))

	var link := _session.get_link()
	link.pairing_code_ready.connect(code.set_text)
	link.pairing_failed.connect(_on_pairing_failed)
	link.state_changed.connect(_on_pairing_state_changed)


# --- Manual address -------------------------------------------------------------
#
# Discovery is multicast with a hop limit of one, so it only ever answers for
# servers on the local network. The phone already has the answer for everything
# else — a typed address, resolved against /api/discovery/identity, which replies
# with the exact beacon discovery would have produced, addressed back to the
# caller. This is the same trick for the friend portal.

func _add_manual_entry_section() -> void:
	_vbox.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_vbox.add_child(row)

	_manual_edit = LineEdit.new()
	_manual_edit.placeholder_text = "192.168.1.42  ·  host:5068"
	_manual_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manual_edit.text_submitted.connect(func(_text: String) -> void: _on_add_manual())
	row.add_child(_manual_edit)

	_manual_button = Button.new()
	_manual_button.text = "Add"
	_manual_button.pressed.connect(_on_add_manual)
	row.add_child(_manual_button)

	_manual_status = _hint("")
	_manual_status.visible = false
	_vbox.add_child(_manual_status)

	_manual_edit.grab_focus()


func _show_manual_status(text: String) -> void:
	if _manual_status == null:
		return
	_manual_status.text = text
	_manual_status.visible = true


func _on_add_manual() -> void:
	if _manual_fetching:
		return

	var base_url := _normalize_address(_manual_edit.text)
	if base_url == "":
		_show_manual_status("Type an address first, e.g. 192.168.48.128 or host:5068.")
		return

	if _manual_http == null:
		_manual_http = HTTPRequest.new()
		_manual_http.timeout = IDENTITY_TIMEOUT
		add_child(_manual_http)
		_manual_http.request_completed.connect(_on_identity_response)

	_manual_fetching = true
	_manual_button.disabled = true
	_show_manual_status("Asking %s to identify itself..." % base_url)

	var err := _manual_http.request(base_url + "/api/discovery/identity")
	if err != OK:
		_manual_fetching = false
		_manual_button.disabled = false
		_show_manual_status("Could not start the request (error %d)." % err)


func _on_identity_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_manual_fetching = false
	if _manual_button != null:
		_manual_button.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_manual_status("Nothing answering as a Klippy server there (HTTP %d)." % response_code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("serverId"):
		_show_manual_status("That answered, but not as a Klippy server.")
		return

	var beacon: Dictionary = parsed
	var own_server_id := LinkSettings.load_settings().server_id
	if str(beacon.get("serverId", "")) == own_server_id:
		_show_manual_status("That is your own server — visits go to somebody else's monitor.")
		return

	_manual_status = null
	_on_server_picked(beacon)


## Turns what a person would type into a base URL, or "" if it cannot be one:
## "192.168.1.42", "host:5068", "http://box:5068/devices" all end at the server's
## root with the default port filled in — the same rules the phone applies.
func _normalize_address(address: String) -> String:
	var trimmed := address.strip_edges().trim_suffix("/")
	if trimmed.is_empty():
		return ""

	var scheme := "http"
	var scheme_at := trimmed.find("://")
	if scheme_at != -1:
		scheme = trimmed.substr(0, scheme_at)
		trimmed = trimmed.substr(scheme_at + 3)

	# Everything after the first slash is a path; the identity endpoint lives at
	# the root, so drop whatever journey the user pasted in.
	var slash := trimmed.find("/")
	if slash != -1:
		trimmed = trimmed.substr(0, slash)

	if trimmed.is_empty():
		return ""

	# A port was typed only if the authority carries one — the colon in "http://"
	# is not it, and an IPv6 literal hides its port behind the closing bracket.
	var bracket_end := trimmed.rfind("]")
	var has_port := trimmed.contains("]:") if bracket_end != -1 else trimmed.contains(":")
	if not has_port:
		trimmed += ":%d" % DEFAULT_SERVER_PORT

	return "%s://%s" % [scheme, trimmed]


func _on_pairing_failed(reason: String) -> void:
	_clear()

	var status := Label.new()
	status.text = "Pairing did not finish"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(status)
	_vbox.add_child(_hint(reason))

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_show_scanning)
	_vbox.add_child(back)


func _on_pairing_state_changed(state: GuestLink.State) -> void:
	if state == GuestLink.State.CONNECTED:
		# Paired and live: the door can open, and this dialog has done its job.
		visit_ready.emit()
		close_requested.emit()


func _show_paired() -> void:
	_clear()

	var status := Label.new()
	status.text = "Visits go to %s" % _session.paired_server_name()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(status)

	var forget := Button.new()
	forget.text = "Forget this server"
	forget.pressed.connect(func() -> void:
		_session.forget_pairing()
		_show_scanning())
	_vbox.add_child(forget)
