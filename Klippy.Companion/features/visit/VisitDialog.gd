class_name VisitDialog
extends Window

## Picks whose monitor the friend portal opens onto.
##
## The klippy network is the server's device list: every other Klippy companion
## currently connected to our own server is a monitor this pet can visit — no
## pairing beyond what got each of them onto the server, and no addresses to
## type. Phones and other devices are not klippys and never appear here.

var _session: VisitSession
var _vbox: VBoxContainer


func setup(session: VisitSession) -> void:
	_session = session
	_vbox = RockyTheme.setup_window(self, "Visit a Friend")
	_show_peers()


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


func _show_peers() -> void:
	_clear()

	if not KlippyLink.is_connected_to_server():
		_vbox.add_child(_hint("Not connected to a Klippy server — visits ride the"
				+ " same link as everything else. Check the Connection dialog."))
		return

	var peers := _session.companion_peers()
	if peers.is_empty():
		_vbox.add_child(_hint("No other Klippy is connected to your server yet."
				+ " Start Klippy on the other PC and pair it — the code to approve"
				+ " shows on the server's Devices page — and it will appear here."))
		return

	_vbox.add_child(_hint("Pick whose monitor your pet should visit:"))

	for peer in peers:
		var button := Button.new()
		button.text = str(peer.get("name", "A Klippy"))
		button.pressed.connect(_on_peer_picked.bind(peer))
		_vbox.add_child(button)


func _on_peer_picked(peer: Dictionary) -> void:
	_session.summon_portal(peer)
	# Both halves of the doorway are opening; this dialog has done its job.
	close_requested.emit()
