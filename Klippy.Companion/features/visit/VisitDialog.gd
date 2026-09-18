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

var _session: VisitSession
var _vbox: VBoxContainer
var _discovery: ServerDiscovery


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
		_vbox.add_child(_hint("No other Klippy servers answered."))

	var again := Button.new()
	again.text = "Scan again"
	again.pressed.connect(_show_scanning)
	_vbox.add_child(again)


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
