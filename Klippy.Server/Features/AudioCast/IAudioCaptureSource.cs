using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// The OS seam. One open capture of the system mix, delivering fixed-size frames of
/// interleaved float32.
///
/// Float32 rather than int16 because it is what both platforms hand us natively —
/// WASAPI loopback is float32, and PipeWire's monitor will give it without a
/// conversion — and because Opus has a float API, so the whole path avoids an integer
/// round-trip it would only have to undo.
/// </summary>
public interface IAudioCaptureSource : IAsyncDisposable
{
    /// <summary>1 or 2. Fixed for the life of the source.</summary>
    int Channels { get; }

    /// <summary>What is being captured, for the listener's UI.</summary>
    string SourceName { get; }

    /// <summary>
    /// Fills <paramref name="frame"/> with exactly one frame and returns true, or
    /// returns false once the capture has ended.
    ///
    /// The buffer is caller-owned so a running cast allocates nothing per frame. It
    /// must be <see cref="AudioCastFormat.SampleCount"/> long.
    /// </summary>
    ValueTask<bool> ReadFrameAsync(Memory<float> frame, CancellationToken cancellationToken);
}

/// <summary>
/// Opens capture sources for whichever OS the server is running on. Registered per
/// platform; <see cref="IsSupported"/> is what keeps the Linux build from ever
/// touching the Windows-only one.
/// </summary>
public interface IAudioCaptureSourceFactory
{
    /// <summary>False when this implementation cannot run here, e.g. WASAPI on Linux.</summary>
    bool IsSupported { get; }

    /// <summary>
    /// Opens the given output for capture, or the platform default when
    /// <paramref name="deviceId"/> is null.
    /// </summary>
    Task<IAudioCaptureSource> OpenAsync(string? deviceId, int channels, CancellationToken cancellationToken);
}

/// <summary>
/// Lists what this machine can capture, so the picker is not a text box the user has
/// to paste a PulseAudio sink name into.
///
/// Enumeration lives next to its capture source rather than in one cross-platform
/// class: the id a device is identified by is only meaningful to the code that opens
/// it, and keeping the pair together means neither platform's naming leaks into the
/// other's.
/// </summary>
public interface IAudioSourceCatalog
{
    Task<IReadOnlyList<AudioOutputDevice>> ListAsync(CancellationToken cancellationToken);
}
