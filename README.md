# Klippy

A desktop pet that is also a PC assistant, the server that backs it, a phone app that
can reach it — and, as of the audio cast, a way to hear your PC through your phone.

| Project | What it is |
| --- | --- |
| [Klippy.Companion](Klippy.Companion/README.md) | Godot 4.7 desktop pet — the face of the thing, and what you meet first |
| [Klippy.Server](Klippy.Server/README.md) | ASP.NET Core server and MudBlazor config UI — owns the data, the skills, and audio capture |
| Klippy.Mobile | .NET MAUI app — pairs to the server, pokes the pet, plays the cast |
| Klippy.Shared | The contracts that cross the wire |
| Klippy.Tests | Every test in the solution, plus the hand-run AudioCast bench probe |

## How the pieces fit together

Everything goes through the server, over two paths that are deliberately not the same
path.

**Control** is one WebSocket per device carrying a single message shape
(`LinkEnvelope`), so a new capability is a new event name rather than a new connection
between apps. Envelopes are authenticated, ordered, reliable and persisted.

**Media** is a separate one-way UDP socket. Audio wants none of what the Link gives it:
a retransmit only ever delivers a frame that is already too late to play.

```
   Klippy.Companion                                   Klippy.Mobile
   (Godot/GDScript)                                       (MAUI)
          │                                                 │
          │        WebSocket · LinkEnvelope JSON             │
          └────────────►   Klippy.Server   ◄────────────────┘
                          ├ routes events
                          ├ reacts to them
                          ├ stores them  ──── Postgres
                          └ captures the system mix
                                   │
                                   └──── UDP · Opus, 5 ms ────►  Klippy.Mobile
```

Devices find the server on their own. There is no address to type: the server announces
itself over UDP multicast on `239.255.71.84:47814` and answers direct probes, so a
device that has just launched gets an answer in milliseconds. Where multicast cannot
reach — a VPN, mobile data, an emulator behind user-mode NAT — the phone will take a
typed address instead and remember it.

Pairing is approve-on-the-server. A device shows a six-character code, and that same
code is confirmed on the server's **Devices** page. Only then is a token issued, and the
approval endpoints refuse callers that are not on the server's own machine.

## Audio cast

The server captures the PC's post-mix system output — every application plus system
sounds, not per-application audio — and streams it to a paired phone. Stereo, full
quality, aimed at the lowest latency the stack allows.

| | |
| --- | --- |
| Capture | PulseAudio/PipeWire sink monitor on Linux, WASAPI loopback on Windows |
| Codec | Opus, 48 kHz, 5 ms frames, 128 kbps stereo / 64 kbps mono |
| Transport | UDP on port 43117 by default, 8-byte header plus one Opus packet |
| Fallback | The same packets over a WebSocket, for networks that punish UDP |
| Playback | Android `AudioTrack` as Media/Music, so speaker, wired and Bluetooth are one code path |

Control and negotiation ride the Link (`audio.cast.start` / `.stop` / `.offer` /
`.state`); only the bytes go over UDP. The media socket is unauthenticated by nature, so
each listener is handed an ephemeral 128-bit stream key in a targeted offer and repeats
it as a keepalive — which also makes the stream self-healing, since the server takes the
listener's endpoint from whatever address the hello arrived from. A phone that changes
IP simply reappears.

The listener side holds an adaptive jitter buffer rather than a fixed one. Home WiFi
throws occasional 30–50 ms spikes, and any fixed buffer smaller than the worst spike is
an audible dropout while any fixed buffer larger than the typical one is latency paid on
every frame forever.

Measured budget is ~27–40 ms of our own pipeline; end to end that lands at ~47–75 ms on
speaker or wired, and anywhere from 45 ms to 290 ms on Bluetooth depending entirely on
which codec the headphones negotiate. [`docs/audio-cast-plan.md`](docs/audio-cast-plan.md)
carries the numbers, the measurements behind them, and what has been settled.

**What is proven and what is not.** Linux capture, encoding, the UDP path and the
dashboard are verified by measurement on this machine; the jitter buffer is verified in
simulation. Windows capture and Android playback are compile-verified only — there is no
Windows box and no phone attached here. Treat those two ends with suspicion.

## Architecture

Feature-slice, in all three apps. A slice owns everything it needs — its data access, its
endpoints, its UI, its registration — and only genuinely shared things live outside one.
In practice that means `Features/<slice>/` in the .NET projects and `features/<slice>/`
in the Godot project.

| Slice | Server | Companion | Mobile |
| --- | :---: | :---: | :---: |
| Discovery | ✓ | ✓ | ✓ |
| Pairing | ✓ | ✓ | ✓ |
| Link | ✓ | ✓ | ✓ |
| Pet | ✓ `PetState` | ✓ `pet` `food` `stats` `dialogue` `remote` | ✓ `Pet` |
| AudioCast | ✓ | — | ✓ (Android) |

`Klippy.Shared` is reserved for what actually crosses the wire: the envelope and event
names, the pairing and discovery contracts, the audio packet format, and the jitter
buffer — which lives there because it is pure logic driven by injected time, and so can
be tested against synthetic traces without a phone in the room.

One serializer configuration (`KlippyJson`) is stamped onto both the sockets and
ASP.NET's HTTP JSON options, so an HTTP response cannot drift from what the sockets
send. This matters more than it sounds: the Companion parses the result in GDScript,
where a null the sender thought was harmless is not substituted for by
`Dictionary.get(key, default)`.

Data access is RepoDb over Npgsql, no EF Core — typed helpers where the case is plain,
hand-written SQL where one statement beats a read-modify-write. The schema is applied by
grate in-process at startup. The phone keeps its own SQLite cache.

The Companion is GDScript and cannot reference `Klippy.Shared`, so its event names are
mirrored by hand in `features/link/LinkEvents.gd`. Add a name in both places.

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

Then open <http://localhost:5068/devices> and approve whatever asks to pair. The
**Audio** page picks which output to capture and shows who is listening.

Capture on Linux needs `parec` (PulseAudio or pipewire-pulse). Opus runs on a managed
port by default and will use a system `libopus` when one is loadable — worth having for
the ~11 MB/s of allocation it avoids while casting, which the Audio page warns about
when it is missing.

## Working on it

- **Rider** — open `Klippy.sln`. The .NET projects are normal; the Godot project appears
  as solution folders mirroring its slices.
- **Godot editor** — open `Klippy.Companion` directly, not the repository root.

The Godot project is not an MSBuild project, so its listing in `Klippy.sln` does not
update itself. After adding a slice or a source file:

```sh
python3 tools/regen-solution.py
```

## Checks

```sh
dotnet build Klippy.sln              # server, shared, mobile, tests
dotnet test Klippy.sln               # everything in Klippy.Tests
Klippy.Companion/tools/check.sh      # companion, headless
```

All .NET test code lives in `Klippy.Tests`, one project for the whole solution, laid
out by slice to mirror the code it covers.

### Probing the audio pipeline

The same project doubles as the AudioCast bench probe. Every failure mode in the cast
is timing-related, and timing bugs are miserable to debug in aggregate, so each stage
is proven on its own — capture without a codec, the codec without a network, the
server chain without a phone:

```sh
dotnet run --project Klippy.Tests -- devices   # what this machine can capture
dotnet run --project Klippy.Tests -- capture   # step 1: system mix -> float32 WAV
dotnet run --project Klippy.Tests -- codec     # encoder settings, timing, allocation
dotnet run --project Klippy.Tests -- stream    # capture -> broadcaster -> decoded WAV
dotnet run --project Klippy.Tests -- cast      # pairs and does what a phone does
dotnet run --project Klippy.Tests -- jitter    # replays synthetic arrival traces
```

Run it with no arguments for the flags. The WAVs it writes are IEEE float, so a
strictly-integer-PCM reader will refuse a perfectly good file.
