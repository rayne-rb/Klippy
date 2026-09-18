# Klippy

Klippy is a Clippy-inspired desktop pet — a small rock that lives on your desktop.

## Requirements

- Godot Engine **4.7**
- Linux or Windows (not tested/targeted on macOS)

## Features

- Drag and throw Klippy with real physics, allowing him to interact with the desktop
- Food, mood, and health stats: feeding, passive healing, starvation, death, and revival
- Right-click menu: Feed, Summon Food, Summon Portals, Status, Skills, Reminders, DVD mode, Connection, Settings, Close (plus Revive / Dev Tools when relevant)
- Travel portals: place as many as you like and drag them anywhere (any monitor) — the first summon makes a blue/red pair across monitors; throw Klippy into one and he flies out of the next portal in the chain
- Friend portal: a green portal onto another Klippy's monitor — both companions paired to the same server, pick the other one and a portal opens on both screens; throw Klippy in and he lives there until called back, and the friend can set reminders through him while he visits
- Reminders: set a message and a minutes-from-now and Klippy announces it in his speech bubble when it comes due — the bubble repeats until clicked, and reminders persist across launches
- State persists across launches, including offline progress while closed
- Pairs with Klippy.Server so the pet can be seen and poked from a phone
- Skills window: what Klippy can do with the rest of the setup. Audio Relay starts the
  PC's sound playing on a connected phone
- Dev Tools panel (enable in Settings) for nudging stats directly while testing

## Layout

Feature-slice: each folder under `features/` holds everything that feature needs.
GDScript registers `class_name` globally, so scripts refer to each other regardless
of which folder they sit in.

| Slice | What it holds |
| --- | --- |
| `pet` | `Klippy.gd`, the physics base in `PetBody.gd`, and the main scene |
| `food` | Food items and the spawner that pools them |
| `portals` | The linked blue/red travel portals Klippy can be thrown through |
| `stats` | Vitals and the Status window |
| `skills` | The Skills window and the cards in it, one per thing Klippy can be put to |
| `dialogue` | What Klippy says, and the speech bubble it says it in |
| `reminders` | Scheduling a message for N minutes from now, keeping it in the save, and nagging about it |
| `settings` | The Settings window |
| `devtools` | The Dev Tools window |
| `discovery` | Finds a Klippy server on the network |
| `pairing` | The pairing handshake and the Connection window |
| `link` | The WebSocket to the server — registered as the `KlippyLink` autoload |
| `remote` | Turns link events into things the pet does, and vice versa |
| `visit` | The green friend portal: trips to another user's monitor, hosting visitors, guest reminders |

`shared/` holds only what has no single owner, and `assets/` the art.

### Talking to the server

`KlippyLink` is an autoload, so any slice can reach it without being handed a
reference:

```gdscript
KlippyLink.publish(LinkEvents.PET_SPOKE, {"text": "hello"})
KlippyLink.event_received.connect(_on_event_received)
```

`KlippyLink` also keeps `peers` — the other devices on the same server, from the welcome
message and the presence events — so a slice can ask what is out there (`peers_of_kind`)
without a round trip, and `publish` takes an optional device id to address one of them
rather than everyone.

The pet itself does not know the link exists. `RemoteControl` is handed the few things
that can be driven remotely and bridges the two, so the link can be broken or absent
and the pet carries on regardless.

Event names live in `features/link/LinkEvents.gd` and mirror `KlippyEvents.cs` in
`Klippy.Shared` by hand — GDScript cannot reference a .NET assembly. Add a name in
both places or the event goes nowhere.

## Checks

Klippy cannot run headless, since it drives real windows through `DisplayServer`. This
runs it anyway for long enough to compile and start everything, then checks the scene,
autoload and asset paths:

```sh
tools/check.sh
```

Worth running after moving files: it is exactly the kind of breakage a reshuffle causes.

## Exporting

Klippy does not work properly when run through the Godot editor, so you'll need to export it to a binary.

1. Editor > Manage Export Templates — install templates matching your installed Godot version if you haven't already.
2. Project > Export, add a Linux or Windows preset.
3. Select an export directory and click "Export"
4. Run the resulting binary directly
