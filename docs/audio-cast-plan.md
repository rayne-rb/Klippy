# Klippy AudioCast — implementation plan

Streaming the PC's **system audio** to Klippy.Mobile at the lowest achievable
latency, without sacrificing music quality.

Planned 2026-09-10. Nothing here is built yet.

**Benchmarked 2026-09-10.** Sections 5, 7 and 10 now carry *measured* numbers from
this machine, not estimates. Anything marked **measured** was run; the Bluetooth
ranges in section 9 are still literature estimates. See
[Settled by measurement](#settled-by-measurement--do-not-re-litigate).

**To resume this work:** point a Claude Code session at this file — it is written to
be self-contained. Start at [Build order](#build-order); every step is independently
verifiable.

---

## 1. Goal and constraints

Stream the full post-mix output of the PC (every application plus system sounds, not
per-application audio) to the phone, playable through the phone speaker, wired
headphones, or Bluetooth headphones.

**Requirements, as stated:**

| | |
|---|---|
| PC platforms | Linux **and** Windows |
| Latency | lowest achievable |
| Content | **music as well as voice** — quality must be preserved |
| Channels | stereo **and** mono |

**Explicitly ruled out:**

- **A USB Bluetooth dongle for the PC.** This would have been the lowest-latency
  option overall (~20–100 ms, no network hop, no phone, no double encode) and this
  machine has no Bluetooth adapter at all — but it is off the table. Do not
  re-propose it.
- **SCO/HFP "voice mode."** 16 kHz mono is phone-call quality, unacceptable for
  music. This costs nothing anyway: aptX LL (32–40 ms) and LC3 (20–40 ms) beat SCO's
  40–100 ms *and* are full-band stereo.
- **WebRTC as the primary transport.** On a single-hop LAN with no NAT,
  ICE/DTLS-SRTP/congestion-control/signalling is pure overhead. Retained only as the
  fallback if the adaptive jitter buffer underperforms — WebRTC's NetEq is the one
  piece genuinely worth borrowing, and **SIPSorcery** (pure C#, works both ends) is
  the way to get it without binding Google's native `.aar`.

---

## 2. Environment facts

Verified on this machine, 2026-09-10. Re-check if the box changes.

**Audio stack** — PipeWire 1.0.5 with pulse compat (`pipewire-pulse`), WirePlumber
0.4.17.

```
sink     alsa_output.pci-0000_0b_00.6.analog-stereo           s32le 2ch 48000Hz
monitor  alsa_output.pci-0000_0b_00.6.analog-stereo.monitor   s32le 2ch 48000Hz
```

The `.monitor` source **is** the system mix — no virtual sink or loopback config
needed. Natively 48 kHz, which matches Opus exactly: **zero resampling in the
capture chain.**

**Tooling present:** `parec`, `pw-record`, `pactl`, `pw-cli`.
**Tooling absent:** `ffmpeg`, `opusenc`, `sox`. Do not plan around them.

**Native libopus:** `libopus.so.0` → `libopus.so.0.9.0` is present (libopus 1.4,
package `libopus0`). The **unversioned `libopus.so` symlink is NOT** — it ships in
`libopus-dev`, which is not installed. This one missing symlink is why
`AttemptToUseNativeLibrary` silently no-ops; see section 5. `gcc` 13.3 present;
`clang`, `rustc`, `cmake` absent.

**Bluetooth:** no adapter. `/sys/class/bluetooth/` empty, nothing in `lspci`/`lsusb`,
`bluetooth.service` inactive. PipeWire nonetheless ships the full codec set
(`libspa-codec-bluez5-{sbc,aptx,ldac,lc3,faststream,opus}.so`, `libfreeaptx0`,
`libldacbt-enc2`) — irrelevant while the dongle is ruled out, but recorded in case
that changes.

**Packages** (both confirmed current on nuget.org):

| package | version | where |
|---|---|---|
| `Concentus` | 2.2.2 | Server + Mobile |
| `NAudio.Wasapi` | 3.1.0 | Server, **Windows-only at runtime** |

`Concentus.Native` 1.5.2 bundles the native binary. **Measured: take it, but for
allocation, not speed** — the pure-C# port is fast enough and the native path's real
value is that it allocates nothing. Section 5 has the numbers.

---

## 3. Architecture: media must not use the existing Link

The Link WebSocket is correct for state events and **wrong for a media stream**.
Four independent blockers in the current code:

| file | problem |
|---|---|
| `Klippy.Server/Features/Link/EventDispatcher.cs:27` | persists every non-ping envelope to Postgres — audio would write ~200 rows/sec into `link_events` forever |
| `Klippy.Server/Features/Link/LinkEndpoints.cs:13` | 64 KB message cap, and JSON+base64 inflates binary ~33% |
| `Klippy.Server/Features/Link/LinkConnection.cs:20,41` | 256-slot `DropOldest` channel — right for state events (a newer `pet.stats` supersedes an older one), destructive for a stream where the oldest packet is the one you need next |
| `Klippy.Server/Features/Link/LinkConnection.cs:75` | sends `WebSocketMessageType.Text` only |

**The split: control over the Link, media over UDP.**

Control gains persistence, auth and fan-out for free by staying on the Link. Add to
`Klippy.Shared/Link/KlippyEvents.cs`:

```
audio.cast.start    // phone → server: begin casting to me
audio.cast.stop     // phone → server: stop
audio.cast.state    // server → all: what is casting, to whom, which device
```

---

## 4. Transport and codec

### UDP, not TCP

A TCP retransmit stalls the stream to deliver data that is **already too late to
play**. You pay latency for a correction you cannot use. UDP lets a lost frame be
concealed and stepped past.

WebSocket is retained as a **fallback path** using the identical packet format —
useful for debugging and for networks that deprioritise UDP.

### Opus, and why (the reason is MTU, not bandwidth)

Raw PCM at 1.5 Mbps is only ~3% of the WiFi, so bandwidth was never the constraint.
The problem is **fragmentation**: a raw stereo frame exceeds the 1500-byte MTU, so
losing either IP fragment loses the whole frame. Opus fits a frame in ~120 bytes —
one datagram, never fragmented, one loss event costs exactly one frame.

### Packet format

First message is text JSON (format negotiation: codec, rate, channels, frame
duration, device name). Then binary datagrams:

| bytes | field | purpose |
|---|---|---|
| 0–3 | `u32 sequence` | gap/loss detection |
| 4–7 | `u32 timestampMs` | jitter buffer + drift correction |
| 8+ | payload | Opus packet |

### Auth on UDP

1. Phone sends `audio.cast.start` over the already-authenticated Link.
2. Server replies with an **ephemeral 16-byte stream key**.
3. Phone's UDP hello carries that key; the server learns its endpoint from the
   packet source address.

No NAT config, and it self-heals when the phone's IP changes. Media itself is
unencrypted — a deliberate LAN-only call, consistent with the no-HTTPS decision at
`Klippy.Server/Program.cs:36`.

---

## 5. Opus configuration

Every setting below was **verified present in the Concentus 2.2.2 assembly**.

```
Application         = OPUS_APPLICATION_RESTRICTED_LOWDELAY
ExpertFrameDuration = OPUS_FRAMESIZE_5_MS
Bitrate             = 128000 stereo / 64000 mono
SignalType          = OPUS_SIGNAL_MUSIC     // OPUS_SIGNAL_VOICE for Klippy speech
MaxBandwidth        = OPUS_BANDWIDTH_FULLBAND
Complexity          = 10
UseVBR              = true
ForceChannels       = <negotiated>
AttemptToUseNativeLibrary = true    // necessary but NOT sufficient - see below
```

**`RESTRICTED_LOWDELAY` is both the fastest and the music-optimal mode.** It forces
CELT-only operation, and CELT *is* Opus's music layer (SILK is the speech layer).
Lookahead drops 6.5 ms → ~2.5 ms. Nothing is lost for music.

**Use the float API.** `opus_encode_float` / `opus_decode_float` are present.
Capture `float32le` on both platforms — WASAPI loopback is *natively* float32, so
this **simplifies** the Windows path rather than complicating it, and removes an
int16 round-trip.

### Managed vs native — measured, and the flag is a trap

> **`AttemptToUseNativeLibrary = true` silently does nothing on this box.** It probes
> for **unversioned `libopus.so`**, which is not installed (section 2). With the flag
> `true` the implementation, version string, speed and allocation are *identical* to
> `false`. It fails **silently**: the probe log is visible only if you pass the
> optional `messageLogger` argument to `OpusCodecFactory.CreateEncoder`.
>
> **So: always pass a `messageLogger` and assert on it at startup.** A cast that
> quietly runs 3x slower and allocates 9.6 MB/s because a symlink is missing is
> exactly the bug you will not find by reading code.

Get the native path deliberately — `Concentus.Native`, or `libopus-dev` for the
symlink, or ~6 `DllImport` lines against `libopus.so.0`. Then verify it loaded.

**Measured** — 5 ms stereo frame, 48 kHz, complexity 10, `RESTRICTED_LOWDELAY`,
20k frames, this machine:

| path | mean | p99 | max | % of 5 ms frame | alloc / frame |
|---|---|---|---|---|---|
| encode, C# | 0.049 ms | 0.069 | 0.284 | 1.0% | **49,420 B** |
| encode, native | 0.029 ms | 0.043 | 0.091 | 0.6% | 0 B |
| decode, C# | 0.022 ms | 0.054 | 0.159 | 0.44% | 9,500 B |
| decode, native | 0.007 ms | 0.011 | 0.029 | 0.15% | 0 B |

**CPU time is not the reason.** Native saves ~0.035 ms across encode+decode against a
45–340 ms end-to-end budget. Even the worst C# spike is 5.7% of one frame. A phone is
~2–4x slower and C# decode still sits under 2% of the frame.

**Allocation is the reason.** Managed encode churns **9.6 MB/s** at 200 frames/sec
(60 gen0 collections per 100 s of audio); managed decode **1.9 MB/s**. A gen0 pause in
a real-time audio path is a dropout, it does not improve with a faster CPU, and the
decode side runs on the phone — so this is a mobile concern first.

**Output is bit-identical either way:** both paths emitted 81.0 B packets, 130 kbps
actual, lookahead 120 samples (2.50 ms) — confirming the 2.5 ms figure above. Same
codec, same bitstream. Quality is set by bitrate/bandwidth and then capped by the
Bluetooth codec (section 9); the encoder implementation cannot move it.

### The one trade this creates

`RESTRICTED_LOWDELAY` disables SILK, so **Opus in-band FEC (LBRR) is unavailable**.
At 5 ms frames a loss is a 5 ms gap that CELT's concealment makes essentially
inaudible, and LAN loss should be near zero. If measurement shows real loss, **send
duplicate packets** (128 kbps of spare LAN bandwidth) rather than switching modes and
paying the lookahead back.

### Stereo/mono

Negotiated in the hello via `ForceChannels`, switchable mid-stream.

> **Mono does not reduce latency.** Latency is frame duration plus buffer depth;
> channel count only affects bitrate. Mono is a *bandwidth* knob — weak WiFi,
> single-earbud use, or genuinely mono source material. Do not present it as a
> low-latency mode.

---

## 6. Slice layout

Follows the established feature-slice convention — see the existing
`Features/{Pairing,Link,Discovery,PetState}` for the pattern
(`XRegistration.AddXFeature()`, `XEndpoints.MapXEndpoints()`, wired in `Program.cs`).

```
Klippy.Server/Features/AudioCast/
  AudioCastRegistration.cs     AddAudioCastFeature()
  AudioCastEndpoints.cs        /api/audio/{devices,stream}  (+ WS fallback)
  AudioBroadcaster.cs          singleton: ref-counted capture -> N subscribers
  AudioCastUdpServer.cs        binds UDP, learns endpoints from hello, streams back
  AudioCastEventHandler.cs     IKlippyEventHandler for audio.cast.*
  IAudioCaptureSource.cs       the OS seam
  ParecCaptureSource.cs        Linux
  WasapiCaptureSource.cs       Windows
  OpusEncoderPool.cs           Concentus, config as section 5
  AudioSourceCatalog.cs        enumerate outputs per platform

Klippy.Shared/Audio/
  AudioStreamContracts.cs      packet header, format negotiation, hello payloads
Klippy.Shared/Link/KlippyEvents.cs
  + audio.cast.{start,stop,state}

Klippy.Mobile/Features/AudioCast/
  AudioCastClient.cs                   UDP socket + keepalive
  AdaptiveJitterBuffer.cs              <- the hard part
  OpusStreamDecoder.cs                 Concentus
  IAudioSink.cs
  Platforms/Android/AudioTrackSink.cs
```

**No DB migration.** Cast state stays in memory, like `PetStateStore`. Add
`db/up/0004_audio_cast.sql` only if the device choice should survive a restart.

**Capture is shared and ref-counted** — one `parec`/WASAPI instance fanned out to N
subscribers, started on first subscriber, stopped on last with a short linger so a
reconnect does not respawn it.

---

## 7. Capture

### Linux

```bash
parec --device=alsa_output.pci-0000_0b_00.6.analog-stereo.monitor \
      --format=float32le --rate=48000 --channels=2 --latency-msec=5
```

Read stdout in fixed-size frames. Speaks the PulseAudio API, so it works on real
PulseAudio too. Enumerate candidates with `pactl list short sinks` and append
`.monitor`.

**`--latency-msec=5`, not 10 — this is the single largest win in the whole plan, and
it is one number.** Measured delivery on this machine (4 s per run, 0.5 s warm-up
discarded, tone playing):

| setting | chunk delivered | p99 inter-arrival | |
|---|---|---|---|
| `=1` or `=2` | 2.67 ms (128 smp) | 2.70 ms | the floor |
| `=3` | 3.00 ms | **5.36 ms** | *irregular* — bursty, see below |
| **`=5`** | **5.00 ms** | **5.37 ms** | **exactly one Opus frame** |
| `=10` | 10.00 ms | 10.75 ms | what this plan originally said |
| `pw-record` | 10.67 ms | 10.70 ms | ignored the latency hint entirely |

**Why 5 and not the 2.67 ms floor:** capture latency cannot go below the Opus frame
duration, because you cannot encode until you hold 5 ms of audio. At `=5` one read is
exactly one 240-sample frame — **no reframing ring buffer at all.** Dropping to
2.67 ms chunks buys no real latency and forces you to reassemble 128-sample chunks
into 240-sample frames.

**Do not use `=3`.** Its delivery is *irregular*: p50 gap 2.67 ms but p99 5.36 ms — a
2.7 ms spread, arriving in bursts. `=5` by contrast is metronomic (p50 5.33, p99 5.37,
a 0.04 ms spread). 3 ms straddles a quantum boundary — `clock.power-of-two-quantum =
true` on this stack — so you pay bursty arrival and a 1.7x higher read rate to gain
nothing, since a frame still cannot be encoded before 5 ms of audio exists.

> **`pw-record` is the worse path, not the escape hatch.** It **ignored**
> `PIPEWIRE_LATENCY` completely: `32/48000` and `128/48000` both delivered identical
> 10.67 ms chunks. PipeWire's `clock.min-quantum` is 32 samples (0.67 ms) and
> `quantum-floor` is 4, but `pw-record` will not ask for it. Direct libpipewire remains
> a *theoretical* escape hatch below 5 ms — but per the paragraph above there is
> nothing to win there while frames are 5 ms.

**Caveat:** read granularity is a *proxy* for true buffer depth. The click test under
[How to measure](#how-to-measure--do-this-rather-than-trusting-the-ranges-above)
is still the only authority on end-to-end latency.

### Windows

`WasapiLoopbackCapture` from `NAudio.Wasapi`, on the render endpoint — same full
system mix as the PipeWire monitor.

> **Gotcha: WASAPI loopback goes silent, not idle.** It delivers *no callbacks at
> all* when nothing is playing — it does not hand you zeros. Without injecting
> silence the stream stalls and the phone's buffer starves the moment music is
> paused. This is the single most likely Windows bug.

`NAudio.Wasapi` is Windows-only at runtime: use a conditional `PackageReference`
plus a runtime probe so the Linux build stays clean.

---

## 8. Android playback

- **`AudioTrack`, `MODE_STREAM`**, `AudioUsageKind.Media` + `AudioContentType.Music`.
  This routes to whatever output the OS considers active — **Bluetooth needs zero
  extra code**, speaker vs BT is an OS-level choice.
- **Buffer must be exactly `getMinBufferSize()`.** A "safe" multiple silently costs
  40+ ms.
- **Match the device's native sample rate.** Query
  `AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`. Feeding 48 kHz to a 44.1 kHz device
  inserts a resampler in the path. Opus only runs at 8/12/16/24/48 kHz, so a
  44.1 kHz device needs a post-decode resample; modern Android is 48 kHz.
- **`AudioTrack.GetTimestamp()`** is the supported way to learn actual playout
  position — build the adaptive buffer on it. `getOutputLatency()` is hidden and
  unstable; do not use it.
- **`PerformanceMode.LowLatency` does NOTHING on A2DP.** Bluetooth output does not
  use the fast-mixer path. Set it anyway for speaker/wired, but do not budget for it
  on the BT path.

### Two things that will otherwise bite

1. **Foreground service** — `foregroundServiceType="mediaPlayback"`,
   `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`. Without these,
   playback dies seconds after the screen locks.
2. **Cleartext HTTP** — Android 9+ blocks it. Needs `usesCleartextTraffic` or a
   LAN-scoped network security config. Applies to the existing pairing/Link work
   too, not just audio.

---

## 9. Bluetooth reality

**Where the 150–250 ms goes** — the two dominant terms are buffers, and neither is
reachable from an app:

| stage | ms | ours? |
|---|---|---|
| phone-side codec encode | 10–40 | no |
| **Android A2DP transmit buffer** | 100–150 | no |
| radio transit | 5–10 | no |
| **headphone jitter buffer** (firmware) | 20–100 | no |
| headphone decode | 5–20 | no |

**Key insight: for Bluetooth, quality and latency mostly align.** SBC is
simultaneously the worst quality and near-worst latency. **LDAC is the only real
trade.**

| codec | quality | latency |
|---|---|---|
| LC3 (LE Audio) | better than SBC at half the bitrate | **20–40** |
| aptX LL | CD-ish | **32–40** |
| aptX Adaptive | very good | 50–80 |
| aptX | CD-ish | 70–100 |
| aptX HD | 24-bit/48k, excellent | 100–130 |
| AAC | decent (poor encoder on Android) | 150–250 |
| SBC | mediocre — artifacts on cymbals/highs | 150–250 |
| **LDAC** | best raw at 990 kbps | **200–300** |

**The phone's codec setting outweighs everything in our code combined.** We cannot
set it — `BluetoothA2dp.setCodecConfigPreference()` is `@SystemApi` behind
`BLUETOOTH_PRIVILEGED`. So build a **warning** that reads the active codec and flags
a slow one, not a codec picker.

### Our two app-side wins

1. **Shrink the jitter buffer to ~10–15 ms when the route is Bluetooth.** Android's
   own 100–150 ms A2DP buffer already absorbs network jitter downstream of
   `AudioTrack`, making our full 30–50 ms largely redundant. Reclaims 20–35 ms,
   quality-neutral. Detect via `AudioManager.GetDevices()` for
   `TYPE_BLUETOOTH_A2DP`; re-tune on route change via `AudioDeviceCallback`.
   > **Verify this empirically.** It is reasoning about how Android layers its
   > buffers, not a documented guarantee.
2. **5 ms frames + CELT-only** (section 5).

---

## 10. Latency budget

Our pipeline: **~27–40 ms** on Bluetooth (5 ms capture + 5 ms frames +
`RESTRICTED_LOWDELAY` + BT-aware buffer shrink), **~47–75 ms** on speaker/wired where
the full buffer is needed.

Every row below is **5 ms lower than this plan's first draft**, entirely from the
`--latency-msec=10` → `5` capture change in section 7. Codec CPU contributes ~0.07 ms
and is not a line item.

| output | total ms |
|---|---|
| BT, LC3 / LE Audio | **45–80** |
| BT, aptX LL | 60–80 |
| phone speaker or wired | 47–75 |
| BT, aptX | 95–140 |
| BT, aptX HD | 125–170 |
| BT, SBC / AAC | 175–290 |
| BT, LDAC | 225–340 |

Full stereo, 128 kbps Opus, 48 kHz, fullband — **no quality compromise anywhere in
that table.**

**WiFi jitter is the real wall.** Home WiFi throws occasional 30–50 ms spikes from
retransmits and channel contention. Any *fixed* buffer smaller than the worst spike
is an audible dropout — hence the buffer must be adaptive.

---

## Build order

**Built 2026-09-10 on `feature/audio-cast`.** All seven steps are implemented. Steps 1,
3, 4, 6 and 7 are verified by measurement on this machine; steps 2 (Windows) and 5
(Android) are compile-verified only, because there is no Windows box and no phone
attached here. See [Status](#status--what-is-verified-and-what-is-not).


Each step is independently verifiable. This matters because every failure mode here
is timing-related and miserable to debug in aggregate.

- [x] **1. `IAudioCaptureSource` + `ParecCaptureSource`** → write float32 to a `.wav`
      on disk. Proves system-audio capture in isolation. *Independent of every
      Bluetooth question.* Use **`--latency-msec=5`** (section 7) — one read is then
      exactly one 240-sample Opus frame, so no reframing buffer is needed anywhere
      downstream. Assert the read size is 1920 B.
- [x] **2. `WasapiCaptureSource`** behind the same interface, **including the
      silence-injection fix** (section 7).
- [x] **3. `AudioBroadcaster` + `OpusEncoderPool`** with a **desktop .NET test
      client** that decodes and plays. Takes the phone out of the equation entirely.
      **Pass a `messageLogger` to `CreateEncoder`/`CreateDecoder` and fail loudly if
      the native library did not load** (section 5) — otherwise a missing symlink
      silently costs you 9.6 MB/s of allocation. Log allocated-bytes-per-frame here;
      it should be ~0, not ~49,420.
- [x] **4. `AudioCastUdpServer`** + `audio.cast.*` control events over the Link +
      ephemeral stream-key auth.
- [x] **5. Android `AudioTrackSink`** with a deliberately **fat fixed buffer**. Get
      sound out of the phone before optimising anything.
- [x] **6. `AdaptiveJitterBuffer`** replacing the fixed buffer, built on
      `GetTimestamp()`, with the BT-aware shrink. **This is where the latency number
      is actually won, and it is the highest-risk component.**
- [x] **7. Blazor config page** — pick output device, see connected listeners, toggle
      cast, warn on a slow BT codec.

---

## Status — what is verified and what is not

Implemented on `feature/audio-cast`, 0 warnings across the solution.

| step | state | how far it has been proven |
|---|---|---|
| 1 capture (Linux) | **verified** | 600 frames, byte-exact, p99 gap 5.38 ms, every frame in a single read |
| 2 capture (Windows) | **compile only** | no Windows machine here; silence injection is the part most likely wrong |
| 3 broadcast + encode | **verified** | 2 listeners on 1 capture, 81 B packets, 120 B worst datagram, 0.97 round-trip correlation |
| 4 UDP + control + auth | **verified** | 2400 datagrams over 12 s, 0 lost, 0 malformed, p99 arrival 5.47 ms |
| 5 Android sink | **compile only** | no device attached; buffer sizing and route mapping are the parts to distrust |
| 6 jitter buffer | **verified in simulation** | rode out 4 synthetic traces with no starvation where a fixed 10 ms buffer took 56-87 |
| 7 Blazor page | **verified** | renders, lists outputs, shows a live listener mid-cast |

**Still open, in the order it matters:**

1. **Run it to a real phone.** Steps 2 and 5 have never executed. Everything between
   them is measured, which means the remaining unknowns are concentrated at the two ends.
2. **Do the click test.** Every latency figure here is a component measurement. The
   end-to-end number is still the one in
   [How to measure](#how-to-measure--do-this-rather-than-trusting-the-ranges-above),
   and nothing above substitutes for it.
3. **Decide on NetEq.** The jitter buffer adapts its *initial* depth and recovers from
   starvation, but does not add depth to a stream already playing — so it conceals the
   same frames a fixed 30 ms buffer would. Closing that needs time-stretching. The
   measurement to justify the decision now exists.
4. **Install `libopus-dev` or add `Concentus.Native`.** The managed path allocates
   11.3 MB/s while casting. It is fast enough, but a 15.65 ms mid-stream arrival gap was
   observed at 12 s, which is what a collection in the audio path looks like.
5. **Windows 44.1 kHz endpoints** are detected and refused rather than resampled.
6. **The BT codec warning** needs the phone: only it can read the active codec.

---

## Settled by measurement — do not re-litigate

**Would another language + a wrapper cut latency or raise quality?** Benchmarked
2026-09-10 against native `libopus.so.0` via P/Invoke: **no, on both counts.**

- **Latency:** native saves ~0.035 ms across encode+decode. The budget is *buffers* —
  capture, jitter buffer, Android's A2DP buffer, headphone firmware — and codec CPU is
  0.4% of one frame. There is nothing there to win.
- **Quality:** output was **bit-identical** (81.0 B packets, 130 kbps, 120-sample
  lookahead on both paths). Same codec, same bitstream spec. A language cannot improve
  Opus at a fixed bitrate; the knobs are bitrate/bandwidth, and the ceiling is the
  Bluetooth codec.
- **To actually raise quality**, raise the bitrate — 128k → 256k stereo costs ~0 ms
  (bandwidth is ~3% of the WiFi). But on a Bluetooth output A2DP re-encodes to
  SBC/AAC/LDAC downstream, so LAN-side quality above the BT codec's ceiling is
  discarded. Worth it only for speaker/wired.
- **Cost if built anyway:** cross-compiling libopus for arm64-v8a / armeabi-v7a /
  x86_64 plus win-x64 and linux-x64, two toolchains, marshalling, and debugging across
  the managed/native boundary — to reimplement what `Concentus.Native` ships.

The one legitimate finding was **allocation, not language** (section 5), and it is
fixed by a native binding, not a rewrite.

---

## Open questions

1. **Which codecs do the target headphones actually support?** This is the difference
   between 45 ms and 290 ms, and it decides whether step 6's BT-aware shrink is even
   worth building — if the link is stuck on SBC, our 25 ms saving is noise against
   their 250 ms. **Check Developer Options → Bluetooth Audio Codec.**
2. **Do the phone and headphones both support LE Audio?** (Android 13+, Pixel 7+ /
   Galaxy S23+ class.) That is the 45–80 ms row *and* the best quality on the list.
3. **Does the BT-aware buffer shrink actually work?** Hypothesis, not fact. Measure.

### How to measure — do this rather than trusting the ranges above

Play a sharp click on the PC. Record the PC speaker and the headphone cup on one mic
simultaneously. Measure the offset in Audacity. Ten minutes per codec, and you are
tuning against real numbers instead of estimates.

---

## Appendix: useful commands

```bash
# Enumerate sinks; append .monitor for the loopback source
pactl list short sinks
pactl get-default-sink

# Capture system audio to a file (step 1 sanity check)
parec --device="$(pactl get-default-sink).monitor" \
      --format=float32le --rate=48000 --channels=2 --latency-msec=5 \
      --file-format=wav /tmp/systemaudio.wav

# Confirm the monitor source exists and is not SUSPENDED while audio plays
pactl list short sources

# Check native libopus: .so.0 is present but the UNVERSIONED symlink is what
# Concentus probes for. If the second line prints nothing, the flag will no-op.
ls /lib/x86_64-linux-gnu/libopus.so.0
ls /lib/x86_64-linux-gnu/libopus.so 2>/dev/null || echo "MISSING -> AttemptToUseNativeLibrary will silently fall back"

# PipeWire quantum limits (the theoretical capture floor)
pw-metadata -n settings | grep -E "quantum|rate"
```

**Reproducing the capture-latency table in section 7.** The monitor source is IDLE
with nothing playing, so a tone must be running or every path measures nothing:

```bash
# keep audio flowing in another shell
paplay /path/to/tone.wav

# then compare settings - reports chunk size and inter-arrival jitter
for L in 1 3 5 10; do
  echo "=== --latency-msec=$L ==="
  parec --device="$(pactl get-default-sink).monitor" --format=float32le \
        --rate=48000 --channels=2 --latency-msec=$L | python3 reader.py
done
```

`reader.py` timestamps each `os.read`, discards a 0.5 s warm-up, and reports mean /
p50 / p99 of both chunk size and inter-arrival gap. At 48 kHz float32 stereo the
conversion is **384 B per ms**; a 5 ms Opus frame is **1920 B**.

The capture command above is **verified working** on this machine (2026-09-10) — the
byte-count check below was run at `--latency-msec=10`, which changes read granularity
only, not the captured data: 4 s
of playback produced a 1,516,888-byte file — valid RIFF/WAVE, format tag 3, 2 ch,
48000 Hz, 32-bit, 3.95 s. That matches `48000 x 2ch x 4B` exactly.

> **Verification trap for step 1.** A float32 WAV carries `wFormatTag = 3`
> (`WAVE_FORMAT_IEEE_FLOAT`), and tools that only read integer PCM reject it —
> Python's stdlib `wave` module raises `wave.Error: unknown format: 3`. **The file is
> fine.** Do not conclude capture is broken. Check the header directly instead:

```python
import struct, os
p = '/tmp/systemaudio.wav'
d = open(p, 'rb').read(60)
f = d.index(b'fmt ')
tag, ch, rate, _, _, bits = struct.unpack('<HHIIHH', d[f+8:f+24])
print(f"tag={tag} (3=IEEE float) channels={ch} rate={rate} bits={bits}")
sz = os.path.getsize(p)
print(f"{sz/(rate*ch*bits//8):.2f}s")
```

To listen to it, use a float-aware player (`pw-play`, `paplay`, VLC, Audacity)
rather than a minimal PCM-only one.
