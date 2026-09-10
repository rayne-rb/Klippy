using Klippy.Tests.AudioCast.Probe;
using Microsoft.Extensions.Logging;

// A bench harness for the AudioCast pipeline, run by hand.
//
// Every failure mode in this feature is timing-related, and timing bugs are miserable
// to debug in aggregate. This exists so each stage can be proven on its own: capture
// without a codec, the codec without a network, the server chain without a phone.

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
        "capture" => await CaptureCommand.RunAsync(args, loggerFactory, stopping.Token),
        "codec" => await CodecCommand.RunAsync(args, loggerFactory, stopping.Token),
        "stream" => await StreamCommand.RunAsync(args, loggerFactory, stopping.Token),
        "cast" => await CastCommand.RunAsync(args, loggerFactory, stopping.Token),
        "jitter" => await JitterCommand.RunAsync(args, loggerFactory, stopping.Token),
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

          capture [--seconds N] [--out PATH] [--channels 1|2] [--device ID] [--play]
              Step 1. Capture the system mix straight to a float32 WAV. No codec,
              no network, no phone. Reports frame timing and whether every frame
              arrived in a single pipe read.

          codec [--seconds N] [--channels 1|2]
              Step 3a. Put a known signal through the real encoder settings and
              back, and report what the codec resolved to: native or managed,
              allocation per frame, timing, packet size, and round-trip fidelity.

          stream [--seconds N] [--out PATH] [--channels 1|2] [--device ID]
                 [--listeners N] [--play]
              Step 3b. The whole server chain end to end - capture through the
              broadcaster, out as encoded frames, decoded back to a WAV. Pass
              --listeners 2 to check that N listeners share one capture.

          cast [--server URL] [--seconds N] [--channels 1|2] [--out PATH] [--play]
              Step 4 against a running server: pair, ask over the Link, prove the
              ephemeral key over UDP, decode what comes back. Does what a phone
              does. Defaults to --server http://localhost:5068.

          jitter [--seconds N]
              Step 6. Replay synthetic arrival traces - clean LAN, WiFi, WiFi
              with retransmit spikes, spikes plus loss - through the adaptive
              jitter buffer and against fixed buffers, and report what each
              costs in dropouts and latency. No phone needed.

        WAVs are IEEE float (format tag 3). Play them with pw-play, paplay, VLC or
        Audacity; a strictly-integer-PCM reader will refuse a perfectly good file.
        """);

    return 1;
}

static async Task<int> ListDevicesAsync(ILoggerFactory loggerFactory, CancellationToken cancellationToken)
{
    var devices = await ProbeArgs.Catalog(loggerFactory).ListAsync(cancellationToken);

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
