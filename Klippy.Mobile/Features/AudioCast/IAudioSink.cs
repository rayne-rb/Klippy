using Klippy.Shared.Audio;

namespace Klippy.Mobile.Features.AudioCast;

/// <summary>
/// Where decoded audio goes, and the one thing the cast client needs from the platform.
///
/// It also reports the route, because how deep the jitter buffer has to be depends
/// entirely on what is downstream: Bluetooth brings its own 100-150 ms of transmit
/// buffering, a speaker brings none.
/// </summary>
public interface IAudioSink : IAsyncDisposable
{
    /// <summary>The device's native rate. Feeding anything else inserts a resampler in the path.</summary>
    int SampleRate { get; }

    /// <summary>Where the audio is currently going.</summary>
    AudioRoute Route { get; }

    /// <summary>Raised when the output changes, e.g. headphones connecting mid-stream.</summary>
    event Action<AudioRoute>? RouteChanged;

    /// <param name="sourceName">What is being captured, for anything the platform shows the user.</param>
    Task StartAsync(int channels, string sourceName, CancellationToken cancellationToken);

    /// <summary>
    /// Queues one frame of interleaved float samples. Expected to block when the device
    /// is full, since that is what paces playback.
    /// </summary>
    void Write(ReadOnlySpan<float> frame);

    Task StopAsync();
}
