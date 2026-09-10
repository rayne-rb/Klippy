using Android.Content;
using Android.Media;
using Klippy.Mobile.Features.AudioCast;
using Klippy.Shared.Audio;
using AndroidEncoding = Android.Media.Encoding;

namespace Klippy.Mobile.Platforms.Android;

/// <summary>
/// Plays the cast through <see cref="AudioTrack"/> in streaming mode.
///
/// Declaring the stream as Media/Music is what makes Bluetooth work with no Bluetooth
/// code at all: the OS routes Media to whatever output it currently considers active, so
/// speaker, wired and headphones are all the same code path and the user's choice is
/// made in system settings rather than here.
///
/// <para><b>Unverified.</b> Compile-checked against the Android bindings, never run —
/// there is no device attached to this machine. The buffer sizing and the route mapping
/// are the parts most worth distrusting.</para>
/// </summary>
public sealed class AudioTrackSink(ILogger<AudioTrackSink> logger) : IAudioSink
{
    private AudioTrack? _track;
    private AudioManager? _manager;
    private RouteWatcher? _watcher;
    private float[] _scratch = [];
    private int _channels;

    public int SampleRate { get; private set; } = AudioCastFormat.SampleRate;

    public AudioRoute Route { get; private set; } = AudioRoute.Speaker;

    public event Action<AudioRoute>? RouteChanged;

    public Task StartAsync(int channels, string sourceName, CancellationToken cancellationToken)
    {
        // The app supports API 21, but AudioTrack.Builder, float PCM and device
        // enumeration all arrived in 23. Refusing clearly beats crashing on a device from
        // 2015; the rest of the app keeps working there, only the cast does not.
        if (!OperatingSystem.IsAndroidVersionAtLeast(23))
        {
            throw new PlatformNotSupportedException("The audio cast needs Android 6.0 (API 23) or newer.");
        }

        _channels = channels;
        _scratch = new float[AudioCastFormat.SampleCount(channels)];

        _manager = global::Android.App.Application.Context.GetSystemService(Context.AudioService) as AudioManager;
        Route = DetectRoute();

        // Feeding a rate the device does not run at inserts a resampler into the path.
        // Opus only produces 8/12/16/24/48 kHz, so on the rare device that is not 48 kHz
        // the OS resamples for us — worth knowing about, not worth refusing to play over.
        var native = _manager?.GetProperty(AudioManager.PropertyOutputSampleRate);
        if (int.TryParse(native, out var nativeRate) && nativeRate != AudioCastFormat.SampleRate)
        {
            logger.LogWarning(
                "Device output runs at {Native} Hz but the stream is {Stream} Hz; the OS will resample",
                nativeRate, AudioCastFormat.SampleRate);
        }

        var mask = channels == 2 ? ChannelOut.Stereo : ChannelOut.Mono;

        // Exactly the minimum, deliberately. A "safe" multiple is the single easiest way
        // to give away 40 ms or more, and everything upstream exists to protect a budget
        // measured in single-digit milliseconds.
        var bufferBytes = AudioTrack.GetMinBufferSize(AudioCastFormat.SampleRate, mask, AndroidEncoding.PcmFloat);
        if (bufferBytes <= 0)
        {
            throw new InvalidOperationException(
                $"AudioTrack rejected {channels} ch float at {AudioCastFormat.SampleRate} Hz (min buffer {bufferBytes}).");
        }

        var attributes = new AudioAttributes.Builder()
            .SetUsage(AudioUsageKind.Media)!
            .SetContentType(AudioContentType.Music)!
            .Build()!;

        var format = new AudioFormat.Builder()
            .SetEncoding(AndroidEncoding.PcmFloat)!
            .SetSampleRate(AudioCastFormat.SampleRate)!
            .SetChannelMask(mask)!
            .Build()!;

        var builder = new AudioTrack.Builder()
            .SetAudioAttributes(attributes)!
            .SetAudioFormat(format)!
            .SetBufferSizeInBytes(bufferBytes)!
            .SetTransferMode(AudioTrackMode.Stream)!;

        if (OperatingSystem.IsAndroidVersionAtLeast(26))
        {
            // Does nothing on A2DP — Bluetooth output does not use the fast-mixer path —
            // but it is a real win on speaker and wired, so it is asked for regardless.
            builder = builder.SetPerformanceMode(AudioTrackPerformanceMode.LowLatency)!;
        }

        _track = builder.Build();
        _track.Play();

        if (_manager is not null)
        {
            _watcher = new RouteWatcher(OnDevicesChanged);
            _manager.RegisterAudioDeviceCallback(_watcher, null);
        }

        // Started from here rather than from the cast client so that Android's process
        // lifetime stays an Android concern and the client needs no platform branches.
        AudioCastForegroundService.Start(sourceName);

        logger.LogInformation(
            "AudioTrack playing: {Channels} ch float at {Rate} Hz, {Bytes} B buffer " +
            "({Ms:F1} ms), route {Route}",
            channels, AudioCastFormat.SampleRate, bufferBytes,
            bufferBytes / (double)(AudioCastFormat.SampleRate * channels * sizeof(float)) * 1000, Route);

        return Task.CompletedTask;
    }

    public void Write(ReadOnlySpan<float> frame)
    {
        var track = _track;
        if (track is null)
        {
            return;
        }

        // The binding takes an array, so the span is copied into a reusable one rather
        // than allocating per frame at 200 frames a second.
        if (_scratch.Length < frame.Length)
        {
            _scratch = new float[frame.Length];
        }

        frame.CopyTo(_scratch);

        // Blocking on purpose: this is what paces the whole playback loop off the audio
        // hardware's clock instead of a timer that would slowly drift against it.
        track.Write(_scratch, 0, frame.Length, WriteMode.Blocking);
    }

    public Task StopAsync()
    {
        AudioCastForegroundService.Stop();

        if (_watcher is not null && _manager is not null && OperatingSystem.IsAndroidVersionAtLeast(23))
        {
            _manager.UnregisterAudioDeviceCallback(_watcher);
            _watcher = null;
        }

        if (_track is { } track)
        {
            try
            {
                track.Pause();
                track.Flush();
                track.Stop();
            }
            catch (Java.Lang.IllegalStateException ex)
            {
                logger.LogDebug(ex, "AudioTrack was already stopped");
            }

            track.Release();
            track.Dispose();
            _track = null;
        }

        return Task.CompletedTask;
    }

    private void OnDevicesChanged()
    {
        var route = DetectRoute();
        if (route == Route)
        {
            return;
        }

        Route = route;
        logger.LogInformation("Output route changed to {Route}", route);
        RouteChanged?.Invoke(route);
    }

    /// <summary>
    /// Works out what is on the other end, because that decides how much buffering we
    /// have to do ourselves.
    /// </summary>
    private AudioRoute DetectRoute()
    {
        if (!OperatingSystem.IsAndroidVersionAtLeast(23))
        {
            return AudioRoute.Speaker;
        }

        var devices = _manager?.GetDevices(GetDevicesTargets.Outputs);
        if (devices is null)
        {
            return AudioRoute.Speaker;
        }

        var route = AudioRoute.Speaker;

        foreach (var device in devices)
        {
            // A2DP wins if present: it is the one with 100-150 ms of transmit buffering
            // downstream of us, which is the whole reason our own buffer can shrink.
            if (device.Type == AudioDeviceType.BluetoothA2dp)
            {
                return AudioRoute.BluetoothA2dp;
            }

            // LE Audio only exists from API 31.
            if (OperatingSystem.IsAndroidVersionAtLeast(31)
                && device.Type is AudioDeviceType.BleHeadset or AudioDeviceType.BleSpeaker)
            {
                route = AudioRoute.BluetoothLe;
            }
        }

        return route;
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        _manager?.Dispose();
        _manager = null;
    }

    /// <summary>Turns device add/remove callbacks into one "something changed" signal.</summary>
    private sealed class RouteWatcher(Action onChanged) : AudioDeviceCallback
    {
        public override void OnAudioDevicesAdded(AudioDeviceInfo[]? addedDevices) => onChanged();

        public override void OnAudioDevicesRemoved(AudioDeviceInfo[]? removedDevices) => onChanged();
    }
}
