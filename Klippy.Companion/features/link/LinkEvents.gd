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
