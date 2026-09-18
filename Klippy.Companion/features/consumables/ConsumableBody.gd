class_name ConsumableBody
extends PetBody

signal consumed
## Fired once, the tick this item first drifts within reach of [member sell_portal].
## Whoever catches it (see [method Klippy._on_consumable_sell_requested]) is
## responsible for clearing [member pending_sale] again if the sale doesn't
## actually go through, or this item will never be sellable again.
signal sell_requested

var stats: PetStats
var klippy: PetBody
var bag: ConsumableBagBody
var contained_in: ConsumableBagBody
var consumable_type: String = ConsumableCatalog.APPLE

## The current sell portal, or null when none is open. Kept in step by Klippy
## rather than looked up here, the same way [member bag] is — see
## [method Klippy._apply_sell_portal_to_active_items].
var sell_portal: SellPortal
## True from the moment [signal sell_requested] fires until the sale either
## lists or is handed back, so one lingering drift through the portal's radius
## doesn't fire it over and over.
var pending_sale := false

## Below this speed a bagged-and-settled item counts as stopped for [method
## _check_bag]'s sleep check — [constant PetBody.REST_SPEED] is how hard a
## bounce has to be cancelled rather than reflected, too high a bar for "has
## this actually stopped moving".
const SLEEP_SPEED := 1.0

## Every consumable item currently in the tree (bag-contained, loose on the
## desktop, or pooled-and-hidden alike), so any one of them can find the rest
## to collide with. Nothing here is a manager pass; each item just looks up
## its own neighbors and resolves against those that haven't been resolved yet
## this tick (see [method _resolve_consumable_collisions]).
static var _all_consumables: Array[ConsumableBody] = []


func _enter_tree() -> void:
	_all_consumables.append(self)


func _exit_tree() -> void:
	_all_consumables.erase(self)


func _physics_process(delta: float) -> void:
	var pre_move_position := get_window().position
	super._physics_process(delta)

	if state == State.DRAGGING:
		contained_in = null
		return

	_resolve_consumable_collisions(delta)
	_check_bag(delta, pre_move_position)
	_check_feeding()
	_check_market_sell()


## Bounces this item off every other live consumable item it overlaps, using
## the same circle-circle math [method PetBody._resolve_body_collision]
## already uses for Klippy-vs-bag. Walking the shared registry from just past
## this item's own index means each pair only ever gets resolved once per
## tick, no matter which of the two items happens to process first.
func _resolve_consumable_collisions(delta: float) -> void:
	var index := _all_consumables.find(self)
	if index == -1:
		return

	for i in range(index + 1, _all_consumables.size()):
		var other := _all_consumables[i]
		if not is_instance_valid(other) or not other.is_physics_processing():
			continue
		_resolve_body_collision(other, delta)


## A bag-associated item has no floor of its own to rest on the way loose
## consumables do on the real desktop, so it must never latch into a static
## [constant State.IDLE] — that would just freeze it wherever gravity
## happened to zero its velocity for one tick. A consumable with no bag keeps
## the normal desktop resting behavior.
func _can_rest() -> bool:
	return bag == null


func _process_idle_base(_delta: float, _window: Window) -> void:
	if bag != null:
		_set_state(State.THROWN)


## "Stored" is a live membership test against the bag's background art, not a
## sticky flag: a consumable item only counts while it is actually sitting
## over the background this frame, so one that has rolled back out is no
## longer saved with the bag. The bag's walls are a real physical obstacle
## here (see [method ConsumableBagBody.resolve_consumable_wall_collision])
## rather than a place that pins the item in position, so a stored item keeps
## rolling/settling like any other consumable — it's just confined to the
## bag's interior.
func _check_bag(delta: float, pre_move_position: Vector2i) -> void:
	contained_in = null
	if bag == null:
		return

	var bag_window := bag.get_window()
	var item_window := get_window()
	var half_size := Vector2(item_window.size) / 2.0

	# Both measured as of the start of this tick, before anything moved —
	# the item's true position relative to the bag a moment ago.
	var prev_local_center := Vector2(pre_move_position - bag.tick_start_position) + half_size

	# Carry the item along with however far the bag itself moved this tick,
	# same as a real bag drags its contents when picked up — otherwise a
	# fast drag/throw of the bag just leaves loose contents behind in
	# mid-air, which looks exactly like the item escaping. Only carry it if it
	# was actually inside the bag's footprint a moment ago; an item elsewhere
	# shouldn't jump just because some unrelated bag moved.
	if Rect2(Vector2.ZERO, Vector2(bag_window.size)).has_point(prev_local_center):
		item_window.position += bag.movement_delta_this_tick()

	# The wall keeps holding contents in place even while the bag is closed —
	# a real bag doesn't spill what's inside just because you can't see it —
	# so this has to keep running regardless of [member Window.visible].
	# Skipping it while hidden used to mean gravity kept right on pulling
	# the item down with nothing to stop it, so by the time the bag reopened
	# the contents had often fallen straight out through where the (now
	# uncollidable) wall used to be.
	bag.resolve_consumable_wall_collision(self, prev_local_center, delta)

	# The collision may have just moved the window, so re-derive this rather
	# than reuse the pre-collision value above.
	var local_center := Vector2(item_window.position - bag_window.position) + half_size
	var over_bag := Rect2(Vector2.ZERO, Vector2(bag_window.size)).has_point(local_center)

	# A closed bag tucks away whatever is inside it; an item sitting elsewhere
	# on the desktop shouldn't vanish just because the bag elsewhere got
	# closed.
	item_window.visible = bag_window.visible or not over_bag

	# Keep it above the bag's background whenever it's anywhere over the bag
	# at all, not just once it's confirmed "stored" — otherwise it can sit
	# behind the background art (invisible) for however long it takes to
	# settle into the stricter interior zone.
	if bag_window.visible and over_bag:
		item_window.move_to_foreground()

	if bag.contains_point(local_center):
		contained_in = bag

	# Once the bag is closed and this item has actually come to rest against
	# its wall (not just mid-settle), nothing left in [method _check_bag] or
	# [method _resolve_consumable_collisions] can ever move it again until the
	# bag reopens — so stop paying for wall/collision resolution every tick
	# and let [method Klippy._raise_contained_consumables] wake it back up
	# when that happens.
	if not bag_window.visible and over_bag and velocity.length() < SLEEP_SPEED \
			and bag.movement_delta_this_tick() == Vector2i.ZERO:
		set_physics_process(false)


func _check_feeding() -> void:
	if klippy == null or stats == null:
		return
	if not get_window().visible:
		return

	var klippy_window := klippy.get_window()
	var item_window := get_window()
	var klippy_center := Vector2(klippy_window.position) + Vector2(klippy_window.size) / 2.0
	var item_center := Vector2(item_window.position) + Vector2(item_window.size) / 2.0

	if klippy_center.distance_to(item_center) <= klippy.roll_radius + roll_radius:
		stats.feed(ConsumableCatalog.get_def(consumable_type).feed_amount)
		consumed.emit()


## Loose (not stored in a bag, not mid-sale already) and drifted within reach
## of [member sell_portal], if one is even open right now.
func _check_market_sell() -> void:
	if sell_portal == null or pending_sale or contained_in != null or not get_window().visible:
		return

	var item_window := get_window()
	var item_center := Vector2(item_window.position) + Vector2(item_window.size) / 2.0

	if sell_portal.center().distance_to(item_center) <= sell_portal.radius() + roll_radius:
		pending_sale = true
		sell_requested.emit()


## Switches this item to another [ConsumableCatalog] entry: swaps in its
## texture and rescales the sprite to fill this item's window regardless of
## the source art's native resolution, since a pooled window is reused across
## whatever consumable spawns into it next.
func apply_consumable_type(new_consumable_type: String) -> void:
	consumable_type = new_consumable_type

	var texture := ConsumableCatalog.get_def(consumable_type).texture
	sprite.texture = texture

	var largest_side := maxf(texture.get_size().x, texture.get_size().y)
	var window_size := get_window().size.x
	sprite.scale = Vector2.ONE * (window_size / largest_side if largest_side > 0.0 else 1.0)
