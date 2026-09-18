class_name MarketMailbox
extends Node

## Applies a seller's market payouts as they arrive over the link, and tells
## the server to stop resending each one once it has (see
## LinkEvents.MARKET_PAYOUT / MARKET_PAYOUT_ACK and the server's
## MarketEventHandler, which resends anything not yet acknowledged on every
## reconnect).
##
## An acknowledgement can be lost after this end already credited the points
## for it (a crash or a dropped connection between the two), in which case the
## same payout arrives again on the next reconnect. Remembering applied ids
## and just re-acknowledging a repeat, rather than crediting it twice, is what
## keeps that retry from turning into free points.

## Capped rather than kept forever: a payout the server has already recorded
## delivered can never be resent, so remembering more than a session or two's
## worth buys nothing.
const MAX_REMEMBERED := 100

var _points: KlippyPoints
var _applied: Array[String] = []
var _save: Callable


## [param applied_payout_ids] is last session's [method to_save_data]. [param save]
## is called after crediting a new payout, so the id is on disk before the ack
## that tells the server to stop resending it.
func setup(points: KlippyPoints, applied_payout_ids: Array, save: Callable) -> void:
	_points = points
	_save = save
	_applied = []
	for id in applied_payout_ids:
		_applied.append(str(id))

	KlippyLink.event_received.connect(_on_event_received)


func to_save_data() -> Array:
	return _applied.duplicate()


func _on_event_received(type: String, payload: Dictionary, _source: String) -> void:
	if type != LinkEvents.MARKET_PAYOUT:
		return

	var payout_id := str(payload.get("payoutId", ""))
	if payout_id == "":
		return

	if not _applied.has(payout_id):
		var price := int(payload.get("price", 0))
		if price > 0:
			_points.add_points(price)
		_applied.append(payout_id)
		while _applied.size() > MAX_REMEMBERED:
			_applied.pop_front()
		_save.call()

	KlippyLink.publish(LinkEvents.MARKET_PAYOUT_ACK, {"payoutId": payout_id})
