using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Captures the system mix on Linux by reading <c>parec</c>'s stdout.
///
/// A sink's <c>.monitor</c> source *is* the post-mix output — every application plus
/// system sounds — so no virtual sink or loopback module has to be configured first.
/// Talking to it through <c>parec</c> rather than libpipewire means this also works
/// unchanged on a real PulseAudio box, and measurement said it is the faster of the
/// two anyway: <c>pw-record</c> ignores the latency hint entirely and sits at 10.67 ms
/// no matter what it is asked for.
///
/// Unlike WASAPI loopback, a PipeWire monitor keeps delivering zeros when nothing is
/// playing (measured: 762 KB over 2 s on an idle sink). So there is deliberately no
/// silence injection here — the stream does not stall when the music pauses, and the
/// Windows source has to solve that problem alone.
/// </summary>
public sealed class ParecCaptureSource : IAudioCaptureSource
{
    /// <summary>
    /// The measured sweet spot, and the reason nothing downstream reframes.
    ///
    /// At 5 ms one read off the pipe is exactly one 240-sample Opus frame. Asking for
    /// less does not help — a frame cannot be encoded before 5 ms of audio exists, so
    /// the 2.67 ms floor buys nothing and would force a ring buffer. Asking for 3 ms
    /// is actively worse: it straddles the power-of-two quantum and arrives in bursts
    /// (p50 2.67 ms, p99 5.36 ms) instead of the metronomic 5.00 ms this gives.
    /// </summary>
    private const int CaptureLatencyMilliseconds = AudioCastFormat.FrameMilliseconds;

    /// <summary>
    /// Long enough that a suspended sink has time to resume, short enough to still be
    /// an error message rather than a hang. Only ever paid when something is wrong.
    /// </summary>
    private static readonly TimeSpan PrimingTimeout = TimeSpan.FromSeconds(2);

    private readonly Process _process;
    private readonly Stream _stdout;
    private readonly byte[] _frameBytes;
    private readonly StringBuilder _diagnostics;
    private readonly ILogger _logger;

    private float[]? _primedFrame;
    private long _framesRead;
    private long _framesNeedingMultipleReads;
    private bool _disposed;

    private ParecCaptureSource(
        Process process,
        int channels,
        string sourceName,
        StringBuilder diagnostics,
        ILogger logger)
    {
        _process = process;
        _stdout = process.StandardOutput.BaseStream;
        Channels = channels;
        SourceName = sourceName;
        _diagnostics = diagnostics;
        _logger = logger;
        _frameBytes = new byte[AudioCastFormat.FrameBytes(channels)];
    }

    public int Channels { get; }

    public string SourceName { get; }

    /// <summary>Frames so far. Single-reader by contract, so these counters are unsynchronised.</summary>
    public long FramesRead => _framesRead;

    /// <summary>
    /// How many frames needed more than one pipe read. Expected to stay at zero — if it
    /// climbs, 5 ms has stopped delivering whole frames on this machine and the
    /// no-reframing assumption above needs revisiting.
    /// </summary>
    public long FramesNeedingMultipleReads => _framesNeedingMultipleReads;

    public static async Task<ParecCaptureSource> StartAsync(
        string monitorSource,
        int channels,
        string sourceName,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        if (!BitConverter.IsLittleEndian)
        {
            // parec is asked for float32le and the frame is reinterpreted in place.
            throw new PlatformNotSupportedException("Audio capture assumes a little-endian host.");
        }

        var startInfo = new ProcessStartInfo("parec")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        startInfo.ArgumentList.Add($"--device={monitorSource}");
        startInfo.ArgumentList.Add("--format=float32le");
        startInfo.ArgumentList.Add($"--rate={AudioCastFormat.SampleRate}");
        startInfo.ArgumentList.Add($"--channels={channels}");
        startInfo.ArgumentList.Add($"--latency-msec={CaptureLatencyMilliseconds}");

        var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Could not start parec. Is pulseaudio-utils installed?");

        var diagnostics = DrainDiagnostics(process);
        var source = new ParecCaptureSource(process, channels, sourceName, diagnostics, logger);

        // Prove the stream really produces audio before handing it back. An idle sink
        // still yields zeros, so this succeeds on a silent machine; what it catches is a
        // source that has gone away since it was enumerated. parec is no help there —
        // pointed at a nonexistent device it neither exits nor writes to stderr, it
        // simply sits producing nothing — so a read is the only reliable probe.
        // The frame is kept rather than discarded: it is real audio.
        var primed = new float[AudioCastFormat.SampleCount(channels)];

        try
        {
            using var priming = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            priming.CancelAfter(PrimingTimeout);

            if (!await source.FillAsync(primed, priming.Token))
            {
                throw new InvalidOperationException(
                    $"parec produced no audio for '{monitorSource}'. {source.DiagnosticText()}".TrimEnd());
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            await source.DisposeAsync();
            throw new TimeoutException(
                $"parec produced no audio for '{monitorSource}' within {PrimingTimeout.TotalSeconds:0}s. " +
                $"{source.DiagnosticText()}".TrimEnd());
        }
        catch
        {
            await source.DisposeAsync();
            throw;
        }

        source._primedFrame = primed;
        return source;
    }

    public async ValueTask<bool> ReadFrameAsync(Memory<float> frame, CancellationToken cancellationToken)
    {
        var expected = AudioCastFormat.SampleCount(Channels);
        if (frame.Length != expected)
        {
            throw new ArgumentException($"Expected a {expected}-sample frame, got {frame.Length}.", nameof(frame));
        }

        if (_primedFrame is { } primed)
        {
            _primedFrame = null;
            primed.CopyTo(frame.Span);
            return true;
        }

        return await FillAsync(frame, cancellationToken);
    }

    /// <summary>
    /// Reads exactly one frame, counting how many pipe reads it took.
    ///
    /// Frame alignment is enforced rather than assumed: a pipe carries no message
    /// boundaries, so however reliably 5 ms delivers 1920 bytes in a single read,
    /// correctness cannot rest on it.
    /// </summary>
    private async ValueTask<bool> FillAsync(Memory<float> frame, CancellationToken cancellationToken)
    {
        var buffer = _frameBytes;
        var filled = 0;
        var reads = 0;

        while (filled < buffer.Length)
        {
            var read = await _stdout.ReadAsync(buffer.AsMemory(filled), cancellationToken);
            reads++;

            if (read == 0)
            {
                if (filled > 0)
                {
                    _logger.LogWarning(
                        "Capture ended mid-frame with {Filled} of {Total} bytes", filled, buffer.Length);
                }

                return false;
            }

            filled += read;
        }

        MemoryMarshal.Cast<byte, float>(buffer).CopyTo(frame.Span);

        _framesRead++;
        if (reads > 1)
        {
            _framesNeedingMultipleReads++;
        }

        return true;
    }

    /// <summary>
    /// Keeps stderr drained. parec blocks once a full pipe has nowhere to go, and a
    /// capture that stalls on its own error output is a miserable thing to debug.
    /// </summary>
    private static StringBuilder DrainDiagnostics(Process process)
    {
        var diagnostics = new StringBuilder();

        _ = Task.Run(async () =>
        {
            try
            {
                while (await process.StandardError.ReadLineAsync() is { } line)
                {
                    lock (diagnostics)
                    {
                        diagnostics.AppendLine(line);
                    }
                }
            }
            catch (IOException)
            {
                // Process gone; nothing left to read.
            }
        }, CancellationToken.None);

        return diagnostics;
    }

    private string DiagnosticText()
    {
        lock (_diagnostics)
        {
            return _diagnostics.ToString().Trim();
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        if (_framesRead > 0)
        {
            _logger.LogInformation(
                "Capture of '{Source}' ended after {Frames} frames ({Split} needed more than one read)",
                SourceName, _framesRead, _framesNeedingMultipleReads);
        }

        try
        {
            if (!_process.HasExited)
            {
                // Killing is also what unblocks a reader parked in ReadAsync: the pipe
                // hits EOF and the fill loop returns false.
                _process.Kill(entireProcessTree: true);
            }

            await _process.WaitForExitAsync();
        }
        catch (InvalidOperationException)
        {
            // Already reaped.
        }
        finally
        {
            _process.Dispose();
        }
    }
}

/// <summary>Opens <see cref="ParecCaptureSource"/> instances. Linux only.</summary>
public sealed class ParecCaptureSourceFactory(
    IAudioSourceCatalog catalog,
    ILogger<ParecCaptureSource> logger) : IAudioCaptureSourceFactory
{
    public bool IsSupported => OperatingSystem.IsLinux();

    public async Task<IAudioCaptureSource> OpenAsync(
        string? deviceId,
        int channels,
        CancellationToken cancellationToken)
    {
        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            throw new ArgumentOutOfRangeException(nameof(channels), channels, "Only mono and stereo are supported.");
        }

        // Resolved against the catalog rather than passed straight through: parec gives
        // no error for a device that does not exist, so this is where a bad id has to be
        // caught.
        var devices = await catalog.ListAsync(cancellationToken);

        var device = deviceId is null
            ? devices.FirstOrDefault(d => d.IsDefault) ?? devices.FirstOrDefault()
            : devices.FirstOrDefault(d => d.Id == deviceId);

        if (device is null)
        {
            throw new InvalidOperationException(
                deviceId is null
                    ? "No capturable output was found. Is PulseAudio or PipeWire running?"
                    : $"Output '{deviceId}' is not available.");
        }

        return await ParecCaptureSource.StartAsync(
            device.Id, channels, device.Name, logger, cancellationToken);
    }
}
