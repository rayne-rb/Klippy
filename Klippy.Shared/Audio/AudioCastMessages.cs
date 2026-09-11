namespace Klippy.Shared.Audio;

/// <summary>
/// One selectable thing to capture from. On Linux these are PulseAudio/PipeWire sink
/// monitors; on Windows, WASAPI render endpoints. The id is whatever the platform
/// needs to open it, and is meaningless to the phone beyond echoing it back.
/// </summary>
public sealed record AudioOutputDevice
{
    public required string Id { get; init; }

    public required string Name { get; init; }

    /// <summary>True for the platform's current default output.</summary>
    public required bool IsDefault { get; init; }
}

/// <summary>
/// What the stream is, told to a listener before any audio arrives.
///
/// This travels over the Link rather than as a first UDP datagram. The plan's §4
/// called for a leading text datagram, but negotiation on an unreliable transport
/// means a lost first packet leaves the listener unable to interpret anything that
/// follows. The Link is already authenticated, ordered and reliable, so the same
/// split the plan argues for elsewhere — control over the Link, bytes over UDP —
/// applies to negotiation too. The WebSocket fallback does lead with this as text,
/// where framing makes it free.
/// </summary>
public sealed record AudioCastStreamFormat
{
    public string Codec { get; init; } = AudioCastFormat.Codec;

    public int SampleRate { get; init; } = AudioCastFormat.SampleRate;

    public required int Channels { get; init; }

    public int FrameMilliseconds { get; init; } = AudioCastFormat.FrameMilliseconds;

    /// <summary>Human-readable name of what is being captured, for the phone's UI.</summary>
    public required string SourceName { get; init; }
}

/// <summary>
/// Phone to server: start casting to me. Sent over the authenticated Link.
/// </summary>
public sealed record AudioCastStartPayload
{
    /// <summary>Which output to capture. Null takes the platform default.</summary>
    public string? DeviceId { get; init; }

    /// <summary>
    /// 1 or 2. Mono halves the bitrate and nothing else — it is not a latency knob,
    /// so it belongs to weak WiFi and single-earbud listening, not to "make it faster".
    /// </summary>
    public int Channels { get; init; } = 2;
}

/// <summary>
/// Server to one listener, targeted: where to send the hello and how to prove it.
///
/// The key is ephemeral and per-listener, which is what keeps an unauthenticated UDP
/// port from being an open relay. It is deliberately never broadcast — this payload
/// only ever travels on an envelope with a Target set.
/// </summary>
public sealed record AudioCastOfferPayload
{
    public required int UdpPort { get; init; }

    /// <summary>Base64 of 16 random bytes. Valid until the cast stops.</summary>
    public required string StreamKey { get; init; }

    public required AudioCastStreamFormat Format { get; init; }
}

/// <summary>Who is listening right now, for the dashboard and for other devices.</summary>
public sealed record AudioCastListener
{
    public required string DeviceId { get; init; }

    public required string DeviceName { get; init; }

    /// <summary>False until the first UDP hello arrives — offered but not yet streaming.</summary>
    public required bool IsReceiving { get; init; }

    public required int Channels { get; init; }
}

/// <summary>
/// Server to everyone: what is casting, from where, to whom. Carries no key.
/// </summary>
public sealed record AudioCastStatePayload
{
    public required bool IsCasting { get; init; }

    /// <summary>The output being captured, or null when nothing is.</summary>
    public string? DeviceId { get; init; }

    public string? DeviceName { get; init; }

    public required IReadOnlyList<AudioCastListener> Listeners { get; init; }
}

/// <summary>
/// The only thing a listener sends over UDP: its key, repeated as a keepalive.
///
/// Repeating it is what makes the stream self-healing. The server learns the endpoint
/// from the datagram's source address, so a phone that changes IP or comes back
/// through a different NAT mapping simply reappears at the new address on its next
/// hello, with no reconnect handshake.
/// </summary>
public sealed record AudioCastHello
{
    public required string StreamKey { get; init; }
}
