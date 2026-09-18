class_name LinkEvents
extends RefCounted

## Event names carried on the link. This mirrors KlippyEvents.cs in Klippy.Shared;
## the Companion is GDScript and cannot reference that assembly, so the two lists
## have to be kept in step by hand. Add a name in both places or the event silently
## goes nowhere.

# Reported by us, of interest to the server and the phone.
const PET_STATS := "pet.stats"
const PET_DIED := "pet.died"
const PET_REVIVED := "pet.revived"
const PET_SPOKE := "pet.spoke"

# Commands aimed at us.
const PET_FEED := "pet.feed"
const PET_SAY := "pet.say"
const PET_DVD_TOGGLE := "pet.dvd.toggle"
const PET_STATS_REQUEST := "pet.stats.request"

# Link lifecycle, sent by the server.
const DEVICE_CONNECTED := "device.connected"
const DEVICE_DISCONNECTED := "device.disconnected"
const LINK_WELCOME := "link.welcome"
const LINK_PING := "link.ping"
const LINK_PONG := "link.pong"

# Audio cast control. The audio itself never touches the link — the server captures
# and encodes it, the phone receives it over UDP. All the Companion does is ask a
# phone to listen and read back what came of it.
const AUDIO_CAST_REQUEST := "audio.cast.request"
const AUDIO_CAST_STATE := "audio.cast.state"

# Market. Listing and buying go over plain HTTP (see MarketClient) since both want a
# real success-or-failure response; only a payout to a seller who may be offline
# rides the link.
const MARKET_PAYOUT := "market.payout"
const MARKET_PAYOUT_ACK := "market.payout.ack"

# Visits. A visit connects two Klippy companions paired to the same server — the
# klippy network is the server's device list — so these ride the ordinary link,
# always targeted at the companion on the other end. The server only routes
# them; both ends are companions. See the visit slice.
const VISIT_OPEN := "visit.open"
const VISIT_CLOSE := "visit.close"
const VISIT_ARRIVE := "visit.arrive"
const VISIT_ARRIVED := "visit.arrived"
const VISIT_RECALL := "visit.recall"
const VISIT_DEPARTED := "visit.departed"
const VISIT_SPEAK := "visit.speak"

# Device kinds, mirroring DeviceKind.cs in Klippy.Shared. Kept here with the event
# names for the same reason: it is a wire constant the server decides, not ours.
const KIND_COMPANION := "companion"
const KIND_MOBILE := "mobile"
