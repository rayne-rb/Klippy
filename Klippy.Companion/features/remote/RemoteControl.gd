class_name RemoteControl
extends Node

## Makes the pet answerable to the rest of the system.
##
## Two directions, both narrow on purpose:
##   inbound  - commands off the link become things the pet does
##   outbound - things the pet does become events on the link
##
## The pet itself knows nothing about any of this. It hands over what can be driven
## remotely in [method setup] and carries on as before, so the link can be absent,
## broken, or removed entirely without the pet caring.

## Vitals drift continuously, so they go out on a timer rather than on every change.
const STATS_INTERVAL := 5.0

var _stats: PetStats
var _spawner: FoodSpawner
var _speak: Callable
var _set_dvd: Callable
var _stats_timer := 0.0
var _stats_dirty := false


func setup(stats: PetStats, spawner: FoodSpawner, speak: Callable, set_dvd: Callable) -> void:
	_stats = stats
	_spawner = spawner
	_speak = speak
	_set_dvd = set_dvd

	KlippyLink.event_received.connect(_on_event_received)
	KlippyLink.state_changed.connect(_on_link_state_changed)

	_stats.food_changed.connect(_on_stat_changed)
	_stats.mood_changed.connect(_on_stat_changed)
	_stats.health_changed.connect(_on_stat_changed)
	_stats.died.connect(_on_died)
	_stats.revived.connect(_on_revived)

	set_process(true)


# --- Inbound: the link tells the pet what to do -------------------------------

func _on_event_received(type: String, payload: Dictionary, _source: String) -> void:
	match type:
		LinkEvents.PET_FEED:
			var count: int = clampi(int(payload.get("count", 1)), 1, FoodSpawner.MAX_ITEMS)
			for _i in count:
				if not _spawner.spawn():
					break

		LinkEvents.PET_SAY:
			var text: String = str(payload.get("text", "")).strip_edges()
			if text != "":
				_speak.call(text)
				# Report it back so the phone can see the pet said it.
				KlippyLink.publish(LinkEvents.PET_SPOKE, {"text": text})

		LinkEvents.PET_DVD_TOGGLE:
			_set_dvd.call(bool(payload.get("enabled", false)))

		LinkEvents.PET_STATS_REQUEST:
			_publish_stats()


# --- Outbound: the pet tells the link what it did ------------------------------

func _on_link_state_changed(state: KlippyLink.State) -> void:
	# Report vitals as soon as there is somewhere to report them to, so the phone
	# and the server are not staring at a blank until the next tick.
	if state == KlippyLink.State.CONNECTED:
		_publish_stats()


func _on_stat_changed(_value: float) -> void:
	_stats_dirty = true


func _on_died() -> void:
	KlippyLink.publish(LinkEvents.PET_DIED)
	_publish_stats()


func _on_revived() -> void:
	KlippyLink.publish(LinkEvents.PET_REVIVED)
	_publish_stats()


func _process(delta: float) -> void:
	if not _stats_dirty:
		return

	_stats_timer += delta
	if _stats_timer < STATS_INTERVAL:
		return

	_publish_stats()


func _publish_stats() -> void:
	_stats_timer = 0.0
	_stats_dirty = false

	if _stats == null:
		return

	KlippyLink.publish(LinkEvents.PET_STATS, {
		"food": _stats.food,
		"mood": _stats.mood,
		"health": _stats.health,
		"isDead": _stats.is_dead,
		"feedingEnabled": _stats.feeding_enabled,
		"foodStatus": _stats.get_status(),
		"moodStatus": _stats.get_mood_status(),
		"healthStatus": _stats.get_health_status(),
	})
