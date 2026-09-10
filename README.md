# Klippy

A desktop pet that is also a PC assistant, plus the server that backs it and a phone
app that can reach it.

| Project | What it is |
| --- | --- |
| [Klippy.Companion](Klippy.Companion/README.md) | Godot 4.7 desktop pet — the face of the thing, and what you meet first |
| [Klippy.Server](Klippy.Server/README.md) | ASP.NET Core server and config UI — owns the data and the heavy lifting |
| Klippy.Mobile | .NET MAUI app — pairs to the server so Klippy is reachable from a phone |
| Klippy.Shared | The contracts that cross the wire |

## How the three fit together

Everything goes through the server. The Companion and the phone each hold one
WebSocket to it and exchange a single message shape, so a new capability is a new
event name rather than a new connection between apps.

```
  Klippy.Companion  ─┐                        ┌─  Klippy.Mobile
   (Godot/GDScript)  │                        │      (MAUI)
                     ├──►  Klippy.Server  ◄───┤
                     │    ├ routes events     │
                     │    ├ reacts to them    │
                     │    └ stores them       │
                     └────────────────────────┘
                              Postgres
```

Devices find the server on their own. There is no address to type anywhere: the
server announces itself over UDP multicast and answers probes, so a device that has
just launched gets an answer in milliseconds.

Pairing is approve-on-the-server. A device shows a six-character code, and that same
code is confirmed on the server's **Devices** page. Only then is a token issued.

## Architecture

Feature-slice, in all three apps. A slice owns everything it needs — its data access,
its endpoints, its UI, its registration — and only genuinely shared things live
outside one. In practice that means `Features/<slice>/` in the .NET projects and
`features/<slice>/` in the Godot project, with `Klippy.Shared` reserved for the
contracts that actually cross the wire.

The Companion is GDScript and cannot reference `Klippy.Shared`, so its event names
are mirrored by hand in `features/link/LinkEvents.gd`. Add a name in both places.

## Running it

```sh
# 1. The database (each server instance runs its own for now).
cd Klippy.Server && docker compose up -d

# 2. The server. It migrates the schema on startup and starts advertising itself.
dotnet run --project Klippy.Server

# 3. The pet. Export it first — it does not behave properly under the Godot editor.
#    See Klippy.Companion/README.md.

# 4. The phone.
dotnet build Klippy.Mobile -t:Run -f net10.0-android
```

Then open <http://localhost:5068/devices> and approve whatever asks to pair.

## Working on it

- **Rider** — open `Klippy.sln`. The .NET projects are normal; the Godot project
  appears as solution folders mirroring its slices.
- **Godot editor** — open `Klippy.Companion` directly, not the repository root.

The Godot project is not an MSBuild project, so its listing in `Klippy.sln` does not
update itself. After adding a slice or a source file:

```sh
python3 tools/regen-solution.py
```

## Checks

```sh
dotnet build Klippy.sln              # server, shared, mobile
Klippy.Companion/tools/check.sh      # companion, headless
```
