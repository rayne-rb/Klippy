class_name VisitKnockDialog
extends Window

## Somebody else's Klippy is at the door.
##
## A visit from another device of your own account opens silently — those are your
## machines. A friend on the same server is a different matter: the server will carry
## their visit across the account boundary, and this is the only thing between that and
## a pet appearing on your desktop unasked.
##
## Three answers, because "yes" means two different things: once, or from now on (see
## [VisitSettings]). Closing the window is "not now", which is also what happens if it is
## still standing when the knocker gives up.

## [param allow] is whether to open the door, [param remember] whether to stop asking
## about this friend.
signal answered(allow: bool, remember: bool)

var _answered := false


func setup(visitor_name: String) -> void:
	var vbox := RockyTheme.setup_window(self, "Knock, knock")

	var label := Label.new()
	label.text = "%s wants to come over.\nShall the pet in?" % visitor_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(label)

	var once := Button.new()
	once.text = "Let them in"
	once.theme_type_variation = "ButtonPrimary"
	once.pressed.connect(_answer.bind(true, false))
	vbox.add_child(once)

	var always := Button.new()
	always.text = "Always let them in"
	always.pressed.connect(_answer.bind(true, true))
	vbox.add_child(always)

	var never := Button.new()
	never.text = "Not now"
	never.pressed.connect(_answer.bind(false, false))
	vbox.add_child(never)

	# The ✕ and the window manager both mean the same as "Not now": nobody gets in on
	# a question that was dismissed rather than answered.
	close_requested.connect(_answer.bind(false, false))


## Takes the question off the screen without an answer — the knocker changed their mind,
## or went away. Silent, so a stale door is never opened on a dismissed question.
func withdraw() -> void:
	_answered = true
	queue_free()


func _answer(allow: bool, remember: bool) -> void:
	# The buttons and the close button can all land in the same frame; the first one
	# through is the answer.
	if _answered:
		return
	_answered = true

	answered.emit(allow, remember)
	queue_free()
