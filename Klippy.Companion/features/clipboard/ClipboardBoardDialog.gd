class_name ClipboardBoardDialog
extends Window

## What has been copied, across this account's devices.
##
## One row per entry: what it was, where it came from, and the three things worth doing
## with it — put it back on this PC's clipboard, push it to another of your devices, or
## get rid of it. Entries shared server-wide by other accounts appear here too, marked as
## such; they can be used but not deleted, since they are not this account's to withdraw.
##
## The list is pulled rather than pushed. Entries do arrive over the link as they happen
## (see [constant LinkEvents.CLIPBOARD_ENTRY]), but those carry no content — only the news
## that there is some — so the answer to hearing one is to ask again.

## An entry was put on this PC's clipboard, so the watcher can be told not to send it
## straight back up. [param digest] is over the same bytes the watcher hashes.
signal applied_locally(digest: String)

const ROW_WIDTH := 330

var _client: ClipboardClient
var _row_list: VBoxContainer
var _status_label: Label
var _entries: Array = []
var _viewer: Window


func _ready() -> void:
	var vbox := RockyTheme.setup_window(self, "Clipboard", 380)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(ROW_WIDTH - 80, 0)
	header.add_child(_status_label)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh)
	header.add_child(refresh_button)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_row_list = VBoxContainer.new()
	_row_list.add_theme_constant_override("separation", 6)
	_row_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_row_list)

	KlippyLink.event_received.connect(_on_event_received)


## An entry arriving or leaving is announced without its content, so the only useful
## response is to ask for the list again — and only while anyone is looking at it.
func _on_event_received(type: String, _payload: Dictionary, _source: String) -> void:
	if visible and type in [LinkEvents.CLIPBOARD_ENTRY, LinkEvents.CLIPBOARD_REMOVED]:
		refresh()


func setup(client: ClipboardClient) -> void:
	_client = client


func refresh() -> void:
	if not KlippyLink.is_connected_to_server():
		_entries = []
		_render_rows()
		_status_label.text = "Klippy isn't connected to a server."
		return

	_status_label.text = "Loading…"
	_client.list(func(ok: bool, entries: Array) -> void:
		if not ok:
			_status_label.text = "Could not load the clipboard."
			return

		_entries = entries
		_status_label.text = ("Nothing copied yet." if entries.is_empty()
			else "%d entr%s" % [entries.size(), "y" if entries.size() == 1 else "ies"])
		_render_rows()
	)


func _render_rows() -> void:
	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()

	for entry in _entries:
		if typeof(entry) == TYPE_DICTIONARY:
			_row_list.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = RockyTheme.FIELD_BG
	style.border_color = RockyTheme.FIELD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var is_image: bool = str(entry.get("contentType", "")) != "text"

	var what := Label.new()
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	what.text = ("Image · %s" % _size_of(int(entry.get("byteSize", 0))) if is_image
		else str(entry.get("preview", "")))
	vbox.add_child(what)

	var meta := Label.new()
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", RockyTheme.MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	meta.text = _describe(entry)
	vbox.add_child(meta)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons)

	var entry_id := str(entry.get("entryId", ""))

	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(func() -> void: _copy(entry_id, is_image))
	buttons.add_child(copy_button)

	if is_image:
		var view_button := Button.new()
		view_button.text = "View"
		view_button.pressed.connect(func() -> void: _view(entry_id))
		buttons.add_child(view_button)

	# The link only ever lists devices from our own account, so whatever is offered here
	# is already something we are allowed to reach.
	var peers := KlippyLink.peers
	if not peers.is_empty():
		var send_button := MenuButton.new()
		send_button.text = "Send to"
		var popup := send_button.get_popup()
		RockyTheme.style_popup(popup)
		for peer in peers:
			popup.add_item(str(peer.get("name", "?")))
		popup.id_pressed.connect(func(index: int) -> void:
			_send(entry_id, str(peers[index].get("id", ""))))
		buttons.add_child(send_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	# Only what this account copied is ours to delete. Someone else's server-wide entry
	# is theirs to withdraw.
	if bool(entry.get("isMine", false)):
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(func() -> void: _delete(entry_id))
		buttons.add_child(delete_button)

	return panel


func _copy(entry_id: String, is_image: bool) -> void:
	_status_label.text = "Fetching…"
	_client.fetch_content(entry_id, func(ok: bool, body: PackedByteArray) -> void:
		if not ok:
			_status_label.text = "Could not fetch that entry."
			return

		if is_image:
			var error := ClipboardImageWriter.write(body)
			if error != "":
				_status_label.text = error
				return

			# Hashed the way the watcher hashes an image — over the raw pixels — so it
			# recognises this as ours coming back rather than as a new copy.
			var image := Image.new()
			if image.load_png_from_buffer(body) == OK:
				applied_locally.emit(_digest(image.get_data()))

			_status_label.text = "Image is on this PC's clipboard."
			return

		var text := body.get_string_from_utf8()
		DisplayServer.clipboard_set(text)
		applied_locally.emit(_digest(text.to_utf8_buffer()))
		_status_label.text = "Copied to this PC's clipboard."
	)


func _view(entry_id: String) -> void:
	_status_label.text = "Fetching…"
	_client.fetch_content(entry_id, func(ok: bool, body: PackedByteArray) -> void:
		if not ok:
			_status_label.text = "Could not fetch that entry."
			return

		var image := Image.new()
		if image.load_png_from_buffer(body) != OK:
			_status_label.text = "That image could not be read."
			return

		_status_label.text = ""
		_show_image(image)
	)


func _show_image(image: Image) -> void:
	if _viewer != null:
		_viewer.queue_free()

	_viewer = Window.new()
	var vbox := RockyTheme.setup_window(_viewer, "Image", 420)
	_viewer.close_requested.connect(func() -> void:
		_viewer.queue_free()
		_viewer = null)

	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(rect)

	add_child(_viewer)
	_viewer.popup_centered()


func _send(entry_id: String, device_id: String) -> void:
	if device_id == "":
		return

	_status_label.text = "Sending…"
	_client.apply_to(entry_id, device_id, func(ok: bool, error: String) -> void:
		_status_label.text = "Sent." if ok else error
	)


func _delete(entry_id: String) -> void:
	_client.delete_entry(entry_id, func(ok: bool, error: String) -> void:
		if ok:
			refresh()
		else:
			_status_label.text = error
	)


func _describe(entry: Dictionary) -> String:
	var source := str(entry.get("sourceDeviceName", "somewhere"))
	var shared := str(entry.get("visibility", "")) == "server"
	var mine := bool(entry.get("isMine", false))

	if shared and not mine:
		return "from %s · shared by %s" % [source, str(entry.get("ownerName", "someone"))]
	if shared:
		return "from %s · shared with everyone" % source
	return "from %s" % source


static func _size_of(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1024.0 / 1024.0)
	if bytes >= 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%d B" % bytes


static func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
