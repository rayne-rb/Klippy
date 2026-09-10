using System.Buffers.Binary;

namespace Klippy.Shared.Audio;

/// <summary>
/// The fixed part of the cast format, shared by both ends so neither can drift.
///
/// 5 ms frames at 48 kHz is the whole latency argument in one line: the PC's sink
/// monitor is natively 48 kHz, so nothing resamples on capture, and 5 ms is short
/// enough that a lost frame is a gap CELT conceals rather than an audible hole.
/// Everything here is a compile-time constant because a mismatch between the two ends
/// is not a condition worth handling at runtime — it is a bug.
/// </summary>
public static class AudioCastFormat
{
    public const string Codec = "opus";

    public const int SampleRate = 48_000;

    public const int FrameMilliseconds = 5;

    /// <summary>240 at 48 kHz. This is the value Opus is handed as its frame size.</summary>
    public const int SamplesPerChannel = SampleRate / 1000 * FrameMilliseconds;

    public const int StereoBitrate = 128_000;

    public const int MonoBitrate = 64_000;

    /// <summary>Total float samples in one frame, both channels interleaved.</summary>
    public static int SampleCount(int channels) => SamplesPerChannel * channels;

    /// <summary>
    /// Bytes of float32 PCM in one frame — 1920 for stereo. Capture is configured so
    /// that one read off the pipe is exactly this, which is why nothing downstream
    /// needs a reframing buffer.
    /// </summary>
    public static int FrameBytes(int channels) => SampleCount(channels) * sizeof(float);

    public static int BitrateFor(int channels) => channels >= 2 ? StereoBitrate : MonoBitrate;

    public static bool IsSupportedChannelCount(int channels) => channels is 1 or 2;
}

/// <summary>How the media socket behaves. Both ends agree on this without negotiating it.</summary>
public static class AudioCastTransport
{
    /// <summary>
    /// A fixed default so a firewall rule can be written once. The port actually bound
    /// is still told to each listener in its offer, so an ephemeral fallback costs
    /// nothing if this one is taken.
    /// </summary>
    public const int DefaultUdpPort = 43117;

    /// <summary>128 bits of ephemeral, per-listener secret. Long enough that guessing is not a strategy.</summary>
    public const int StreamKeyBytes = 16;

    /// <summary>
    /// How often a listener repeats its hello. Also the mechanism that keeps the stream
    /// self-healing: the server takes the endpoint from whatever address the hello
    /// arrived from, so a phone that changes IP simply reappears.
    /// </summary>
    public static readonly TimeSpan HelloInterval = TimeSpan.FromSeconds(2);

    /// <summary>
    /// Silence longer than this and the listener is considered gone. Generous against
    /// the interval: dropping a live listener over one lost datagram would be worse
    /// than streaming a few seconds into the void.
    /// </summary>
    public static readonly TimeSpan HelloTimeout = TimeSpan.FromSeconds(8);
}

/// <summary>Sequence and timing for one encoded frame, as it appears on the wire.</summary>
public readonly record struct AudioCastPacketHeader(uint Sequence, uint TimestampMs);

/// <summary>
/// The binary datagram: an 8-byte header then one Opus packet.
///
/// Big-endian on purpose. It costs nothing here and it is the byte order anyone
/// debugging with a packet capture will expect, which matters more than saving a
/// byte swap on a 200-per-second path.
/// </summary>
public static class AudioCastPacket
{
    public const int HeaderBytes = 8;

    /// <summary>
    /// Comfortably inside a 1500-byte MTU with room for IP/UDP headers and any
    /// tunnelling in the way. A 128 kbps stereo frame is ~80 bytes, so this is only
    /// ever a guard against a pathological encoder result, never a normal limit.
    /// </summary>
    public const int MaxDatagramBytes = 1200;

    public static int MaxPayloadBytes => MaxDatagramBytes - HeaderBytes;

    /// <summary>Writes header plus payload, returning the datagram length.</summary>
    public static int Write(Span<byte> destination, AudioCastPacketHeader header, ReadOnlySpan<byte> payload)
    {
        if (destination.Length < HeaderBytes + payload.Length)
        {
            throw new ArgumentException("Destination is too small for the packet.", nameof(destination));
        }

        BinaryPrimitives.WriteUInt32BigEndian(destination, header.Sequence);
        BinaryPrimitives.WriteUInt32BigEndian(destination[4..], header.TimestampMs);
        payload.CopyTo(destination[HeaderBytes..]);

        return HeaderBytes + payload.Length;
    }

    /// <summary>
    /// Reads a datagram, returning false on anything malformed. Media arrives on an
    /// unauthenticated socket, so a short or empty datagram is an expected input, not
    /// an exceptional one.
    /// </summary>
    public static bool TryRead(
        ReadOnlySpan<byte> datagram,
        out AudioCastPacketHeader header,
        out ReadOnlySpan<byte> payload)
    {
        if (datagram.Length <= HeaderBytes)
        {
            header = default;
            payload = default;
            return false;
        }

        header = new AudioCastPacketHeader(
            BinaryPrimitives.ReadUInt32BigEndian(datagram),
            BinaryPrimitives.ReadUInt32BigEndian(datagram[4..]));
        payload = datagram[HeaderBytes..];

        return true;
    }
}
