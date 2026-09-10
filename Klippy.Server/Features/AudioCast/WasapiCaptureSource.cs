using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Threading.Channels;
using Klippy.Shared.Audio;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Captures the system mix on Windows through WASAPI loopback on a render endpoint.
///
/// Loopback on the render device is the same full post-mix output the PipeWire monitor
/// gives on Linux — every application plus system sounds — as opposed to
/// <c>WithProcessLoopback</c>, which is per-process and not what this feature is for.
///
/// Built on <c>WasapiRecorderBuilder</c> rather than the <c>WasapiLoopbackCapture</c>
/// the plan named: that type is obsolete in NAudio.Wasapi 3.1.0, and what replaced it
/// is better suited anyway. <c>WithBufferLength</c> is the direct equivalent of
/// <c>parec --latency-msec</c>, and <c>CaptureAsync</c> is a pull-based
/// <see cref="IAsyncEnumerable{T}"/>, so the old event-to-queue bridge is unnecessary.
///
/// <para><b>Unverified.</b> This machine is Linux, so everything here is compile-checked
/// against the real 3.1.0 API surface but has never been run. The silence handling
/// below is the part most likely to be wrong.</para>
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WasapiCaptureSource : IAudioCaptureSource
{
    /// <summary>
    /// How long to wait with no callbacks before deciding the stream has gone quiet
    /// rather than merely late.
    ///
    /// This is the plan's single most likely Windows bug. WASAPI loopback delivers *no
    /// callbacks at all* while nothing is playing — it does not hand over zeros — so
    /// without synthesised silence the listener's jitter buffer starves the moment the
    /// music pauses. (Linux does not share the problem: a PipeWire monitor keeps
    /// producing zeros.) The threshold is deliberately far longer than any plausible
    /// packet jitter, because injecting a frame that was merely late would insert a
    /// click and permanently shift the stream against the capture clock.
    /// </summary>
    private static readonly TimeSpan SilenceThreshold = TimeSpan.FromMilliseconds(50);

    /// <summary>~200 ms. Only reached if the encoder stalls; drops are counted, not silent.</summary>
    private const int FrameQueueCapacity = 40;

    private readonly WasapiRecorder _recorder;
    private readonly Channel<float[]> _frames;
    private readonly ConcurrentQueue<float[]> _pool = new();
    private readonly CancellationTokenSource _stopping = new();
    private readonly byte[] _partialFrame;
    private readonly ILogger _logger;
    private readonly Task _pump;
    private readonly Task _silenceKeeper;

    private int _partialFilled;
    private long _lastDataTicks;
    private long _framesEmitted;
    private long _silentFramesInjected;
    private long _framesDropped;
    private long _discontinuities;
    private bool _disposed;

    private WasapiCaptureSource(WasapiRecorder recorder, int channels, string sourceName, ILogger logger)
    {
        _recorder = recorder;
        Channels = channels;
        SourceName = sourceName;
        _logger = logger;
        _partialFrame = new byte[AudioCastFormat.FrameBytes(channels)];

        _frames = Channel.CreateBounded<float[]>(new BoundedChannelOptions(FrameQueueCapacity)
        {
            // Live audio: if the encoder cannot keep up, staying current matters more
            // than replaying what is already too late to be useful.
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        });

        Volatile.Write(ref _lastDataTicks, Environment.TickCount64);

        _pump = Task.Run(() => PumpAsync(_stopping.Token));
        _silenceKeeper = Task.Run(() => KeepSilenceAsync(_stopping.Token));
    }

    public int Channels { get; }

    public string SourceName { get; }

    /// <summary>Frames synthesised because WASAPI stopped calling back. Expected to be non-zero whenever playback pauses.</summary>
    public long SilentFramesInjected => Interlocked.Read(ref _silentFramesInjected);

    public long FramesDropped => Interlocked.Read(ref _framesDropped);

    public static Task<WasapiCaptureSource> StartAsync(
        string? deviceId,
        int channels,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("WASAPI capture requires Windows.");
        }

        using var enumerator = new MMDeviceEnumerator();

        var device = deviceId is null
            ? enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia)
            : enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
                  .FirstOrDefault(d => d.ID == deviceId)
              ?? throw new InvalidOperationException($"Output '{deviceId}' is not available.");

        var requested = WaveFormat.CreateIeeeFloatWaveFormat(AudioCastFormat.SampleRate, channels);

        var recorder = new WasapiRecorderBuilder()
            .WithDevice(device)
            .WithLoopbackCapture()
            .WithSharedMode()
            // Event-driven rather than polled: the buffer is handed over as soon as the
            // device has it instead of on our own poll interval.
            .WithEventSync()
            .WithBufferLength(AudioCastFormat.FrameMilliseconds)
            .WithFormat(requested)
            // Asked for, not required: on a machine that cannot provide it we would
            // rather stream at ordinary latency than refuse to stream.
            .WithLowLatency(required: false)
            // Windows deprioritises ordinary threads badly enough to cause dropouts;
            // MMCSS is what audio software uses to avoid it.
            .WithMmcssThreadPriority("Pro Audio")
            .Build();

        var actual = recorder.WaveFormat;
        var sourceName = device.FriendlyName;
        device.Dispose();

        // Shared-mode loopback yields the endpoint's mix format. Opus only runs at
        // 8/12/16/24/48 kHz, so a 44.1 kHz endpoint needs a resampler that does not
        // exist here yet. Fail clearly rather than stream audio at the wrong rate.
        if (actual.SampleRate != AudioCastFormat.SampleRate
            || actual.Channels != channels
            || actual.Encoding != WaveFormatEncoding.IeeeFloat)
        {
            recorder.Dispose();
            throw new NotSupportedException(
                $"'{sourceName}' captures as {actual.Encoding} {actual.SampleRate} Hz {actual.Channels} ch, " +
                $"but this build needs IeeeFloat {AudioCastFormat.SampleRate} Hz {channels} ch. " +
                "Set the endpoint to 48 kHz in Windows sound settings, or add a resampler.");
        }

        logger.LogInformation(
            "WASAPI loopback on '{Source}': {Latency} ms buffer, low-latency {LowLatency}{Reason}",
            sourceName, recorder.LatencyMilliseconds, recorder.LowLatencyActive,
            recorder.LowLatencyActive ? string.Empty : $" ({recorder.LowLatencyUnavailableReason})");

        var source = new WasapiCaptureSource(recorder, channels, sourceName, logger);
        recorder.StartRecording();

        return Task.FromResult(source);
    }

    public async ValueTask<bool> ReadFrameAsync(Memory<float> frame, CancellationToken cancellationToken)
    {
        var expected = AudioCastFormat.SampleCount(Channels);
        if (frame.Length != expected)
        {
            throw new ArgumentException($"Expected a {expected}-sample frame, got {frame.Length}.", nameof(frame));
        }

        try
        {
            var produced = await _frames.Reader.ReadAsync(cancellationToken);
            produced.CopyTo(frame.Span);
            _pool.Enqueue(produced);
            return true;
        }
        catch (ChannelClosedException)
        {
            return false;
        }
    }

    /// <summary>
    /// Drains WASAPI into whole frames.
    ///
    /// WASAPI hands over device-period buffers, which have no reason to be a multiple
    /// of 5 ms, so unlike the Linux path this really does have to reframe. That is
    /// what <see cref="_partialFrame"/> carries across callbacks.
    /// </summary>
    private async Task PumpAsync(CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var buffer in _recorder.CaptureAsync(cancellationToken))
            {
                Volatile.Write(ref _lastDataTicks, Environment.TickCount64);

                if (buffer.Flags.HasFlag(AudioClientBufferFlags.DataDiscontinuity))
                {
                    // The device dropped something. Nothing to do but note it: the
                    // listener's concealment is what covers the gap.
                    Interlocked.Increment(ref _discontinuities);
                }

                // WASAPI marks a silent buffer rather than bothering to zero it, so the
                // contents are undefined and must not be forwarded as audio.
                var silent = buffer.Flags.HasFlag(AudioClientBufferFlags.Silent);
                Append(buffer.Data.Span, silent);
            }
        }
        catch (OperationCanceledException)
        {
            // Shutting down.
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "WASAPI capture of '{Source}' failed", SourceName);
        }
        finally
        {
            _frames.Writer.TryComplete();
        }
    }

    private void Append(ReadOnlySpan<byte> source, bool silent)
    {
        var offset = 0;

        while (offset < source.Length)
        {
            var take = Math.Min(_partialFrame.Length - _partialFilled, source.Length - offset);
            var destination = _partialFrame.AsSpan(_partialFilled, take);

            if (silent)
            {
                destination.Clear();
            }
            else
            {
                source.Slice(offset, take).CopyTo(destination);
            }

            _partialFilled += take;
            offset += take;

            if (_partialFilled == _partialFrame.Length)
            {
                Emit(MemoryMarshal.Cast<byte, float>(_partialFrame));
                _partialFilled = 0;
            }
        }
    }

    /// <summary>
    /// Feeds silence at frame rate once the device has gone quiet.
    ///
    /// Pacing matters as much as the silence itself: one frame per starvation timeout
    /// would still leave the listener 10x short of real time. Once quiet, this produces
    /// a frame every 5 ms, exactly as capture would have.
    /// </summary>
    private async Task KeepSilenceAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(AudioCastFormat.FrameMilliseconds));

        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                var quietFor = Environment.TickCount64 - Volatile.Read(ref _lastDataTicks);
                if (quietFor < SilenceThreshold.TotalMilliseconds)
                {
                    continue;
                }

                // Only when the listener would otherwise starve: real audio still
                // queued means there is nothing to paper over.
                if (_frames.Reader.Count > 0)
                {
                    continue;
                }

                var frame = Rent();
                Array.Clear(frame);

                if (_frames.Writer.TryWrite(frame))
                {
                    Interlocked.Increment(ref _silentFramesInjected);
                }
                else
                {
                    _pool.Enqueue(frame);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Shutting down.
        }
    }

    private void Emit(ReadOnlySpan<float> samples)
    {
        var frame = Rent();
        samples.CopyTo(frame);

        if (_frames.Writer.TryWrite(frame))
        {
            Interlocked.Increment(ref _framesEmitted);
        }
        else
        {
            Interlocked.Increment(ref _framesDropped);
            _pool.Enqueue(frame);
        }
    }

    /// <summary>
    /// Recycles frame buffers. At 200 frames a second, allocating one per frame is the
    /// kind of steady churn that turns into a GC pause in the middle of a stream.
    /// </summary>
    private float[] Rent() =>
        _pool.TryDequeue(out var buffer) ? buffer : new float[AudioCastFormat.SampleCount(Channels)];

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        await _stopping.CancelAsync();

        try
        {
            _recorder.StopRecording();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "StopRecording threw during shutdown");
        }

        await Task.WhenAll(_pump, _silenceKeeper).WaitAsync(TimeSpan.FromSeconds(2));

        _logger.LogInformation(
            "WASAPI capture of '{Source}' ended: {Frames} frames, {Silent} silent injected, " +
            "{Dropped} dropped, {Gaps} device discontinuities",
            SourceName, _framesEmitted, SilentFramesInjected, FramesDropped,
            Interlocked.Read(ref _discontinuities));

        await _recorder.DisposeAsync();
        _stopping.Dispose();
    }
}

/// <summary>Opens <see cref="WasapiCaptureSource"/> instances. Windows only.</summary>
public sealed class WasapiCaptureSourceFactory(ILogger<WasapiCaptureSource> logger) : IAudioCaptureSourceFactory
{
    public bool IsSupported => OperatingSystem.IsWindows();

    public Task<IAudioCaptureSource> OpenAsync(
        string? deviceId,
        int channels,
        CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("WASAPI capture requires Windows.");
        }

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            throw new ArgumentOutOfRangeException(nameof(channels), channels, "Only mono and stereo are supported.");
        }

        return Cast(WasapiCaptureSource.StartAsync(deviceId, channels, logger, cancellationToken));

        static async Task<IAudioCaptureSource> Cast(Task<WasapiCaptureSource> task) => await task;
    }
}

/// <summary>Lists active WASAPI render endpoints.</summary>
[SupportedOSPlatform("windows")]
public sealed class WasapiSourceCatalog(ILogger<WasapiSourceCatalog> logger) : IAudioSourceCatalog
{
    public Task<IReadOnlyList<AudioOutputDevice>> ListAsync(CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("WASAPI enumeration requires Windows.");
        }

        try
        {
            using var enumerator = new MMDeviceEnumerator();

            string? defaultId = null;
            try
            {
                using var @default = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
                defaultId = @default.ID;
            }
            catch (COMException)
            {
                // A machine with no active output at all. The list below will be empty.
            }

            var devices = new List<AudioOutputDevice>();

            foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                using (device)
                {
                    devices.Add(new AudioOutputDevice
                    {
                        Id = device.ID,
                        Name = device.FriendlyName,
                        IsDefault = device.ID == defaultId,
                    });
                }
            }

            return Task.FromResult<IReadOnlyList<AudioOutputDevice>>(devices);
        }
        catch (COMException ex)
        {
            logger.LogWarning(ex, "Could not enumerate WASAPI render endpoints");
            return Task.FromResult<IReadOnlyList<AudioOutputDevice>>([]);
        }
    }
}
