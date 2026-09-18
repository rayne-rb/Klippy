class_name MarketSellDialog
extends Window

## Prompts for a price once an item has drifted into the sell portal (see
## SellPortal and Klippy._on_consumable_sell_requested). Confirming lists it on
## the market; cancelling — or the listing call itself failing — hands the
## item back rather than losing it.

signal confirmed(price: int)
signal cancelled

const MIN_PRICE := 1
const MAX_PRICE := 999999
const DEFAULT_PRICE := 10

var _item_label: Label
var _price_box: SpinBox
var _status_label: Label
var _confirm_button: Button


func _ready() -> void:
	var vbox := RockyTheme.setup_window(self, "Sell on Market", 300)
	# The close button and Cancel mean the same thing here: give the item back.
	close_requested.disconnect(hide)
	close_requested.connect(_on_cancel_pressed)

	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_item_label)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	vbox.add_child(price_row)

	var price_label := Label.new()
	price_label.text = "Price (KP)"
	price_row.add_child(price_label)

	_price_box = SpinBox.new()
	_price_box.min_value = MIN_PRICE
	_price_box.max_value = MAX_PRICE
	_price_box.step = 1
	_price_box.value = DEFAULT_PRICE
	_price_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(_price_box)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", RockyTheme.MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_row.add_child(cancel_button)

	_confirm_button = Button.new()
	_confirm_button.text = "List it"
	_confirm_button.theme_type_variation = "ButtonPrimary"
	_confirm_button.pressed.connect(_on_confirm_pressed)
	button_row.add_child(_confirm_button)


## Called right before showing this, so the prompt names what is actually
## being sold and starts from a clean slate every time.
func open_for(display_name: String) -> void:
	_item_label.text = "Sell your %s for how much?" % display_name
	_status_label.text = ""
	_confirm_button.disabled = false
	_price_box.value = DEFAULT_PRICE
	popup_centered()


## Called back when the listing call failed, so the user can see why and try
## again without having to re-open the dialog.
func show_error(message: String) -> void:
	_status_label.text = message
	_confirm_button.disabled = false


func _on_confirm_pressed() -> void:
	_confirm_button.disabled = true
	_status_label.text = "Listing..."
	confirmed.emit(int(_price_box.value))


func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()
