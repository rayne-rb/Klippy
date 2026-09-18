class_name VisitSession
extends Node

## The sending end of a visit: owns the friend portal on this desktop and the
## pet's trip through it.
##
## A throw into the green portal does not teleport the pet locally — it hides him
## here and asks the friend's companion (over [GuestLink], through the friend's
## server) to stand him up over there. Coming home is the same trip in reverse,
## and — the fun part — the exit the friend sees is a portal opened right on top
## of the visiting pet, so "call him back" reads as one motion on both screens.
##
## Every step trusts the other end to answer: an arrival that is never confirmed
## and a departure that is never acknowledged both end with the pet popping back
## out of the green portal. The portal is the pet's home anchor; as long as it
## exists, he can always be given a way back.

signal portal_changed

enum State {
	HOME,       ## No trip in progress; the portal is just a door on the desktop.
	TRAVELING,  ## Went in on this side; waiting to be told he is out the other.
	AWAY,       ## Confirmed: he is on the friend's monitor.
	RECALLING,  ## Called back; waiting for the friend's side to let him go.
}

## How long an arrival or a departure may go unconfirmed before this side stops
## trusting the other and gives the pet his way back.
const TRIP_TIMEOUT := 4.0
const RETURN_BURST_SPEED := 260.0

var _klippy: Klippy
var _link: GuestLink
var _portal: TravelPortal
var _portal_menu: PopupMenu
var _state: State = State.HOME
var _trip_timer := 0.0


func setup(klippy: Klippy) -> void:
	_klippy = klippy

	_link = GuestLink.new()
	_link.name = "GuestLink"
	add_child(_link)
	_link.event_received.connect(_on_guest_event)
	_link.state_changed.connect(_on_guest_link_state_changed)


func has_pairing() -> bool:
	return _link.is_paired()


## For the visit dialog, which wires its progress display straight to the guest
## link's pairing signals.
func get_link() -> GuestLink:
	return _link


func paired_server_name() -> String:
	return _link.server_name()


## Abandon an in-flight pairing (the dialog went away mid-handshake). A no-op
## once pairing has become a live connection.
func cancel_pairing() -> void:
	_link.cancel_pairing()


func is_visiting() -> bool:
	return _state != State.HOME


func begin_pairing(beacon: Dictionary) -> void:
	_link.stay_connected = true
	_link.begin_pairing(beacon)


func forget_pairing() -> void:
	# Called while the pet is home only (the portal menu hides it otherwise):
	# forgetting the door mid-visit would strand him.
	_close_portal()
	_link.disconnect_from_server()
	_link.forget_pairing()
	portal_changed.emit()


## Whether the green door is currently on the desktop (drives the Fun menu items).
func has_portal() -> bool:
	return _portal != null and is_instance_valid(_portal)


## Takes the green door back off the desktop, pet home only. The pairing stays —
## summoning again later reuses it without another approval.
func forget_portal() -> void:
	_close_portal()
	_link.disconnect_from_server()
	portal_changed.emit()


## The green door onto the friend's monitor. The pairing has to exist already
## (the caller sends the user through the visit dialog first if not); without it
## there is nothing to connect to and no door worth opening.
func summon_portal() -> void:
	if _portal != null and is_instance_valid(_portal):
		return

	_link.stay_connected = true
	_link.ensure_connected()

	_portal = TravelPortal.new("green")
	_portal.current_screen = _klippy.get_window().current_screen
	_portal.probe = _klippy.pet_probe
	_portal.entered.connect(_on_friend_portal_entered.bind(_portal))
	_portal.right_clicked.connect(_show_portal_menu)
	add_child(_portal)

	var bounds := DisplayServer.screen_get_usable_rect(_portal.current_screen)
	var spot := Vector2(bounds.position) + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.45)
	_portal.place(Vector2i(spot))

	portal_changed.emit()


## The pet goes into the portal on this monitor and out of a new one on the
## friend's, over their head — "a portal on my klippy", mirrored across the link.
func _on_friend_portal_entered(_entry_velocity: Vector2, rising: bool, portal: TravelPortal) -> void:
	if _state != State.HOME or not rising:
		return

	if _link.host_target() == "":
		# Nobody there to catch him (their companion is not online). Rather than
		# hide him against an arrival that can never be confirmed, bounce him
		# straight back out.
		_klippy.say("Nobody's home...")
		_emerge_from_portal(portal)
		return

	_state = State.TRAVELING
	_trip_timer = TRIP_TIMEOUT

	_klippy.visit_absorb()
	_link.publish(LinkEvents.VISIT_ARRIVE, _appearance_payload(), _link.host_target())


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


## Right-click on the green portal: the only control surface left on this desktop
## that knows where the pet went.
func _show_portal_menu() -> void:
	if _portal_menu == null:
		_portal_menu = PopupMenu.new()
		_portal_menu.add_item("Call him back", 1)
		_portal_menu.add_item("Forget friend's server", 2)
		_portal_menu.add_item("Close portal", 3)
		_portal_menu.id_pressed.connect(_on_portal_menu_id_pressed)
		RockyTheme.style_popup(_portal_menu)
		_portal.add_child(_portal_menu)

	_portal_menu.set_item_disabled(0, _state != State.AWAY)
	_portal_menu.set_item_disabled(1, is_visiting())
	_portal_menu.set_item_disabled(2, is_visiting())
	_portal_menu.position = DisplayServer.mouse_get_position()
	_portal_menu.popup()


func _on_portal_menu_id_pressed(id: int) -> void:
	match id:
		1:
			_recall()
		2:
			forget_pairing()
		3:
			forget_portal()


## Owner-initiated "call him back": the friend's side opens the exit on top of
## the pet and answers with visit.departed once he is through it.
func _recall() -> void:
	if _state != State.AWAY:
		return

	_state = State.RECALLING
	_trip_timer = TRIP_TIMEOUT
	_link.publish(LinkEvents.VISIT_RECALL, null, _link.host_target())


## A word from the pet while he is away — used for the owner's own reminders
## coming due over on the friend's monitor.
func speak(text: String) -> void:
	if _state != State.AWAY:
		return
	_link.publish(LinkEvents.VISIT_SPEAK, {"text": text}, _link.host_target())


func _on_guest_event(type: String, payload: Dictionary, source: String) -> void:
	match type:
		LinkEvents.VISIT_ARRIVED:
			if _state == State.TRAVELING:
				_state = State.AWAY

		LinkEvents.VISIT_DEPARTED:
			if _state == State.RECALLING:
				_return_home(true)

		LinkEvents.DEVICE_DISCONNECTED:
			# The friend's companion signing off ends the visit: nobody is left
			# over there to be showing him. (Their presence entry is already gone
			# from the peers list by the time this event arrives, so the kind on
			# the payload is the only way to tell who left.)
			if str(payload.get("deviceKind", "")) == LinkEvents.KIND_COMPANION \
					and is_visiting():
				_return_home(false)

		_:
			pass


func _on_guest_link_state_changed(state: GuestLink.State) -> void:
	# The socket to the friend's server is the trip's lifeline: without it the
	# pet is a figment on a screen nobody can confirm. Pop him back out and let
	# the portal stand by for another try.
	if state != GuestLink.State.CONNECTED and _state in [State.TRAVELING, State.AWAY, State.RECALLING]:
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


## The pet pops back out of the green portal. When [param announced] he came
## through the friend's exit on purpose, so the whole portal setup closes behind
## him — travel pair included. A failed trip keeps the portals up for another try.
func _return_home(announced: bool) -> void:
	_state = State.HOME

	if _portal == null or not is_instance_valid(_portal):
		return

	if announced:
		_klippy.say("Home sweet home!")
	_emerge_from_portal(_portal)

	if announced:
		_close_portal()
		_klippy.banish_travel_portals()
		_link.disconnect_from_server()

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
