class_name ClipboardSkill
extends SkillCard

## Shares this PC's clipboard with the rest of your devices.
##
## The card is only the switch. The watching is done by [ClipboardWatcher], which runs
## whether or not this window is open — a skill that only worked while you were looking at
## it would be a strange kind of skill — and the entries themselves live in
## [ClipboardBoardDialog].
##
## Two settings, both deliberately cautious by default: off, and private when on. What
## goes through a clipboard is passwords and half-written messages as often as it is a URL.

## Opening the board is Klippy's job — it owns the window, so that it survives this card
## being closed with the Skills list.
signal board_requested


var _settings: ClipboardSettings
var _watcher: ClipboardWatcher
var _visibility: OptionButton
var _open_board: Button

## Shown in place of the usual line when something just happened, cleared on the next change.
var _note := ""


func setup(settings: ClipboardSettings, watcher: ClipboardWatcher) -> void:
	_settings = settings
	_watcher = watcher


func _ready() -> void:
	super._ready()
	set_title("Clipboard")
	set_description("Copy on this PC, paste on your phone or your other Klippy.")

	_visibility = OptionButton.new()
	_visibility.add_item("Only my devices")
	_visibility.add_item("Everyone on this server")
	_visibility.item_selected.connect(_on_visibility_picked)
	extra.add_child(_visibility)

	_open_board = Button.new()
	_open_board.text = "Open the board"
	_open_board.pressed.connect(_on_open_board)
	extra.add_child(_open_board)

	action_pressed.connect(_on_action_pressed)
	KlippyLink.state_changed.connect(_on_link_state_changed)

	if _watcher != null:
		_watcher.captured.connect(_on_captured)
		_watcher.capture_failed.connect(_on_capture_failed)

	if _settings != null:
		_visibility.select(1 if _settings.is_shared_server_wide() else 0)

	_refresh()


func _on_open_board() -> void:
	board_requested.emit()


func _on_action_pressed() -> void:
	if _settings == null:
		return

	_settings.enabled = not _settings.enabled
	_settings.save()
	_note = ""

	# Whatever is on the clipboard right now counts as fair game from the moment it is
	# switched on, and nothing at all before that.
	if _settings.enabled and _watcher != null:
		_watcher.reset()

	_announce()
	_refresh()


func _on_visibility_picked(index: int) -> void:
	if _settings == null:
		return

	_settings.visibility = (ClipboardSettings.VISIBILITY_SERVER if index == 1
		else ClipboardSettings.VISIBILITY_GROUP)
	_settings.save()

	# Only what is copied from now on is affected. Entries already sent keep whatever they
	# were sent as, which is why this says so rather than leaving it to be discovered.
	_note = ("New copies will be shared with everyone on the server." if index == 1
		else "New copies stay on your own devices.")

	_announce()
	_refresh()


## Tells the server whether this PC is taking part, so its own page can say who is.
func _announce() -> void:
	KlippyLink.publish(LinkEvents.CLIPBOARD_SHARING, {
		"enabled": _settings.enabled,
		"visibility": _settings.visibility,
	})


func _on_link_state_changed(_state: KlippyLink.State) -> void:
	# Sharing state is held in memory by the server, so a reconnect has to say it again.
	if KlippyLink.is_connected_to_server() and _settings != null and _settings.enabled:
		_announce()
	_refresh()


func _on_captured(kind: String) -> void:
	_note = "Shared the %s you just copied." % kind
	_refresh()


func _on_capture_failed(reason: String) -> void:
	_note = reason
	_refresh()


func _refresh() -> void:
	if _settings == null:
		set_action("Turn on", false)
		set_status("Not ready yet.")
		return

	_visibility.disabled = not _settings.enabled
	_open_board.disabled = not KlippyLink.is_connected_to_server()

	if not KlippyLink.is_connected_to_server():
		set_action("Turn off" if _settings.enabled else "Turn on", _settings.enabled)
		set_status("Klippy isn't connected to a server, so nothing is being shared.")
		return

	if not _settings.enabled:
		set_action("Turn on", true)
		set_status("Off. Nothing on this PC's clipboard is read while it is.")
		return

	set_action("Turn off", true)

	if _note != "":
		set_status(_note)
		return

	set_status("Watching this PC's clipboard · %s." % ("everyone on this server sees it"
		if _settings.is_shared_server_wide() else "only your own devices see it"))
