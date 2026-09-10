using Klippy.Server.Features.AudioCast;
using Microsoft.Extensions.Logging;

namespace Klippy.Tests.AudioCast.Probe;

/// <summary>Just enough argument handling for a hand-run bench tool.</summary>
internal static class ProbeArgs
{
    public static string? Value(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    public static bool Flag(string[] args, string name) => Array.IndexOf(args, name) >= 0;

    public static int Channels(string[] args) => Value(args, "--channels") is { } c ? int.Parse(c) : 2;

    public static double Seconds(string[] args, double fallback) =>
        Value(args, "--seconds") is { } s ? double.Parse(s) : fallback;

    /// <summary>
    /// The Linux capture stack, wired by hand. The probe deliberately builds the real
    /// server types rather than a DI container: a harness with its own copy of the
    /// pipeline would prove nothing about the one that ships.
    /// </summary>
    public static IAudioSourceCatalog Catalog(ILoggerFactory loggerFactory)
    {
        if (!OperatingSystem.IsLinux())
        {
            throw new PlatformNotSupportedException("The probe only implements the Linux capture path so far.");
        }

        return new PulseAudioSourceCatalog(loggerFactory.CreateLogger<PulseAudioSourceCatalog>());
    }

    public static ParecCaptureSourceFactory CaptureFactory(ILoggerFactory loggerFactory) =>
        new(Catalog(loggerFactory), loggerFactory.CreateLogger<ParecCaptureSource>());

    /// <summary>Plays a file with a float-aware player, for an ear check after a run.</summary>
    public static async Task PlayAsync(string path)
    {
        Console.WriteLine($"\nPlaying {path} ...");

        try
        {
            using var player = System.Diagnostics.Process.Start("pw-play", [path]);
            if (player is not null)
            {
                await player.WaitForExitAsync();
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Could not play it: {ex.Message}");
        }
    }
}
