using System.Collections.Concurrent;
using System.Diagnostics;
using Concentus;
using Concentus.Enums;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>What the codec actually resolved to at startup, measured rather than assumed.</summary>
public sealed record OpusCodecDiagnostics
{
    public required string Version { get; init; }

    /// <summary>Whether native libopus was loaded, from the probe log where it says so.</summary>
    public required bool NativeLibraryLoaded { get; init; }

    /// <summary>
    /// Measured bytes allocated per encoded frame. This is the number that matters:
    /// ~0 on the native path, ~49,000 on the pure-C# one.
    /// </summary>
    public required long AllocatedBytesPerFrame { get; init; }

    /// <summary>
    /// Encode time per frame as sampled at startup. This is a <b>cold</b> number: with
    /// only a few hundred calls behind it, tiered JIT has not finished with Concentus
    /// yet, so it reads roughly 6x slower than steady state (measured: 0.315 ms cold
    /// against 0.050 ms warm). Warming it properly would cost half a second of startup
    /// to measure something the plan already settled, so it stays cold and labelled.
    /// </summary>
    public required double ColdEncodeMillisecondsPerFrame { get; init; }

    /// <summary>Concentus's own probe trail. The only place a failed native load is visible.</summary>
    public required string ProbeLog { get; init; }

    public long AllocatedBytesPerSecond =>
        AllocatedBytesPerFrame * 1000 / AudioCastFormat.FrameMilliseconds;
}

/// <summary>
/// Hands out configured Opus encoders, and settles at startup which codec path we are
/// actually on.
///
/// Encoders are stateful and reused rather than rebuilt per listener: one per channel
/// count, reset on return. The broadcaster encodes a frame once and fans the same bytes
/// out to every listener on that configuration, so this is only ever a small pool.
/// </summary>
public sealed class OpusEncoderPool
{
    /// <summary>
    /// Above this, we are demonstrably on the managed path. The two outcomes are ~0 and
    /// ~49,000 bytes per frame, so anywhere in between is a comfortable place to draw
    /// the line.
    /// </summary>
    private const long NativePathAllocationCeiling = 1024;

    private readonly ConcurrentDictionary<int, ConcurrentBag<IOpusEncoder>> _byChannels = new();
    private readonly ILogger<OpusEncoderPool> _logger;

    public OpusEncoderPool(ILogger<OpusEncoderPool> logger)
    {
        _logger = logger;

        // Transparently uses native libopus when it can find one. On its own this is
        // not enough to know whether it did — hence the probe below.
        OpusCodecFactory.AttemptToUseNativeLibrary = true;

        Diagnostics = Probe();
        Report(Diagnostics);
    }

    public OpusCodecDiagnostics Diagnostics { get; }

    /// <summary>Takes an encoder for the given channel count, configured and with clean state.</summary>
    public IOpusEncoder Rent(int channels)
    {
        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            throw new ArgumentOutOfRangeException(nameof(channels), channels, "Only mono and stereo are supported.");
        }

        if (_byChannels.TryGetValue(channels, out var bag) && bag.TryTake(out var pooled))
        {
            pooled.ResetState();
            return pooled;
        }

        return Configure(OpusCodecFactory.CreateEncoder(
            AudioCastFormat.SampleRate, channels, OpusApplication.OPUS_APPLICATION_RESTRICTED_LOWDELAY), channels);
    }

    public void Return(IOpusEncoder encoder) =>
        _byChannels.GetOrAdd(encoder.NumChannels, _ => []).Add(encoder);

    /// <summary>
    /// The plan's §5 configuration, in one place.
    ///
    /// RESTRICTED_LOWDELAY is both the fastest and the music-optimal choice: it forces
    /// CELT-only operation, and CELT *is* Opus's music layer, which drops lookahead from
    /// 6.5 ms to the 2.5 ms measured here. The cost is that SILK goes away with it, so
    /// in-band FEC is unavailable — at 5 ms a loss is a gap CELT conceals, and if real
    /// loss ever shows up the answer is duplicate packets, not switching modes and
    /// paying the lookahead back.
    /// </summary>
    private static IOpusEncoder Configure(IOpusEncoder encoder, int channels)
    {
        encoder.Bitrate = AudioCastFormat.BitrateFor(channels);
        encoder.SignalType = OpusSignal.OPUS_SIGNAL_MUSIC;
        encoder.MaxBandwidth = OpusBandwidth.OPUS_BANDWIDTH_FULLBAND;
        encoder.Complexity = 10;
        encoder.UseVBR = true;
        encoder.ExpertFrameDuration = OpusFramesize.OPUS_FRAMESIZE_5_MS;
        encoder.ForceChannels = channels;

        return encoder;
    }

    /// <summary>
    /// Encodes throwaway frames to find out what we are running on.
    ///
    /// Deliberately cheap. Allocation and the native/managed verdict are what this is
    /// for, and both are accurate at any JIT tier; the timing it also happens to
    /// produce is cold, and labelled as such.
    ///
    /// The flag is a trap worth guarding against: pointed at a machine with only
    /// <c>libopus.so.0</c> and no unversioned <c>libopus.so</c>, Concentus probes,
    /// fails, and falls back to the managed port in complete silence. The probe log is
    /// the only place that is visible, and it only exists if a messageLogger is passed.
    /// Allocation is measured as well, because that is the ground truth and the reason
    /// the native path is worth having at all.
    /// </summary>
    private static OpusCodecDiagnostics Probe()
    {
        const int warmup = 200;
        const int measured = 400;
        const int channels = 2;

        var probeLog = new StringWriter();
        using var encoder = Configure(
            OpusCodecFactory.CreateEncoder(
                AudioCastFormat.SampleRate,
                channels,
                OpusApplication.OPUS_APPLICATION_RESTRICTED_LOWDELAY,
                probeLog),
            channels);

        var pcm = SyntheticFrame(channels);
        var packet = new byte[AudioCastPacket.MaxPayloadBytes];

        for (var i = 0; i < warmup; i++)
        {
            encoder.Encode(pcm, AudioCastFormat.SamplesPerChannel, packet, packet.Length);
        }

        var before = GC.GetTotalAllocatedBytes(precise: true);
        var clock = Stopwatch.StartNew();

        for (var i = 0; i < measured; i++)
        {
            encoder.Encode(pcm, AudioCastFormat.SamplesPerChannel, packet, packet.Length);
        }

        clock.Stop();
        var allocated = GC.GetTotalAllocatedBytes(precise: true) - before;
        var perFrame = allocated / measured;

        var text = probeLog.ToString();
        var reported = text.Contains("Is native opus available? True", StringComparison.OrdinalIgnoreCase)
            ? true
            : text.Contains("Is native opus available? False", StringComparison.OrdinalIgnoreCase)
                ? false
                : (bool?)null;

        return new OpusCodecDiagnostics
        {
            Version = encoder.GetVersionString(),
            // Falls back to what allocation says when the probe log is silent: the two
            // paths are three orders of magnitude apart, so it is not a close call.
            NativeLibraryLoaded = reported ?? perFrame < NativePathAllocationCeiling,
            AllocatedBytesPerFrame = perFrame,
            ColdEncodeMillisecondsPerFrame = clock.Elapsed.TotalMilliseconds / measured,
            ProbeLog = text.Trim(),
        };
    }

    /// <summary>
    /// Spectrally rich rather than silence: an all-zero frame encodes unrealistically
    /// cheaply under VBR and would understate both cost and allocation.
    /// </summary>
    private static float[] SyntheticFrame(int channels)
    {
        var frame = new float[AudioCastFormat.SampleCount(channels)];
        double[] partials = [55, 220, 880, 3520, 11000];

        for (var i = 0; i < AudioCastFormat.SamplesPerChannel; i++)
        {
            var t = i / (double)AudioCastFormat.SampleRate;
            var value = partials.Sum(f => Math.Sin(2 * Math.PI * f * t)) / partials.Length * 0.7;

            for (var c = 0; c < channels; c++)
            {
                frame[(i * channels) + c] = (float)value;
            }
        }

        return frame;
    }

    private void Report(OpusCodecDiagnostics diagnostics)
    {
        _logger.LogInformation(
            "Opus ready: {Version}, native={Native}, {Alloc} B/frame ({AllocPerSec:N0} B/s), " +
            "{Encode:F3} ms/frame cold",
            diagnostics.Version,
            diagnostics.NativeLibraryLoaded,
            diagnostics.AllocatedBytesPerFrame,
            diagnostics.AllocatedBytesPerSecond,
            diagnostics.ColdEncodeMillisecondsPerFrame);

        if (diagnostics.AllocatedBytesPerFrame < NativePathAllocationCeiling)
        {
            return;
        }

        // Not fatal — the managed port is comfortably fast enough, at ~1% of a 5 ms
        // frame. It is the steady allocation that eventually costs a listener a dropout.
        _logger.LogWarning(
            "Opus is on the managed path, allocating {AllocPerSec:N0} B/s while casting. " +
            "Install libopus-dev for the unversioned libopus.so symlink, or add the " +
            "Concentus.Native package, to get the zero-allocation path. Probe said: {Probe}",
            diagnostics.AllocatedBytesPerSecond,
            string.IsNullOrEmpty(diagnostics.ProbeLog) ? "(nothing)" : diagnostics.ProbeLog);
    }
}
