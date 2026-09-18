class_name VisitHost
extends Node

## The receiving end of a visit: turns a friend portal opened by another
## companion on the same server into a door on this machine's desktop, and the
## arrival behind it into a pet standing here.
##
## The visitor's companion and this one are two devices on one server, so from
## this machine's point of view a visit is just targeted `visit.*` events off the
## link we already hold. The hosting work is local: open our half of the doorway
## when the other end summons, dress the guest from his arrival payload, drop him
## next to our own pet, and answer the door events (arrived, departed).
##
## Whose visits open a door without asking is the one question this side has to
## answer, and the link answers most of it: another device of your own account is
## a peer, and walks in. A friend is a neighbour — somebody else's account on the
## same server — and the server carries their visit across a boundary that stops
## everything else, so they knock first ([VisitKnockDialog]) and the answer can be
## remembered ([VisitSettings]). A device that is neither gets nothing at all.
##
## Reminders the host user sets through the visiting pet live here too, in their
## own scheduler. They are a favor to the guest's stay — announced by the visitor
## on this monitor, dropped when the visit ends — and never touch the host pet's
## own reminders.

const ARRIVE_BURST_DELAY := 0.6
const ARRIVE_BURST_SPEED := 260.0
const SUCK_IN_DURATION := 0.5

var _klippy: Klippy
## This side's half of the doorway: the green portal shown while the other end
## has one open too. Nobody passes through it; it is the door he arrives at and
## the door he leaves from.
var _standing_portal: TravelPortal
## The other end of the current visit — the visitor device's id on this server.
var _visitor_id := ""
## Who the standing portal belongs to, so it can be taken back down if that
## device vanishes without a visit.close.
var _open_peer_id := ""
var _visitor: VisitingKlippy
var _visitor_window: Window
var _exit_portal: TravelPortal
var _guest_reminders: ReminderScheduler
var _guest_reminder_dialog: ReminderDialog
var _suck_in_tween: Tween
## Friends who may skip the knock.
var _settings: VisitSettings
## The question on screen, and who it is about, while a friend waits at the door.
var _knock: VisitKnockDialog
var _knocking_peer := ""


func setup(klippy: Klippy) -> void:
	_klippy = klippy
	_settings = VisitSettings.load_settings()

	_guest_reminders = ReminderScheduler.new()
	add_child(_guest_reminders)
	_guest_reminders.reminder_due.connect(_on_guest_reminder_due)

	KlippyLink.event_received.connect(_on_event_received)
	KlippyLink.state_changed.connect(_on_link_state_changed)
	KlippyLink.neighbors_changed.connect(_on_neighbors_changed)


## The friends this machine has stopped asking about, and how to stop letting them
## in — read by the visit dialog, which is where that list is undone.
func remembered_friends() -> Array[Dictionary]:
	return _settings.friends()


func forget_friend(device_id: String) -> void:
	_settings.forget(device_id)


func is_hosting() -> bool:
	return _visitor != null and is_instance_valid(_visitor)


# --- Inbound ------------------------------------------------------------------

func _on_event_received(type: String, payload: Dictionary, source: String) -> void:
	match type:
		LinkEvents.VISIT_OPEN:
			_on_portal_requested(source)

		LinkEvents.VISIT_CLOSE:
			if source == _knocking_peer:
				# They gave up on the door before it was answered.
				_dismiss_knock()
			if source == _open_peer_id and not is_hosting():
				_close_standing_portal()
				_open_peer_id = ""

		LinkEvents.VISIT_ARRIVE:
			_on_arrive(payload, source)

		LinkEvents.VISIT_RECALL:
			if source == _visitor_id and is_hosting():
				_depart_visitor()

		LinkEvents.VISIT_SPEAK:
			if source == _visitor_id and is_hosting():
				var text := str(payload.get("text", "")).strip_edges()
				if text != "":
					_visitor.say(text)

		LinkEvents.DEVICE_DISCONNECTED:
			_on_device_gone(str(payload.get("deviceId", "")))

		_:
			pass


func _on_link_state_changed(state: KlippyLink.State) -> void:
	# Without the link there is no way to know anything about the visitor — not
	# even that he is still wanted — so the visit ends rather than linger.
	if state != KlippyLink.State.CONNECTED:
		_end_visit()
		_close_standing_portal()
		_open_peer_id = ""
		_dismiss_knock()


func _on_device_gone(device_id: String) -> void:
	if device_id == "":
		return

	if device_id == _knocking_peer:
		# Nobody left at the door to let in.
		_dismiss_knock()

	if device_id == _visitor_id and is_hosting():
		# The visitor's connection is his lifeline: if his device went away,
		# whatever he is doing here is over.
		_end_visit()
	elif device_id == _open_peer_id and not is_hosting():
		# The summoner vanished without closing his end; ours would linger on
		# this desktop with nobody behind it.
		_close_standing_portal()
		_open_peer_id = ""


## A friend's Klippy has no device.disconnected to give us — that event stays inside
## an account — so their going offline reaches us as the neighbour list arriving
## without them in it.
func _on_neighbors_changed() -> void:
	for device_id in [_visitor_id, _open_peer_id, _knocking_peer]:
		if device_id != "" and not KlippyLink.is_device_online(device_id):
			_on_device_gone(device_id)


# --- The doorway ----------------------------------------------------------------

## Somebody summoned a portal onto this desktop. One of our own opens it on the
## spot; a friend is asked about first, unless they have been let in before.
func _on_portal_requested(source: String) -> void:
	if KlippyLink.is_peer(source):
		_open_doorway(source)
		return

	var friend := KlippyLink.neighbor(source)
	if friend.is_empty():
		# Neither ours nor anybody the server has told us about. Nothing to open
		# onto, and nothing worth saying to a device we do not know.
		return

	if _settings.is_allowed(source):
		_open_doorway(source)
		return

	_ask_to_let_in(source, friend)


func _open_doorway(source: String) -> void:
	_open_peer_id = source
	_spawn_standing_portal()


## Puts the question on the screen. Only ever asked about a neighbour, and only one
## at a time: a second knock replaces the first, which is also what happens to the
## doorway itself.
func _ask_to_let_in(source: String, friend: Dictionary) -> void:
	_dismiss_knock()

	_knocking_peer = source
	_knock = VisitKnockDialog.new()
	add_child(_knock)
	_knock.setup(_describe(friend))
	_knock.answered.connect(_on_knock_answered.bind(source, friend))
	_knock.popup_centered()


func _on_knock_answered(allow: bool, remember: bool, source: String, friend: Dictionary) -> void:
	_knock = null
	_knocking_peer = ""

	if not allow:
		# Answered rather than ignored, so the other end can take its own half of
		# the doorway down instead of waiting on a pet that is not coming.
		KlippyLink.publish(LinkEvents.VISIT_DECLINED, null, source)
		return

	if remember:
		_settings.allow(source, _describe(friend))

	_open_doorway(source)


func _dismiss_knock() -> void:
	if _knock != null and is_instance_valid(_knock):
		_knock.withdraw()
	_knock = null
	_knocking_peer = ""


## How a friend is named at the door: their Klippy and whose it is, since "Klippy on
## studio-pc" on its own says nothing about who is asking.
func _describe(friend: Dictionary) -> String:
	var device_name := str(friend.get("name", "")).strip_edges()
	if device_name == "":
		device_name = "A Klippy"

	var owner := str(friend.get("owner", "")).strip_edges()
	return device_name if owner == "" else "%s (%s)" % [device_name, owner]


## Whether an arrival from this device should be stood up on the screen at all. A
## door we opened is the usual answer; the rest is for the arrival that beats its own
## visit.open, or comes from a friend we long since stopped asking about.
func _may_host(source: String) -> bool:
	if source == "":
		return false
	return source == _open_peer_id or KlippyLink.is_peer(source) or _settings.is_allowed(source)


## The green door, placed next to our own pet on his screen — the spot an
## arriving guest bursts out of and gets pulled back into.
func _spawn_standing_portal() -> void:
	_close_standing_portal()

	_standing_portal = TravelPortal.new("green")
	_standing_portal.current_screen = _klippy.get_window().current_screen
	add_child(_standing_portal)
	_standing_portal.place(Vector2i(_doorway_spot()))


func _close_standing_portal() -> void:
	if _standing_portal != null and is_instance_valid(_standing_portal):
		_standing_portal.queue_free()
	_standing_portal = null


## Next to our own pet, shoved far enough over that the burst-out does not land
## the guest inside him.
func _doorway_spot() -> Vector2:
	var window := _klippy.get_window()
	var center := Vector2(window.position) + Vector2(window.size) / 2.0
	var offset := Vector2(window.size.x / 2.0 + TravelPortal.SIZE / 2.0 + 60.0, -20.0)

	var bounds := DisplayServer.screen_get_usable_rect(window.current_screen)
	var lo := Vector2(bounds.position) + Vector2(TravelPortal.SIZE, TravelPortal.SIZE) / 2.0
	var hi := Vector2(bounds.end) - Vector2(TravelPortal.SIZE, TravelPortal.SIZE) / 2.0
	return (center + offset).clamp(lo, hi)


# --- Visitor lifecycle ----------------------------------------------------------

func _on_arrive(payload: Dictionary, source: String) -> void:
	# A pet may only stand up here if his summoner was let in. Without this, a
	# declined knock is answered by simply arriving anyway.
	if not _may_host(source):
		return

	# One guest at a time: a second arrival replaces the first.
	if is_hosting():
		_end_visit()

	_visitor_id = source

	# The doorway is normally already open (visit.open came first); a host that
	# missed it still gets a door rather than a pet appearing from nowhere.
	if _standing_portal == null or not is_instance_valid(_standing_portal):
		_spawn_standing_portal()

	_build_visitor(payload)

	# The door is answered the moment the guest is built, not when he finishes
	# bursting out of it — the owner's side should stop holding its breath while
	# the animation is still playing.
	KlippyLink.publish(LinkEvents.VISIT_ARRIVED, null, _visitor_id)

	_burst_out_visitor()


func _build_visitor(payload: Dictionary) -> void:
	# A nonsense size from a misbehaving visitor must not build a 0-pixel window.
	var pet_size := clampi(int(payload.get("size", 200)), 50, 1000)
	var window_size := VisitingKlippy.window_size_for(pet_size)

	_visitor_window = Window.new()
	_visitor_window.borderless = true
	_visitor_window.transparent = true
	_visitor_window.always_on_top = true
	_visitor_window.unfocusable = true
	_visitor_window.size = window_size
	_visitor_window.content_scale_size = window_size

	_visitor = VisitingKlippy.new()
	_visitor.apply_appearance(payload)
	_visitor.host_pet = _klippy
	_visitor.menu_id_pressed.connect(_on_visitor_menu_id_pressed)
	_visitor_window.add_child(_visitor)
	add_child(_visitor_window)

	_visitor.scale_to_size(pet_size)

	var portal_center := _standing_portal.center()
	_visitor_window.position = Vector2i(portal_center - Vector2(window_size) / 2.0)
	_visitor_window.hide()


func _burst_out_visitor() -> void:
	await get_tree().create_timer(ARRIVE_BURST_DELAY).timeout

	if not is_hosting():
		return

	# Out of the doorway and away from the host pet, so the arrival does not
	# land the guest on top of him.
	var host_center := Vector2(_klippy.get_window().position) \
			+ Vector2(_klippy.get_window().size) / 2.0
	var away_from_host := (_standing_portal.center() - host_center).normalized()
	if away_from_host == Vector2.ZERO:
		away_from_host = Vector2.RIGHT
	_visitor.velocity = away_from_host.rotated(randf_range(-0.4, 0.4)) * ARRIVE_BURST_SPEED
	_visitor.state = PetBody.State.THROWN
	_visitor_window.show()

	_visitor.say(Dialogue.random_greeting())


## Called from the visitor's own menu: he leaves under his own steam, so the
## owner only learns he is on the way.
func _on_visitor_menu_id_pressed(id: int) -> void:
	match id:
		VisitingKlippy.MENU_REMINDERS_ID:
			_open_guest_reminders()
		VisitingKlippy.MENU_SEND_HOME_ID:
			_depart_visitor()


## The return, from either side: a portal opens right on top of the guest ("call
## him back" from the owner, or "send home" from the visitor's own menu), he is
## pulled into it, and only then is the owner told he is gone — the message and
## the pet travel together. Both halves of the doorway come down behind him.
func _depart_visitor() -> void:
	if not is_hosting() or _suck_in_tween != null:
		return

	_close_standing_portal()

	# The visitor may have been dragged anywhere; the exit opens where he stands.
	_exit_portal = TravelPortal.new("green")
	_exit_portal.current_screen = _visitor_window.current_screen
	add_child(_exit_portal)
	_exit_portal.place(Vector2i(_visitor_center()))

	# The tween owns his motion for the next half second; physics must not fight
	# it for the window's position (the same freeze the sell portal uses while an
	# item waits on a price).
	_visitor.velocity = Vector2.ZERO
	_visitor.angular_velocity = 0.0
	_visitor.set_physics_process(false)

	_suck_in_tween = create_tween()
	_suck_in_tween.set_parallel(true)
	_suck_in_tween.tween_property(_visitor, "sprite:scale",
			_visitor.sprite.scale * 0.05, SUCK_IN_DURATION).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)
	_suck_in_tween.tween_property(_visitor_window, "position",
			Vector2i(_exit_portal.center() - Vector2(_visitor_window.size) / 2.0),
			SUCK_IN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_suck_in_tween.chain().tween_callback(_end_visit.bind(true))


## Tears the visit down: the pet is gone from this screen and both halves of the
## doorway come with him. [param announce] sends visit.departed so the owner's
## side can pop him out at home; a vanished visitor (app closed, link dropped)
## says nothing, because there is nobody to say it to.
func _end_visit(announce := false) -> void:
	if _suck_in_tween != null:
		_suck_in_tween.kill()
		_suck_in_tween = null

	var id := _visitor_id
	_visitor_id = ""

	if _visitor != null and is_instance_valid(_visitor):
		_visitor.queue_free()
	_visitor = null

	if _visitor_window != null and is_instance_valid(_visitor_window):
		_visitor_window.queue_free()
	_visitor_window = null

	if _exit_portal != null and is_instance_valid(_exit_portal):
		_exit_portal.queue_free()
	_exit_portal = null

	if announce and id != "":
		KlippyLink.publish(LinkEvents.VISIT_DEPARTED, null, id)

	_close_guest_reminders()
	if _guest_reminders != null:
		_guest_reminders.reminders.clear()


func _visitor_center() -> Vector2:
	return Vector2(_visitor_window.position) + Vector2(_visitor_window.size) / 2.0


# --- The guest's reminders ------------------------------------------------------

func _open_guest_reminders() -> void:
	if _guest_reminder_dialog == null:
		_guest_reminder_dialog = ReminderDialog.new()
		add_child(_guest_reminder_dialog)
		_guest_reminder_dialog.setup(_guest_reminders)
	_guest_reminder_dialog.popup_centered()


func _close_guest_reminders() -> void:
	if _guest_reminder_dialog != null and is_instance_valid(_guest_reminder_dialog):
		_guest_reminder_dialog.queue_free()
	_guest_reminder_dialog = null


## Reminders set through the visiting pet are announced by the visiting pet, on
## this monitor — the whole point of setting one through him.
func _on_guest_reminder_due(reminder: Dictionary) -> void:
	var message := str(reminder.get("message", "")).strip_edges()
	if message.is_empty():
		return
	if not is_hosting():
		return
	_visitor.announce_reminder(message)
