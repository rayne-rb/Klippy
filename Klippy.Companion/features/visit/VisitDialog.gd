class_name VisitDialog
extends Window

## Picks whose monitor the friend portal opens onto.
##
## The klippy network is the server's device list: every other Klippy companion
## connected to our own server is a monitor this pet can visit — no pairing beyond
## what got each of them onto the server, and no addresses to type. Phones and other
## devices are not klippys and never appear here.
##
## Two lists, because they are two different things. Your own machines are yours and
## open on the spot. A friend is somebody else's account on the same server: the
## server will carry a visit to them and nothing else, and their own Klippy asks them
## before it opens a door. The dialog says so rather than letting a summons quietly
## do nothing while somebody decides.
##
## The last section is the other direction — the friends this machine has stopped
## asking about — because the place you choose who to visit is the obvious place to
## find who may visit you.

var _session: VisitSession
var _host: VisitHost
var _vbox: VBoxContainer


func setup(session: VisitSession, host: VisitHost) -> void:
	_session = session
	_host = host
	_vbox = RockyTheme.setup_window(self, "Visit a Friend")

	# A friend starting their Klippy while this is open should show up in it, rather
	# than the list being whatever was true the moment it was opened.
	KlippyLink.peers_changed.connect(_show_peers)
	KlippyLink.neighbors_changed.connect(_show_peers)
	KlippyLink.state_changed.connect(func(_state: KlippyLink.State) -> void: _show_peers())

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


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", RockyTheme.MUTED)
	return label


func _show_peers() -> void:
	_clear()

	if not KlippyLink.is_connected_to_server():
		_vbox.add_child(_hint("Not connected to a Klippy server — visits ride the"
				+ " same link as everything else. Check the Connection dialog."))
		return

	var mine := _session.companion_peers()
	var friends := _session.friend_companions()

	if mine.is_empty() and friends.is_empty():
		_vbox.add_child(_hint("No other Klippy is connected to your server yet."
				+ " Start Klippy on the other PC and pair it — the code to approve"
				+ " shows on the server's Devices page — and it will appear here."))
	else:
		_vbox.add_child(_hint("Pick whose monitor your pet should visit:"))

	if not mine.is_empty():
		_vbox.add_child(_section("Your machines"))
		for peer in mine:
			_vbox.add_child(_peer_button(str(peer.get("name", "A Klippy")), peer))

	if not friends.is_empty():
		_vbox.add_child(_section("Friends on this server"))
		for friend in friends:
			_vbox.add_child(_peer_button(_friend_label(friend), friend))
		_vbox.add_child(_hint("They get asked before your pet turns up."))

	_show_remembered()


## The friends who may open a door here without being asked about, and the way to
## take that back.
func _show_remembered() -> void:
	var remembered := _host.remembered_friends()
	if remembered.is_empty():
		return

	_vbox.add_child(HSeparator.new())
	_vbox.add_child(_section("May drop in on you"))

	for friend in remembered:
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = str(friend.get("name", "A Klippy"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var forget := Button.new()
		forget.text = "✕"
		forget.tooltip_text = "Ask again next time"
		forget.pressed.connect(_on_forget_pressed.bind(str(friend.get("id", ""))))
		row.add_child(forget)

		_vbox.add_child(row)


func _peer_button(text: String, peer: Dictionary) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_on_peer_picked.bind(peer))
	return button


## Whose Klippy it is matters more than what they called the machine, so both are
## shown when the server told us both.
func _friend_label(friend: Dictionary) -> String:
	var device_name := str(friend.get("name", "")).strip_edges()
	if device_name == "":
		device_name = "A Klippy"

	var owner := str(friend.get("owner", "")).strip_edges()
	return device_name if owner == "" else "%s (%s)" % [device_name, owner]


func _on_forget_pressed(device_id: String) -> void:
	_host.forget_friend(device_id)
	_show_peers()


func _on_peer_picked(peer: Dictionary) -> void:
	_session.summon_portal(peer)
	# Both halves of the doorway are opening; this dialog has done its job.
	close_requested.emit()
