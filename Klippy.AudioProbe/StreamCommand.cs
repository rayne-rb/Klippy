using Concentus;
using Klippy.Server.Features.AudioCast;
using Klippy.Shared.Audio;
using Microsoft.Extensions.Logging;

namespace Klippy.AudioProbe;

/// <summary>
/// The whole server-side chain, end to end, with no phone involved: capture through
/// <see cref="AudioBroadcaster"/>, out as encoded frames, decoded here and written to a
/// WAV you can listen to.
///
/// This is step 3's "desktop test client". If this sounds right, everything left to go
/// wrong is transport or playback, which is exactly the point of proving it here first.
/// </summary>
internal static class StreamCommand
{
    public static async Task<int> RunAsync(
        string[] args,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var channels = ProbeArgs.Channels(args);
        var seconds = ProbeArgs.Seconds(args, 5.0);
        var output = ProbeArgs.Value(args, "--out") ?? "/tmp/klippy-decoded.wav";
        var deviceId = ProbeArgs.Value(args, "--device");
        var listeners = ProbeArgs.Value(args, "--listeners") is { } l ? int.Parse(l) : 1;

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            Console.Error.WriteLine("--channels must be 1 or 2.");
            return 1;
        }

        var pool = new OpusEncoderPool(loggerFactory.CreateLogger<OpusEncoderPool>());

        await using var broadcaster = new AudioBroadcaster(
            [ProbeArgs.CaptureFactory(loggerFactory)],
            pool,
            loggerFactory.CreateLogger<AudioBroadcaster>());

        // More than one proves the ref-counting: N listeners must share one capture and
        // one encoder, not spawn N of each.
        var subscriptions = new List<IAudioSubscription>();
        for (var i = 0; i < listeners; i++)
        {
            subscriptions.Add(await broadcaster.SubscribeAsync(deviceId, channels, cancellationToken));
        }

        var format = subscriptions[0].Format;
        Console.WriteLine($"Streaming '{format.SourceName}'");
        Console.WriteLine($"  {format.Codec} {format.SampleRate} Hz {format.Channels} ch, " +
                          $"{format.FrameMilliseconds} ms frames");
        Console.WriteLine($"  {listeners} listener(s), {seconds:F1}s -> {output}");
        Console.WriteLine($"  captures active: {broadcaster.Active.Count}\n");

        var expectedFrames = (long)Math.Round(seconds * 1000 / AudioCastFormat.FrameMilliseconds);

        // Only the first listener is decoded; the rest exist to exercise the fan-out.
        var result = await DrainAsync(
            subscriptions[0], channels, expectedFrames, output, broadcaster, cancellationToken);

        foreach (var subscription in subscriptions)
        {
            await subscription.DisposeAsync();
        }

        if (result == 0 && ProbeArgs.Flag(args, "--play"))
        {
            await ProbeArgs.PlayAsync(output);
        }

        return result;
    }

    private static async Task<int> DrainAsync(
        IAudioSubscription subscription,
        int channels,
        long expectedFrames,
        string output,
        AudioBroadcaster broadcaster,
        CancellationToken cancellationToken)
    {
        using var decoder = OpusCodecFactory.CreateDecoder(AudioCastFormat.SampleRate, channels);
        await using var wav = await WavWriter.CreateAsync(output, channels, AudioCastFormat.SampleRate);

        var pcm = new float[AudioCastFormat.SampleCount(channels)];
        var packetSizes = new List<int>((int)expectedFrames);

        long frames = 0, encodedBytes = 0, sequenceGaps = 0, nonSilent = 0;
        uint? previousSequence = null;
        var peak = 0f;

        await foreach (var frame in subscription.ReadAllAsync(cancellationToken))
        {
            if (previousSequence is { } previous && frame.Header.Sequence != previous + 1)
            {
                // A gap here means the broadcaster dropped for this listener, which is a
                // local stall, not packet loss — nothing has touched the network yet.
                sequenceGaps++;
            }

            previousSequence = frame.Header.Sequence;
            encodedBytes += frame.Payload.Length;
            packetSizes.Add(frame.Payload.Length);

            var produced = decoder.Decode(
                frame.Payload.Span, pcm, AudioCastFormat.SamplesPerChannel, decode_fec: false);

            if (produced != AudioCastFormat.SamplesPerChannel)
            {
                Console.Error.WriteLine($"Decode returned {produced} samples on sequence {frame.Header.Sequence}.");
                return 1;
            }

            var hasSignal = false;
            foreach (var sample in pcm)
            {
                var magnitude = Math.Abs(sample);
                if (magnitude > peak)
                {
                    peak = magnitude;
                }

                if (magnitude > 1e-6f)
                {
                    hasSignal = true;
                }
            }

            if (hasSignal)
            {
                nonSilent++;
            }

            wav.Write(pcm);

            if (++frames >= expectedFrames)
            {
                break;
            }
        }

        if (frames == 0)
        {
            Console.Error.WriteLine("No frames arrived.");
            return 1;
        }

        packetSizes.Sort();
        var audioMs = frames * AudioCastFormat.FrameMilliseconds;
        var bitrate = encodedBytes * 8.0 / (audioMs / 1000.0);

        Console.WriteLine($"frames        {frames}  ({audioMs} ms of audio)");
        Console.WriteLine($"packet        mean {encodedBytes / (double)frames:F1} B  " +
                          $"p50 {packetSizes[packetSizes.Count / 2]} B  max {packetSizes[^1]} B");
        Console.WriteLine($"bitrate       {bitrate / 1000:F0} kbps actual");
        Console.WriteLine($"datagram      {packetSizes[^1] + AudioCastPacket.HeaderBytes} B worst case " +
                          $"(limit {AudioCastPacket.MaxDatagramBytes}, MTU-safe: " +
                          $"{packetSizes[^1] + AudioCastPacket.HeaderBytes <= AudioCastPacket.MaxDatagramBytes})");
        Console.WriteLine($"sequence      {sequenceGaps} gap(s)");
        Console.WriteLine($"dropped       {subscription.FramesDropped} frame(s) for this listener");
        Console.WriteLine($"decoded pcm   {wav.DataBytes} B  (expected {frames * AudioCastFormat.FrameBytes(channels)})");
        Console.WriteLine($"signal        peak {peak:F4}, {nonSilent} of {frames} frames non-silent");
        Console.WriteLine($"captures      {broadcaster.Active.Count} active " +
                          $"(listeners: {string.Join(", ", broadcaster.Active.Select(a => a.Listeners))})");

        if (nonSilent == 0)
        {
            Console.WriteLine("\n              (all silence - correct for an idle machine. Play something\n" +
                              "               to hear real audio come back through the codec.)");
        }

        Console.WriteLine($"\nWrote {output}");
        return 0;
    }
}
