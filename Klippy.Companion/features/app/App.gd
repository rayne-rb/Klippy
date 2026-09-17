extends Node

## Klippy used to be the app's primary/embedded window. That window's
## position gets silently reset by the OS between physics ticks in a way
## secondary [Window] nodes never exhibit — that's what left his landing
## bounce unable to settle (see [method PetBody._process_thrown]) even after
## the consumable bag and wardrobe, which are already built as secondary windows,
## were fixed to rest flush with the screen edge. Spawning him into his own
## secondary window, the same way, sidesteps the problem instead of chasing
## it. This root only exists to keep the real primary window out of sight and
## host that window for him.

const KLIPPY_SCENE := preload("res://features/pet/Klippy.tscn")
const DEFAULT_SIZE := 200


func _ready() -> void:
	var window := Window.new()
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	window.unfocusable = true

	var window_size := Vector2i(DEFAULT_SIZE, DEFAULT_SIZE)
	window.size = window_size
	window.content_scale_size = window_size

	var bounds := DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	window.position = bounds.position + (bounds.size - window_size) / 2

	# DisplayServer only registers a Window's id once it has actually been
	# shown at least once — hiding it before this point (as opposed to right
	# after, the way the consumable bag and wardrobe do it) leaves Klippy's
	# mouse-passthrough setup unable to find it. So this stays visible=true
	# (the default) through creation; the primary window itself can't be
	# hidden at all (Godot refuses), which is why it's kept 1x1 via project
	# settings instead — borderless and transparent make that imperceptible.
	var klippy := KLIPPY_SCENE.instantiate()
	window.add_child(klippy)
	add_child(window)

	# Klippy starts State.IDLE with zero velocity like every PetBody, which
	# never moves on its own — nothing was ever dropping him onto the floor
	# on launch; center-screen (see above) is just where he'd stay forever.
	# The consumable bag and wardrobe only ever reach the floor because the player
	# drags and releases them, which throws them into gravity. A zero-velocity
	# THROWN is a no-op too (PetBody._process_thrown bails straight back to
	# IDLE when velocity is exactly zero), so this needs a tiny downward nudge
	# to actually start the fall.
	klippy.state = PetBody.State.THROWN
	klippy.velocity = Vector2(0.0, 1.0)
