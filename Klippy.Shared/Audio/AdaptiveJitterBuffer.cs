namespace Klippy.Shared.Audio;

/// <summary>
/// Where the audio is going. It decides how deep the buffer needs to be, because the
/// output path already has buffering of its own that ours would only duplicate.
/// </summary>
public enum AudioRoute
{
    /// <summary>Phone speaker or wired headphones. Nothing downstream absorbs jitter, so ours must.</summary>
    Speaker,

    /// <summary>Classic Bluetooth. Android's own A2DP transmit buffer is 100-150 ms all by itself.</summary>
    BluetoothA2dp,

    /// <summary>LE Audio. Lower transmit buffering than A2DP, so ours has to carry a little more.</summary>
    BluetoothLe,
}

/// <summary>What the playback loop should do with this tick.</summary>
public enum JitterBufferAction
{
    /// <summary>A frame is ready. Play it.</summary>
    Play,

    /// <summary>Still filling. Play silence; do not treat it as a dropout.</summary>
    Buffering,

    /// <summary>The frame is not coming. Let the decoder conceal the gap and move on.</summary>
    Conceal,
}

/// <summary>One decision from the buffer, plus the payload when there is one.</summary>
public readonly record struct JitterBufferFrame(
    JitterBufferAction Action,
    uint Sequence,
    ReadOnlyMemory<byte> Payload);

/// <summary>
/// Holds arriving packets just long enough to play them in order at a steady rate, and
/// no longer.
///
/// This is where the latency number is actually won or lost. Home WiFi throws occasional
/// 30-50 ms spikes from retransmits and channel contention, so any *fixed* buffer smaller
/// than the worst spike is an audible dropout, and any fixed buffer larger than the
/// typical spike is latency paid on every single frame for an event that is rare. Hence
/// adaptive: track how bad the arrivals actually are and hold only that much.
///
/// <para>Time is injected rather than read from a clock so the whole thing can be driven
/// through synthetic jitter traces off-device. Given the plan calls this the
/// highest-risk component, being able to test it without a phone in the room is worth
/// more than keeping it next to its platform code.</para>
///
/// <para><b>What this is not.</b> Measured over 30 s traces, this reliably prevents
/// starvation — a fixed 10 ms buffer took 56-87 dropouts on the same spiky traces where
/// this took none — and it keeps the low floor on a clean network that a fixed 30 or
/// 80 ms buffer cannot. But <see cref="TargetMs"/> only gates the initial fill and the
/// refill after a starvation; it does not add depth to a stream already playing. So on
/// spiky traces this concealed the same 113 frames a fixed 30 ms buffer did, where only
/// a fixed 80 ms buffer caught them all, at 75 ms of latency on every frame forever.
/// Absorbing a spike mid-stream without a gap needs time-stretching, which is exactly
/// the part of WebRTC's NetEq the plan identifies as worth borrowing. This measurement
/// is the evidence for making that call, not a substitute for it.</para>
/// </summary>
public sealed class AdaptiveJitterBuffer
{
    /// <summary>
    /// How much of the measured worst case to actually hold. Above 1 because the peak we
    /// have seen is not the worst that exists.
    /// </summary>
    private const double SafetyFactor = 1.5;

    /// <summary>
    /// Per-tick decay on the peak estimate. At 200 ticks a second this forgets a spike
    /// over a couple of seconds, which is fast enough to give latency back after a bad
    /// patch and slow enough not to shrink straight back into the next one.
    /// </summary>
    private const double PeakDecay = 0.997;

    /// <summary>Give up on a head packet once this many later frames are already waiting.</summary>
    private const int ReorderTolerance = 3;

    private readonly Dictionary<uint, ReadOnlyMemory<byte>> _packets = [];
    private readonly int _minTargetMs;
    private readonly int _maxTargetMs;

    private double _peakDeviationMs;
    private long _firstArrivalMs;
    private uint _firstTimestampMs;
    private bool _seenAnything;
    private bool _playing;
    private uint _nextSequence;
    private int _consecutiveStarvations;

    public AdaptiveJitterBuffer(AudioRoute route)
    {
        Route = route;

        // The plan's two app-side wins, in numbers. On A2DP, Android's own 100-150 ms
        // transmit buffer sits downstream of us and already absorbs network jitter, which
        // makes most of ours redundant — shrinking to ~10-15 ms reclaims 20-35 ms at no
        // cost to quality.
        //
        // Worth stressing: this is reasoning about how Android layers its buffers, not a
        // documented guarantee. It needs measuring on a real device before it is believed.
        (_minTargetMs, _maxTargetMs) = route switch
        {
            AudioRoute.BluetoothA2dp => (10, 40),
            AudioRoute.BluetoothLe => (15, 50),
            _ => (25, 80),
        };

        TargetMs = _minTargetMs;
    }

    public AudioRoute Route { get; }

    /// <summary>How deep we are currently trying to hold, in milliseconds.</summary>
    public int TargetMs { get; private set; }

    /// <summary>How much playable audio is buffered right now.</summary>
    public int BufferedMs => _packets.Count * AudioCastFormat.FrameMilliseconds;

    public long FramesPlayed { get; private set; }

    /// <summary>Frames that never arrived, or arrived too late to use.</summary>
    public long FramesConcealed { get; private set; }

    /// <summary>Times the buffer ran dry mid-stream. The number to drive to zero.</summary>
    public long Starvations { get; private set; }

    /// <summary>Packets that arrived after their slot had already been played.</summary>
    public long ArrivedTooLate { get; private set; }

    public long Duplicates { get; private set; }

    /// <summary>Packets that arrived out of order but still in time to be used.</summary>
    public long Reordered { get; private set; }

    /// <summary>The worst arrival deviation seen, which is what the target is derived from.</summary>
    public double PeakDeviationMs => _peakDeviationMs;

    /// <summary>
    /// Takes a packet, whenever it turns up.
    ///
    /// <paramref name="arrivalMs"/> is a monotonic reading at the moment of arrival. The
    /// deviation between how far the stream's own clock has advanced and how far ours has
    /// is the jitter estimate — no round trips, no clock sync, just the two rates
    /// compared.
    /// </summary>
    public void Push(AudioCastPacketHeader header, ReadOnlyMemory<byte> payload, long arrivalMs)
    {
        if (!_seenAnything)
        {
            _seenAnything = true;
            _firstArrivalMs = arrivalMs;
            _firstTimestampMs = header.TimestampMs;
            _nextSequence = header.Sequence;
        }

        var streamElapsed = (long)(header.TimestampMs - _firstTimestampMs);
        var localElapsed = arrivalMs - _firstArrivalMs;
        var deviation = Math.Abs(localElapsed - streamElapsed);

        _peakDeviationMs = Math.Max(_peakDeviationMs, deviation);
        Retarget();

        // Already played past this slot: too late to be anything but a statistic.
        if (_playing && Compare(header.Sequence, _nextSequence) < 0)
        {
            ArrivedTooLate++;
            return;
        }

        if (!_packets.TryAdd(header.Sequence, payload))
        {
            Duplicates++;
            return;
        }

        if (_playing && Compare(header.Sequence, _nextSequence) > 0)
        {
            Reordered++;
        }
    }

    /// <summary>
    /// Asks what to do with the next playback slot. Called once per frame period by
    /// whatever is feeding the audio device.
    /// </summary>
    public JitterBufferFrame Next()
    {
        // Decay the peak a little every tick so a bad patch does not cost latency forever.
        _peakDeviationMs *= PeakDecay;
        Retarget();

        if (!_playing)
        {
            // Filling. Starting before the target is reached would only mean starving
            // immediately afterwards.
            if (!_seenAnything || BufferedMs < TargetMs)
            {
                return new JitterBufferFrame(JitterBufferAction.Buffering, 0, default);
            }

            _playing = true;
            _nextSequence = Oldest();
        }

        if (_packets.Remove(_nextSequence, out var payload))
        {
            var sequence = _nextSequence;
            _nextSequence++;
            FramesPlayed++;
            _consecutiveStarvations = 0;

            return new JitterBufferFrame(JitterBufferAction.Play, sequence, payload);
        }

        // The head is missing. If enough of its successors are already here, it is lost
        // rather than late, and waiting for it would cost more than concealing it.
        if (_packets.Count >= ReorderTolerance)
        {
            _nextSequence++;
            FramesConcealed++;
            _consecutiveStarvations = 0;

            return new JitterBufferFrame(JitterBufferAction.Conceal, 0, default);
        }

        // Nothing to play at all. Conceal to keep the device fed, and treat a run of
        // these as evidence the target is too low.
        Starvations++;
        FramesConcealed++;
        _consecutiveStarvations++;

        if (_consecutiveStarvations >= 2)
        {
            // React immediately rather than waiting for the estimate to catch up: a
            // dropout is far more expensive than a few milliseconds of latency.
            _peakDeviationMs = Math.Max(_peakDeviationMs, TargetMs + AudioCastFormat.FrameMilliseconds);
            Retarget();
            _playing = false;
            _consecutiveStarvations = 0;
        }
        else
        {
            _nextSequence++;
        }

        return new JitterBufferFrame(JitterBufferAction.Conceal, 0, default);
    }

    /// <summary>Called when the output route changes, e.g. headphones connecting mid-stream.</summary>
    public static AdaptiveJitterBuffer ForRoute(AudioRoute route) => new(route);

    private void Retarget() =>
        TargetMs = Math.Clamp(
            (int)Math.Ceiling(_peakDeviationMs * SafetyFactor),
            _minTargetMs,
            _maxTargetMs);

    private uint Oldest()
    {
        var oldest = uint.MaxValue;
        var first = true;

        foreach (var sequence in _packets.Keys)
        {
            if (first || Compare(sequence, oldest) < 0)
            {
                oldest = sequence;
                first = false;
            }
        }

        return oldest;
    }

    /// <summary>
    /// Compares sequence numbers the way they actually behave: unsigned and wrapping.
    /// Plain <c>&lt;</c> would invert every comparison for a few seconds when the counter
    /// rolls over, which at 200 a second is a real if distant event.
    /// </summary>
    private static int Compare(uint left, uint right) => Math.Sign((int)(left - right));
}
