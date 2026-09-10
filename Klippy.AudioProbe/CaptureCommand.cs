using System.Diagnostics;
using Klippy.Server.Features.AudioCast;
using Klippy.Shared.Audio;
using Microsoft.Extensions.Logging;

namespace Klippy.AudioProbe;

/// <summary>
/// Step 1 on its own: capture the system mix to a WAV, with no codec and no network in
/// the way. Also the place the plan's central capture claim is checked — that at
/// <c>--latency-msec=5</c> one pipe read is exactly one frame.
/// </summary>
internal static class CaptureCommand
{
    public static async Task<int> RunAsync(
        string[] args,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var seconds = ProbeArgs.Seconds(args, 5.0);
        var output = ProbeArgs.Value(args, "--out") ?? "/tmp/klippy-capture.wav";
        var channels = ProbeArgs.Channels(args);
        var deviceId = ProbeArgs.Value(args, "--device");

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            Console.Error.WriteLine("--channels must be 1 or 2.");
            return 1;
        }

        await using var source = await ProbeArgs.CaptureFactory(loggerFactory)
            .OpenAsync(deviceId, channels, cancellationToken);

        var expectedFrames = (long)Math.Round(seconds * 1000 / AudioCastFormat.FrameMilliseconds);
        var frame = new float[AudioCastFormat.SampleCount(channels)];

        Console.WriteLine($"Capturing '{source.SourceName}'");
        Console.WriteLine(
            $"  {channels} ch, {AudioCastFormat.SampleRate} Hz, {AudioCastFormat.FrameMilliseconds} ms frames " +
            $"({AudioCastFormat.FrameBytes(channels)} B/frame)");
        Console.WriteLine($"  {expectedFrames} frames -> {output}\n");

        await using var wav = await WavWriter.CreateAsync(output, channels, AudioCastFormat.SampleRate);

        var gaps = new List<double>((int)expectedFrames);
        var peak = 0f;
        long nonSilent = 0, frames = 0;
        var clock = Stopwatch.StartNew();
        var previous = clock.Elapsed.TotalMilliseconds;

        while (frames < expectedFrames && !cancellationToken.IsCancellationRequested)
        {
            if (!await source.ReadFrameAsync(frame, cancellationToken))
            {
                Console.Error.WriteLine("Capture ended early.");
                break;
            }

            var now = clock.Elapsed.TotalMilliseconds;
            if (frames > 0)
            {
                gaps.Add(now - previous);
            }

            previous = now;
            frames++;

            var hasSignal = false;
            foreach (var sample in frame)
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

            wav.Write(frame);
        }

        clock.Stop();

        var audioMs = frames * AudioCastFormat.FrameMilliseconds;
        Console.WriteLine($"frames        {frames}  ({audioMs} ms of audio in {clock.Elapsed.TotalMilliseconds:F0} ms wall)");
        Console.WriteLine($"bytes         {wav.DataBytes}  (expected {frames * AudioCastFormat.FrameBytes(channels)})");

        if (gaps.Count > 0)
        {
            gaps.Sort();
            Console.WriteLine(
                $"frame gap     mean {gaps.Average():F2}  p50 {gaps[gaps.Count / 2]:F2}  " +
                $"p99 {gaps[(int)(gaps.Count * 0.99)]:F2}  max {gaps[^1]:F2} ms");
        }

        if (source is ParecCaptureSource parec)
        {
            var split = parec.FramesNeedingMultipleReads;
            Console.WriteLine(split == 0
                ? $"read align    OK - all {frames} frames arrived in a single read"
                : $"read align    {split} of {frames} frames needed more than one read");
        }

        Console.WriteLine($"signal        peak {peak:F4}, {nonSilent} of {frames} frames non-silent");

        if (nonSilent == 0)
        {
            Console.WriteLine(
                "              (all zeros - the monitor delivers silence when nothing is playing,\n" +
                "               which is correct. Play something to capture real audio.)");
        }

        Console.WriteLine($"\nWrote {output}");

        if (frames > 0 && ProbeArgs.Flag(args, "--play"))
        {
            await ProbeArgs.PlayAsync(output);
        }

        return frames > 0 ? 0 : 1;
    }
}
