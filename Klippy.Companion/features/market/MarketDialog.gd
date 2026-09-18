class_name MarketDialog
extends Window

## Browse-and-buy view of everything currently for sale on the connected
## Klippy server. Selling happens through the sell portal instead — see
## SellPortal and Klippy._on_consumable_sell_requested — since a price only
## makes sense once you already know what you're pricing.

## A purchase went through and was paid for; Klippy is responsible for
## actually delivering [param item_type] onto the desktop (see
## Klippy._on_market_item_purchased).
signal item_purchased(item_type: String)

var _market: MarketClient
var _points: KlippyPoints
var _row_list: VBoxContainer
var _status_label: Label
var _listings: Array = []
var _busy := false


func _ready() -> void:
	var vbox := RockyTheme.setup_window(self, "Market", 380)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_status_label)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh)
	header.add_child(refresh_button)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_row_list = VBoxContainer.new()
	_row_list.add_theme_constant_override("separation", 6)
	_row_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_row_list)


func setup(market: MarketClient, points: KlippyPoints) -> void:
	_market = market
	_points = points


## Pulls the current listings from the server. Called by Klippy right after
## popping this open, and by the Refresh button — the list is never pushed, so
## nothing else keeps it current on its own.
func refresh() -> void:
	if not KlippyLink.is_connected_to_server():
		_listings = []
		_render_rows()
		_status_label.text = "Not connected to a server."
		return

	_status_label.text = "Loading..."
	_market.list_listings(_on_listings_loaded)


func _on_listings_loaded(ok: bool, listings: Array) -> void:
	if not ok:
		_status_label.text = "Could not load the market."
		return

	_listings = listings
	_status_label.text = "Nothing for sale right now." if listings.is_empty() else "%d for sale" % listings.size()
	_render_rows()


func _render_rows() -> void:
	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()

	var own_device_id := KlippyLink.device_id()
	for entry in _listings:
		if typeof(entry) == TYPE_DICTIONARY:
			_add_row(entry, own_device_id)


func _add_row(entry: Dictionary, own_device_id: String) -> void:
	var listing_id := str(entry.get("listingId", ""))
	var item_type := str(entry.get("itemType", ""))
	var price := int(entry.get("price", 0))
	var seller_name := str(entry.get("sellerDeviceName", "?"))
	var seller_device_id := str(entry.get("sellerDeviceId", ""))
	var def := ConsumableCatalog.get_def(item_type)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_row_list.add_child(row)

	var icon := TextureRect.new()
	icon.texture = def.texture
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = "%s — %d KP" % [def.display_name, price]
	info.add_child(name_label)

	var seller_label := Label.new()
	seller_label.text = "from %s" % seller_name
	seller_label.add_theme_font_size_override("font_size", 11)
	seller_label.add_theme_color_override("font_color", RockyTheme.MUTED)
	info.add_child(seller_label)

	var is_own_listing := own_device_id != "" and seller_device_id == own_device_id

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.theme_type_variation = "ButtonPrimary"
	buy_button.disabled = _busy or is_own_listing or price > _points.points
	buy_button.pressed.connect(_on_buy_pressed.bind(listing_id))
	row.add_child(buy_button)


func _on_buy_pressed(listing_id: String) -> void:
	if _busy:
		return
	_busy = true
	_render_rows()
	_status_label.text = "Buying..."
	_market.buy(listing_id, _on_bought)


func _on_bought(ok: bool, item_type: String, price: int, error: String) -> void:
	_busy = false
	if not ok:
		_status_label.text = error
		refresh()
		return

	_points.spend_points(price)
	item_purchased.emit(item_type)
	_status_label.text = "Bought!"
	refresh()
