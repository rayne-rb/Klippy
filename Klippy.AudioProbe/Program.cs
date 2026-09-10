using System.Diagnostics;
using Klippy.AudioProbe;
using Klippy.Server.Features.AudioCast;
using Klippy.Shared.Audio;
using Microsoft.Extensions.Logging;

// A bench harness for the AudioCast pipeline, run by hand.
//
// Every failure mode in this feature is timing-related, and timing bugs are miserable
// to debug in aggregate. This exists so each stage can be proven on its own: capture
// without a codec, codec without a network, network without a phone.

var command = args.Length > 0 ? args[0] : "help";

using var loggerFactory = LoggerFactory.Create(builder => builder
    .SetMinimumLevel(LogLevel.Debug)
    .AddSimpleConsole(options =>
    {
        options.SingleLine = true;
        options.TimestampFormat = "HH:mm:ss.fff ";
    }));

using var stopping = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    stopping.Cancel();
};

try
{
    return command switch
    {
        "devices" => await ListDevicesAsync(loggerFactory, stopping.Token),
        "capture" => await CaptureAsync(args, loggerFactory, stopping.Token),
        _ => Help(),
    };
}
catch (OperationCanceledException)
{
    Console.WriteLine("Interrupted.");
    return 130;
}

static int Help()
{
    Console.WriteLine(
        """
        Klippy AudioCast probe

          devices
              List the outputs this machine can capture.

          capture [--seconds N] [--out PATH] [--channels 1|2] [--device ID]
              Capture the system mix to a float32 WAV. Proves step 1 in isolation:
              no codec, no network, no phone.

              Defaults: --seconds 5 --out /tmp/klippy-capture.wav --channels 2
              and the platform's default output.

        Note the WAV is IEEE float (format tag 3). Play it with pw-play, paplay, VLC
        or Audacity; a strictly-integer-PCM reader will refuse a perfectly good file.
        """);

    return 1;
}

static IAudioSourceCatalog Catalog(ILoggerFactory loggerFactory)
{
    if (!OperatingSystem.IsLinux())
    {
        throw new PlatformNotSupportedException(
            "The probe only implements the Linux capture path so far.");
    }

    return new PulseAudioSourceCatalog(loggerFactory.CreateLogger<PulseAudioSourceCatalog>());
}

static async Task<int> ListDevicesAsync(ILoggerFactory loggerFactory, CancellationToken ct)
{
    var devices = await Catalog(loggerFactory).ListAsync(ct);

    if (devices.Count == 0)
    {
        Console.WriteLine("No capturable outputs found.");
        return 1;
    }

    Console.WriteLine($"{devices.Count} capturable output(s):");
    foreach (var device in devices)
    {
        Console.WriteLine($"  {(device.IsDefault ? "*" : " ")} {device.Name}");
        Console.WriteLine($"      {device.Id}");
    }

    Console.WriteLine("\n* = platform default, used when --device is omitted.");
    return 0;
}

static async Task<int> CaptureAsync(string[] args, ILoggerFactory loggerFactory, CancellationToken ct)
{
    var seconds = ArgValue(args, "--seconds") is { } s ? double.Parse(s) : 5.0;
    var output = ArgValue(args, "--out") ?? "/tmp/klippy-capture.wav";
    var channels = ArgValue(args, "--channels") is { } c ? int.Parse(c) : 2;
    var deviceId = ArgValue(args, "--device");

    if (!AudioCastFormat.IsSupportedChannelCount(channels))
    {
        Console.Error.WriteLine("--channels must be 1 or 2.");
        return 1;
    }

    var factory = new ParecCaptureSourceFactory(
        Catalog(loggerFactory), loggerFactory.CreateLogger<ParecCaptureSource>());

    await using var source = await factory.OpenAsync(deviceId, channels, ct);

    var frameSamples = AudioCastFormat.SampleCount(channels);
    var expectedFrames = (long)Math.Round(seconds * 1000 / AudioCastFormat.FrameMilliseconds);
    var frame = new float[frameSamples];

    Console.WriteLine($"Capturing '{source.SourceName}'");
    Console.WriteLine(
        $"  {channels} ch, {AudioCastFormat.SampleRate} Hz, {AudioCastFormat.FrameMilliseconds} ms frames " +
        $"({AudioCastFormat.FrameBytes(channels)} B/frame)");
    Console.WriteLine($"  {expectedFrames} frames -> {output}\n");

    await using var wav = await WavWriter.CreateAsync(output, channels, AudioCastFormat.SampleRate);

    var gaps = new List<double>((int)expectedFrames);
    var peak = 0f;
    var nonSilentFrames = 0L;
    var frames = 0L;
    var clock = Stopwatch.StartNew();
    var previous = clock.Elapsed.TotalMilliseconds;

    while (frames < expectedFrames && !ct.IsCancellationRequested)
    {
        if (!await source.ReadFrameAsync(frame, ct))
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

        var frameHasSignal = false;
        foreach (var sample in frame)
        {
            var magnitude = Math.Abs(sample);
            if (magnitude > peak)
            {
                peak = magnitude;
            }

            if (magnitude > 1e-6f)
            {
                frameHasSignal = true;
            }
        }

        if (frameHasSignal)
        {
            nonSilentFrames++;
        }

        wav.Write(frame);
    }

    clock.Stop();
    Report(source, wav, frames, channels, gaps, peak, nonSilentFrames, clock.Elapsed, output);
    return frames > 0 ? 0 : 1;
}

static void Report(
    IAudioCaptureSource source,
    WavWriter wav,
    long frames,
    int channels,
    List<double> gaps,
    float peak,
    long nonSilentFrames,
    TimeSpan elapsed,
    string output)
{
    var audioMs = frames * AudioCastFormat.FrameMilliseconds;
    Console.WriteLine($"frames        {frames}  ({audioMs} ms of audio in {elapsed.TotalMilliseconds:F0} ms wall)");
    Console.WriteLine($"bytes         {wav.DataBytes}  (expected {frames * AudioCastFormat.FrameBytes(channels)})");

    if (gaps.Count > 0)
    {
        gaps.Sort();
        Console.WriteLine(
            $"frame gap     mean {gaps.Average():F2}  p50 {gaps[gaps.Count / 2]:F2}  " +
            $"p99 {gaps[(int)(gaps.Count * 0.99)]:F2}  max {gaps[^1]:F2} ms");
    }

    // The claim under test: at --latency-msec=5 one pipe read is exactly one frame, so
    // nothing downstream needs a reframing buffer.
    if (source is ParecCaptureSource parec)
    {
        var split = parec.FramesNeedingMultipleReads;
        Console.WriteLine(split == 0
            ? $"read align    OK - all {frames} frames arrived in a single read"
            : $"read align    {split} of {frames} frames needed more than one read");
    }

    Console.WriteLine($"signal        peak {peak:F4}, {nonSilentFrames} of {frames} frames non-silent");

    if (nonSilentFrames == 0)
    {
        Console.WriteLine(
            "              (all zeros - the monitor delivers silence when nothing is playing,\n" +
            "               which is correct. Play something to capture real audio.)");
    }

    Console.WriteLine($"\nWrote {output}");
}

static string? ArgValue(string[] args, string name)
{
    var index = Array.IndexOf(args, name);
    return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
}
