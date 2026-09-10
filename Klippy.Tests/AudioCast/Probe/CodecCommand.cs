using System.Diagnostics;
using Concentus;
using Concentus.Enums;
using Klippy.Server.Features.AudioCast;
using Klippy.Shared.Audio;
using Microsoft.Extensions.Logging;

namespace Klippy.Tests.AudioCast.Probe;

/// <summary>
/// Puts a known signal through the real encoder configuration and back.
///
/// This is the codec half of step 3, isolated from capture and from the network: if the
/// stream ever sounds wrong, this says whether the codec settings are the reason before
/// anyone goes looking at jitter buffers.
/// </summary>
internal static class CodecCommand
{
    public static Task<int> RunAsync(string[] args, ILoggerFactory loggerFactory, CancellationToken cancellationToken)
    {
        var channels = ProbeArgs.Channels(args);
        var seconds = ProbeArgs.Seconds(args, 2.0);

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            Console.Error.WriteLine("--channels must be 1 or 2.");
            return Task.FromResult(1);
        }

        var pool = new OpusEncoderPool(loggerFactory.CreateLogger<OpusEncoderPool>());
        var diagnostics = pool.Diagnostics;

        Console.WriteLine("Opus configuration (plan §5)");
        Console.WriteLine($"  version              {diagnostics.Version}");
        Console.WriteLine($"  native libopus       {diagnostics.NativeLibraryLoaded}");
        Console.WriteLine($"  alloc per frame      {diagnostics.AllocatedBytesPerFrame:N0} B" +
                          $"  ({diagnostics.AllocatedBytesPerSecond:N0} B/s while casting)");
        Console.WriteLine($"  encode per frame     {diagnostics.ColdEncodeMillisecondsPerFrame:F3} ms cold" +
                          $"  (startup sample; steady state is measured below)");

        if (!string.IsNullOrEmpty(diagnostics.ProbeLog))
        {
            Console.WriteLine($"  probe                {diagnostics.ProbeLog.Replace("\n", " | ")}");
        }

        var encoder = pool.Rent(channels);
        using var decoder = OpusCodecFactory.CreateDecoder(AudioCastFormat.SampleRate, channels);

        Console.WriteLine($"  lookahead            {encoder.Lookahead} samples " +
                          $"({encoder.Lookahead * 1000.0 / AudioCastFormat.SampleRate:F2} ms)");
        Console.WriteLine($"  application          RESTRICTED_LOWDELAY (CELT-only)");
        Console.WriteLine($"  bitrate target       {AudioCastFormat.BitrateFor(channels):N0} bps\n");

        var frames = (int)Math.Round(seconds * 1000 / AudioCastFormat.FrameMilliseconds);
        var perFrame = AudioCastFormat.SampleCount(channels);

        var original = Signal(frames, channels);
        var decoded = new float[frames * perFrame];
        var packet = new byte[AudioCastPacket.MaxPayloadBytes];

        long encodedBytes = 0;
        var encodeMs = new List<double>(frames);
        var decodeMs = new List<double>(frames);
        var clock = new Stopwatch();

        // Warm up before timing anything. Without this the mean is dominated by tiered
        // JIT on the first few hundred calls — measured, that reads ~6x slower than
        // steady state and would make the codec look like a cost it is not.
        var warmupPacket = new byte[AudioCastPacket.MaxPayloadBytes];
        var warmupPcm = new float[perFrame];
        for (var i = 0; i < 2000; i++)
        {
            var written = encoder.Encode(
                original.AsSpan(0, perFrame), AudioCastFormat.SamplesPerChannel, warmupPacket, warmupPacket.Length);
            decoder.Decode(
                warmupPacket.AsSpan(0, written), warmupPcm, AudioCastFormat.SamplesPerChannel, decode_fec: false);
        }

        encoder.ResetState();
        decoder.ResetState();

        for (var i = 0; i < frames && !cancellationToken.IsCancellationRequested; i++)
        {
            var input = original.AsSpan(i * perFrame, perFrame);

            clock.Restart();
            var length = encoder.Encode(input, AudioCastFormat.SamplesPerChannel, packet, packet.Length);
            clock.Stop();
            encodeMs.Add(clock.Elapsed.TotalMilliseconds);

            if (length <= 0)
            {
                Console.Error.WriteLine($"Encode returned {length} on frame {i}.");
                return Task.FromResult(1);
            }

            encodedBytes += length;

            clock.Restart();
            var produced = decoder.Decode(
                packet.AsSpan(0, length),
                decoded.AsSpan(i * perFrame, perFrame),
                AudioCastFormat.SamplesPerChannel,
                decode_fec: false);
            clock.Stop();
            decodeMs.Add(clock.Elapsed.TotalMilliseconds);

            if (produced != AudioCastFormat.SamplesPerChannel)
            {
                Console.Error.WriteLine(
                    $"Decode returned {produced} samples, expected {AudioCastFormat.SamplesPerChannel}.");
                return Task.FromResult(1);
            }
        }

        pool.Return(encoder);

        var averagePacket = encodedBytes / (double)frames;
        var actualBitrate = encodedBytes * 8.0 / (frames * AudioCastFormat.FrameMilliseconds / 1000.0);

        Console.WriteLine($"Round trip: {frames} frames, {seconds:F1}s, {channels} ch");
        Console.WriteLine($"  packet               {averagePacket:F1} B avg -> {actualBitrate / 1000:F0} kbps actual");
        Stats("  encode             ", encodeMs);
        Stats("  decode             ", decodeMs);

        // Opus is perceptual, not waveform-preserving, so a modest SNR is expected and
        // fine. Correlation is the honest measure of "did the same audio come back".
        var (snr, correlation) = Compare(original, decoded, encoder.Lookahead * channels);
        Console.WriteLine($"  waveform SNR         {snr:F1} dB");
        Console.WriteLine($"  correlation          {correlation:F4}  (aligned by {encoder.Lookahead}-sample lookahead)");

        var ok = correlation > 0.8;
        Console.WriteLine(ok
            ? "\nPASS - the same audio came back."
            : $"\nFAIL - correlation {correlation:F4} is too low for a working round trip.");

        return Task.FromResult(ok ? 0 : 1);
    }

    private static void Stats(string label, List<double> samples)
    {
        if (samples.Count == 0)
        {
            return;
        }

        var sorted = samples.ToArray();
        Array.Sort(sorted);

        Console.WriteLine(
            $"{label}  mean {sorted.Average():F3}  p50 {sorted[sorted.Length / 2]:F3}  " +
            $"p99 {sorted[(int)(sorted.Length * 0.99)]:F3}  max {sorted[^1]:F3} ms");
    }

    /// <summary>
    /// Spectrally rich, so CELT has real work to do. A pure tone or silence would encode
    /// unrealistically well and tell us nothing.
    /// </summary>
    private static float[] Signal(int frames, int channels)
    {
        var samples = new float[frames * AudioCastFormat.SampleCount(channels)];
        var random = new Random(1234);
        double[] partials = [55, 110, 220, 440, 880, 1760, 3520, 7040, 11000, 15500];

        for (var i = 0; i < frames * AudioCastFormat.SamplesPerChannel; i++)
        {
            var t = i / (double)AudioCastFormat.SampleRate;
            var left = partials.Sum(f => Math.Sin(2 * Math.PI * f * t)) / partials.Length;
            var right = partials.Sum(f => Math.Sin((2 * Math.PI * f * t * 1.003) + 0.7)) / partials.Length;

            left = (left * 0.7) + ((random.NextDouble() - 0.5) * 0.05);
            right = (right * 0.7) + ((random.NextDouble() - 0.5) * 0.05);

            if (channels == 1)
            {
                samples[i] = (float)left;
            }
            else
            {
                samples[i * 2] = (float)left;
                samples[(i * 2) + 1] = (float)right;
            }
        }

        return samples;
    }

    /// <summary>
    /// Compares input against output, shifted by the codec's own delay. Without that
    /// shift both numbers look like noise even on a perfect round trip.
    /// </summary>
    private static (double Snr, double Correlation) Compare(float[] original, float[] decoded, int delay)
    {
        var length = Math.Min(original.Length, decoded.Length) - delay;
        if (length <= 0)
        {
            return (double.NaN, double.NaN);
        }

        double signal = 0, noise = 0, dot = 0, normA = 0, normB = 0;

        for (var i = 0; i < length; i++)
        {
            double a = original[i];
            double b = decoded[i + delay];

            signal += a * a;
            noise += (a - b) * (a - b);
            dot += a * b;
            normA += a * a;
            normB += b * b;
        }

        var snr = noise > 0 ? 10 * Math.Log10(signal / noise) : double.PositiveInfinity;
        var correlation = normA > 0 && normB > 0 ? dot / Math.Sqrt(normA * normB) : 0;

        return (snr, correlation);
    }
}
