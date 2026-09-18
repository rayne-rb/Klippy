class_name VisitSession
extends Node

## The sending end of a visit: owns this desktop's green friend portal and the
## pet's trip through it.
##
## A visit connects two Klippy companions paired to the same server — the klippy
## network is the server's device list. Both ends already share one link, so a
## visit is just targeted `visit.*` events to the chosen companion's device id;
## there is no second socket, no second pairing, and nothing the server needs to
## know about. Summoning opens a portal here and asks the other end (visit.open)
## to open its own; what each end does on its own monitor is its own business.
##
## A throw into the green portal does not teleport the pet locally — it hides him
## here and asks the other companion (visit.arrive) to stand him up over there.
## Coming home is the same trip in reverse, and the exit the friend sees is a
## portal opened right on top of the visiting pet, so "call him back" reads as
## one motion on both screens. Every step trusts the other end to answer: an
## arrival that is never confirmed and a departure that is never acknowledged
## both end with the pet popping back out of the green portal — the portal is
## the pet's home anchor, and while it exists he can always be given a way back.

signal portal_changed

enum State {
	HOME,       ## No trip in progress; the portal is just a door on the desktop.
	TRAVELING,  ## Went in on this side; waiting to be told he is out the other.
	AWAY,       ## Confirmed: he is on the other companion's monitor.
	RECALLING,  ## Called back; waiting for the other side to let him go.
}

## How long an arrival or a departure may go unconfirmed before this side stops
## trusting the other and gives the pet his way back.
const TRIP_TIMEOUT := 4.0
const RETURN_BURST_SPEED := 260.0

var _klippy: Klippy
var _portal: TravelPortal
var _portal_menu: PopupMenu
## The companion whose monitor this portal opens onto, while it exists.
var _peer_id := ""
var _state: State = State.HOME
var _trip_timer := 0.0


func setup(klippy: Klippy) -> void:
	_klippy = klippy

	KlippyLink.event_received.connect(_on_link_event)
	KlippyLink.state_changed.connect(_on_link_state_changed)


## The other Klippy companions currently connected to our server — the monitors
## a friend portal can open onto. Phones and other devices are not klippys and
## cannot host one, so they never appear.
func companion_peers() -> Array[Dictionary]:
	return KlippyLink.peers_of_kind(LinkEvents.KIND_COMPANION)


## Whether the green door is currently on the desktop (drives the Fun menu items).
func has_portal() -> bool:
	return _portal != null and is_instance_valid(_portal)


func is_visiting() -> bool:
	return _state != State.HOME


## Opens this end and asks [param peer] (a [member KlippyLink.peers] entry) to
## open the other. The pairing question never comes up: both ends are already
## devices in good standing on the same server.
func summon_portal(peer: Dictionary) -> void:
	if has_portal():
		return
	if not KlippyLink.is_connected_to_server():
		return

	_peer_id = str(peer.get("id", ""))
	if _peer_id == "":
		return

	_spawn_portal()

	KlippyLink.publish(LinkEvents.VISIT_OPEN, null, _peer_id)
	portal_changed.emit()


## Takes the green door back off both desktops (pet home only). The other end
## hears visit.close and does the same.
func forget_portal() -> void:
	_close_portal()
	if _peer_id != "":
		KlippyLink.publish(LinkEvents.VISIT_CLOSE, null, _peer_id)
	_peer_id = ""
	portal_changed.emit()


## The pet goes into the portal on this monitor and out of the one the friend is
## already looking at — the two doors opened together at summon time.
func _on_friend_portal_entered(_entry_velocity: Vector2, rising: bool, portal: TravelPortal) -> void:
	if _state != State.HOME or not rising:
		return

	if _peer_id == "":
		_close_portal()
		portal_changed.emit()
		return

	_state = State.TRAVELING
	_trip_timer = TRIP_TIMEOUT

	_klippy.visit_absorb()
	KlippyLink.publish(LinkEvents.VISIT_ARRIVE, _appearance_payload(), _peer_id)


## Right-click on the green portal: the only control surface left on this desktop
## that knows where the pet went.
func _show_portal_menu() -> void:
	if _portal_menu == null:
		_portal_menu = PopupMenu.new()
		_portal_menu.add_item("Call him back", 1)
		_portal_menu.add_item("Close portal", 2)
		_portal_menu.id_pressed.connect(_on_portal_menu_id_pressed)
		RockyTheme.style_popup(_portal_menu)
		_portal.add_child(_portal_menu)

	_portal_menu.set_item_disabled(0, _state != State.AWAY)
	_portal_menu.set_item_disabled(1, is_visiting())
	_portal_menu.position = DisplayServer.mouse_get_position()
	_portal_menu.popup()


func _on_portal_menu_id_pressed(id: int) -> void:
	match id:
		1:
			_recall()
		2:
			forget_portal()


## Owner-initiated "call him back": the friend's side opens the exit on top of
## the pet and answers with visit.departed once he is through it.
func _recall() -> void:
	if _state != State.AWAY:
		return

	_state = State.RECALLING
	_trip_timer = TRIP_TIMEOUT
	KlippyLink.publish(LinkEvents.VISIT_RECALL, null, _peer_id)


## A word from the pet while he is away — used for the owner's own reminders
## coming due over on the friend's monitor.
func speak(text: String) -> void:
	if _state != State.AWAY:
		return
	KlippyLink.publish(LinkEvents.VISIT_SPEAK, {"text": text}, _peer_id)


func _on_link_event(type: String, payload: Dictionary, source: String) -> void:
	match type:
		LinkEvents.VISIT_ARRIVED:
			if _state == State.TRAVELING and source == _peer_id:
				_state = State.AWAY

		LinkEvents.VISIT_DEPARTED:
			if _state == State.RECALLING and source == _peer_id:
				_return_home(true)

		LinkEvents.DEVICE_DISCONNECTED:
			var gone := str(payload.get("deviceId", ""))
			if gone != _peer_id:
				return
			# The other end signing off takes the whole doorway with it: nobody is
			# left to show him, and nothing is left to open onto.
			if is_visiting():
				_return_home(false)
			elif has_portal():
				_close_portal()
				_peer_id = ""
				portal_changed.emit()

		_:
			pass


func _on_link_state_changed(state: KlippyLink.State) -> void:
	# The link is the whole trip: without it the pet is a figment on a screen
	# nobody can confirm. Pop him back out and let the portal stand by for
	# another try.
	if state != KlippyLink.State.CONNECTED and is_visiting():
		_return_home(false)


func _process(delta: float) -> void:
	if _state == State.HOME:
		return

	_trip_timer -= delta
	if _trip_timer > 0.0:
		return

	# Too long without an answer. The recall case gets no republish loop — if the
	# friend's side cannot answer, hiding the pet here would only lose him.
	match _state:
		State.TRAVELING:
			_klippy.say("Nobody's home...")
			_return_home(false)
		State.RECALLING:
			_return_home(false)
		_:
			pass


func _spawn_portal() -> void:
	_portal = TravelPortal.new("green")
	_portal.current_screen = _klippy.get_window().current_screen
	_portal.probe = _klippy.pet_probe
	_portal.entered.connect(_on_friend_portal_entered.bind(_portal))
	_portal.right_clicked.connect(_show_portal_menu)
	_klippy.add_child(_portal)

	var bounds := DisplayServer.screen_get_usable_rect(_portal.current_screen)
	var spot := Vector2(bounds.position) + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.45)
	_portal.place(Vector2i(spot))


## The pet pops back out of the green portal. When [param announced] he came
## through the friend's exit on purpose, so the whole doorway closes behind him —
## both ends and the travel pair included. A failed trip keeps the portals up
## for another try.
func _return_home(announced: bool) -> void:
	_state = State.HOME

	if _portal == null or not is_instance_valid(_portal):
		return

	if announced:
		_klippy.say("Home sweet home!")
	_emerge_from_portal(_portal)

	if announced:
		_close_portal()
		_peer_id = ""
		_klippy.banish_travel_portals()

	portal_changed.emit()


## Stands the pet up just outside the portal's rim, moving away from it — the
## same offset the local portal chain uses. Dead-center would have the portal's
## own entry detection re-catch him on the next tick and swallow him again.
func _emerge_from_portal(portal: TravelPortal) -> void:
	var exit_velocity := _random_exit_velocity()
	var direction := exit_velocity.normalized()
	var center := portal.center() + direction * (portal.radius() + _klippy.roll_radius + 8.0)
	_klippy.visit_emerge(center, portal.current_screen, exit_velocity)


func _close_portal() -> void:
	if _portal != null and is_instance_valid(_portal):
		_portal.queue_free()
	_portal = null
	_portal_menu = null


func _random_exit_velocity() -> Vector2:
	return Vector2.RIGHT.rotated(randf() * TAU) * RETURN_BURST_SPEED


## Where the pet is headed. Words come only from his owner's mouth elsewhere;
## the friend's side greets him on its own.
func _appearance_payload() -> Dictionary:
	return {
		"visitorName": KlippyLink.device_name(),
		"bodyId": _klippy.current_body_id,
		"expressionId": _klippy.current_expression_id,
		"eyesId": _klippy.current_eyes_id,
		"pupilsId": _klippy.current_pupils_id,
		"hatId": _klippy.current_hat_id,
		"size": _klippy.current_size,
	}
