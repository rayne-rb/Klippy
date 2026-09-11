class_name ServerDiscovery
extends Node

## Finds a Klippy server on the local network without anybody typing an address.
##
## The server both announces itself periodically and answers direct probes. We use
## the probe path: send a small datagram to the multicast group, and the server
## replies straight back to our socket. That means we never have to join the group
## ourselves, which sidesteps picking a network interface to join it on.

signal server_found(beacon: Dictionary)

const MULTICAST_ADDRESS := "239.255.71.84"
const PORT := 47814
const PROBE_MAGIC := "KLIPPY-DISCOVER/1"
const BEACON_MAGIC := "KLIPPY-SERVER/1"
const PROBE_INTERVAL := 2.0

var _udp: PacketPeerUDP
var _probe_timer := 0.0
var _searching := false


func start() -> void:
	if _searching:
		return

	_udp = PacketPeerUDP.new()
	var err := _udp.bind(0)
	if err != OK:
		push_warning("Discovery could not open a UDP socket (error %d)" % err)
		_udp = null
		return

	_udp.set_dest_address(MULTICAST_ADDRESS, PORT)
	_searching = true
	# Probe straight away rather than waiting out the first interval.
	_probe_timer = PROBE_INTERVAL
	set_process(true)


func stop() -> void:
	_searching = false
	set_process(false)
	if _udp != null:
		_udp.close()
		_udp = null


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not _searching or _udp == null:
		return

	_probe_timer += delta
	if _probe_timer >= PROBE_INTERVAL:
		_probe_timer = 0.0
		_udp.put_packet(PROBE_MAGIC.to_utf8_buffer())

	while _udp.get_available_packet_count() > 0:
		var text := _udp.get_packet().get_string_from_utf8()
		var beacon := _parse_beacon(text)
		if not beacon.is_empty():
			server_found.emit(beacon)
			return


## Returns the beacon's fields, or an empty dictionary for anything that is not one.
func _parse_beacon(datagram: String) -> Dictionary:
	if not datagram.begins_with(BEACON_MAGIC):
		return {}

	var newline := datagram.find("\n")
	if newline < 0:
		return {}

	var parsed: Variant = JSON.parse_string(datagram.substr(newline + 1))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	var beacon: Dictionary = parsed
	if not beacon.has("serverId") or not beacon.has("baseUrl") or not beacon.has("wsUrl"):
		return {}

	return beacon
