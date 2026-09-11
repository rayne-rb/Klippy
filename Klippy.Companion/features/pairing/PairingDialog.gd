class_name PairingDialog
extends Window

## Shows where the Companion stands with the server.
##
## During pairing it exists to display one thing well: the code, big enough to read
## at a glance and compare against the server's Devices page. The rest of the time
## it is a small status readout with a way to start over.

signal unpair_requested

var _status_label: Label
var _code_label: Label
var _hint_label: Label
var _server_label: Label
var _unpair_button: Button


func _ready() -> void:
	title = "Klippy Connection"
	size = Vector2i(340, 250)
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 40)
	_code_label.visible = false
	vbox.add_child(_code_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_hint_label)

	_server_label = Label.new()
	_server_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_server_label)

	vbox.add_child(HSeparator.new())

	_unpair_button = Button.new()
	_unpair_button.text = "Forget this server"
	_unpair_button.pressed.connect(func() -> void: unpair_requested.emit())
	vbox.add_child(_unpair_button)

	KlippyLink.state_changed.connect(_on_state_changed)
	KlippyLink.pairing_code_ready.connect(_on_code_ready)
	KlippyLink.pairing_failed.connect(_on_pairing_failed)
	_on_state_changed(KlippyLink.state)


func _on_state_changed(state: KlippyLink.State) -> void:
	# The code only means anything while an approval is outstanding.
	if state != KlippyLink.State.PAIRING:
		_code_label.visible = false

	match state:
		KlippyLink.State.OFFLINE:
			_status_label.text = "Not connected"
			_hint_label.text = "Retrying shortly."
		KlippyLink.State.SEARCHING:
			_status_label.text = "Looking for a Klippy server"
			_hint_label.text = "Anything running on this network will turn up on its own."
		KlippyLink.State.PAIRING:
			_status_label.text = "Waiting to be let in"
		KlippyLink.State.CONNECTING:
			_status_label.text = "Connecting"
			_hint_label.text = ""
		KlippyLink.State.CONNECTED:
			_status_label.text = "Connected"
			_hint_label.text = "Klippy can be reached from your phone."

	_unpair_button.disabled = state == KlippyLink.State.SEARCHING


func _on_code_ready(code: String) -> void:
	_code_label.text = code
	_code_label.visible = true
	_hint_label.text = "Open the server's Devices page and approve this code."


func _on_pairing_failed(reason: String) -> void:
	_code_label.visible = false
	_status_label.text = "Pairing did not finish"
	_hint_label.text = reason


## Called by the pet so the dialog can name the server it is talking to.
func set_server(description: String) -> void:
	_server_label.text = description
