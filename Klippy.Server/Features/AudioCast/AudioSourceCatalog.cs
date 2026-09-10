using System.Diagnostics;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Lists the sink monitors on a PulseAudio or PipeWire box.
///
/// A monitor is named after its sink with <c>.monitor</c> appended, and that full name
/// is what <c>parec --device=</c> wants, so it is used as the id directly. The
/// human-readable half comes from the sink's Description, because
/// "alsa_output.pci-0000_0b_00.6.analog-stereo" is not a thing to show in a picker.
/// </summary>
public sealed class PulseAudioSourceCatalog(ILogger<PulseAudioSourceCatalog> logger) : IAudioSourceCatalog
{
    private const string MonitorSuffix = ".monitor";

    public async Task<IReadOnlyList<AudioOutputDevice>> ListAsync(CancellationToken cancellationToken)
    {
        var defaultSink = (await RunAsync("pactl", ["get-default-sink"], cancellationToken))?.Trim();
        var listing = await RunAsync("pactl", ["list", "sinks"], cancellationToken);

        if (listing is null)
        {
            logger.LogWarning("Could not list sinks: pactl is unavailable or failed");
            return [];
        }

        var devices = new List<AudioOutputDevice>();
        string? name = null;
        string? description = null;

        // Flat scan rather than a block parser: every "Name:" starts a sink's fields and
        // every "Description:" completes the only pair worth keeping.
        foreach (var raw in listing.Split('\n'))
        {
            var line = raw.Trim();

            if (line.StartsWith("Name:", StringComparison.Ordinal))
            {
                name = line["Name:".Length..].Trim();
                description = null;
            }
            else if (line.StartsWith("Description:", StringComparison.Ordinal))
            {
                description = line["Description:".Length..].Trim();
            }

            if (name is null || description is null)
            {
                continue;
            }

            devices.Add(new AudioOutputDevice
            {
                Id = name + MonitorSuffix,
                Name = description,
                IsDefault = name == defaultSink,
            });

            name = null;
            description = null;
        }

        if (devices.Count == 0)
        {
            logger.LogWarning("pactl reported no sinks; there is nothing to cast");
        }

        return devices;
    }

    /// <summary>
    /// Runs a short-lived command and returns its stdout, or null if it could not run
    /// or failed. Enumeration is a convenience — a missing <c>pactl</c> should degrade
    /// to an empty picker, not take the server down.
    /// </summary>
    private async Task<string?> RunAsync(string file, string[] arguments, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo(file)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return null;
            }

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));

            var stdout = await process.StandardOutput.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);

            if (process.ExitCode != 0)
            {
                var stderr = await process.StandardError.ReadToEndAsync(CancellationToken.None);
                logger.LogWarning("{File} {Args} exited {Code}: {Error}",
                    file, string.Join(' ', arguments), process.ExitCode, stderr.Trim());
                return null;
            }

            return stdout;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("{File} {Args} timed out", file, string.Join(' ', arguments));
            return null;
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            logger.LogWarning(ex, "Could not run {File}", file);
            return null;
        }
    }
}
