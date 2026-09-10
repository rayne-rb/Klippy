using System.Collections.Concurrent;
using System.Threading.Channels;
using Concentus;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// One encoded frame, ready to put in a datagram.
///
/// The payload is shared by every listener on the same capture: it is encoded once and
/// handed out as-is, never copied per listener. Treat it as immutable.
/// </summary>
public sealed record EncodedAudioFrame(AudioCastPacketHeader Header, ReadOnlyMemory<byte> Payload);

/// <summary>A listener's view of a running capture. Disposing it releases its share.</summary>
public interface IAudioSubscription : IAsyncDisposable
{
    AudioCastStreamFormat Format { get; }

    /// <summary>Frames dropped because this listener could not keep up.</summary>
    long FramesDropped { get; }

    IAsyncEnumerable<EncodedAudioFrame> ReadAllAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Captures, encodes once, and fans out to every listener.
///
/// Capture is shared and ref-counted rather than opened per listener: two phones on the
/// same output means one <c>parec</c> and one encoder, not two of each. A capture is
/// keyed by output *and* channel count, since a mono listener genuinely needs its own
/// encoder, and it lingers briefly after the last listener leaves so that a phone
/// reconnecting across a WiFi blip does not respawn the whole chain.
/// </summary>
public sealed class AudioBroadcaster(
    IEnumerable<IAudioCaptureSourceFactory> factories,
    OpusEncoderPool encoders,
    ILogger<AudioBroadcaster> logger) : IAsyncDisposable
{
    /// <summary>
    /// Long enough to cover a reconnect, short enough that a forgotten cast stops
    /// reading the sink within a few seconds.
    /// </summary>
    private static readonly TimeSpan Linger = TimeSpan.FromSeconds(5);

    /// <summary>~200 ms per listener. Only reached if a listener's sender stalls.</summary>
    private const int ListenerQueueCapacity = 40;

    private readonly ConcurrentDictionary<CaptureKey, CaptureGroup> _groups = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private bool _disposed;

    private readonly record struct CaptureKey(string DeviceId, int Channels);

    /// <summary>What is being captured right now, for the dashboard.</summary>
    public IReadOnlyList<(string DeviceId, string SourceName, int Channels, int Listeners)> Active =>
        _groups.Select(g => (g.Key.DeviceId, g.Value.SourceName, g.Key.Channels, g.Value.ListenerCount)).ToList();

    public async Task<IAudioSubscription> SubscribeAsync(
        string? deviceId,
        int channels,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            throw new ArgumentOutOfRangeException(nameof(channels), channels, "Only mono and stereo are supported.");
        }

        var factory = factories.FirstOrDefault(f => f.IsSupported)
            ?? throw new PlatformNotSupportedException(
                "No audio capture implementation is available for this platform.");

        // Serialised: two phones asking at once must join one capture, not race two into
        // existence.
        await _gate.WaitAsync(cancellationToken);

        try
        {
            var key = new CaptureKey(deviceId ?? string.Empty, channels);

            if (_groups.TryGetValue(key, out var existing))
            {
                return existing.AddListener();
            }

            var source = await factory.OpenAsync(deviceId, channels, cancellationToken);
            var group = new CaptureGroup(source, encoders, logger, () => Release(key));
            _groups[key] = group;

            logger.LogInformation(
                "Casting '{Source}' at {Channels} ch, {Bitrate} bps",
                source.SourceName, channels, AudioCastFormat.BitrateFor(channels));

            return group.AddListener();
        }
        finally
        {
            _gate.Release();
        }
    }

    private void Release(CaptureKey key)
    {
        if (_groups.TryRemove(key, out var group))
        {
            logger.LogInformation("Stopped casting '{Source}'", group.SourceName);
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        foreach (var group in _groups.Values)
        {
            await group.DisposeAsync();
        }

        _groups.Clear();
        _gate.Dispose();
    }

    /// <summary>One capture plus its encoder, shared by the listeners on it.</summary>
    private sealed class CaptureGroup : IAsyncDisposable
    {
        private readonly IAudioCaptureSource _source;
        private readonly OpusEncoderPool _encoders;
        private readonly IOpusEncoder _encoder;
        private readonly ILogger _logger;
        private readonly Action _onEmpty;
        private readonly ConcurrentDictionary<Guid, Listener> _listeners = new();
        private readonly CancellationTokenSource _stopping = new();
        private readonly Task _pump;
        private readonly Lock _lingerGate = new();

        private CancellationTokenSource? _linger;
        private uint _sequence;
        private bool _disposed;

        public CaptureGroup(
            IAudioCaptureSource source,
            OpusEncoderPool encoders,
            ILogger logger,
            Action onEmpty)
        {
            _source = source;
            _encoders = encoders;
            _encoder = encoders.Rent(source.Channels);
            _logger = logger;
            _onEmpty = onEmpty;
            _pump = Task.Run(() => PumpAsync(_stopping.Token));
        }

        public string SourceName => _source.SourceName;

        public int ListenerCount => _listeners.Count;

        public IAudioSubscription AddListener()
        {
            // A listener arriving during the linger window is exactly what the window
            // is for.
            lock (_lingerGate)
            {
                _linger?.Cancel();
                _linger?.Dispose();
                _linger = null;
            }

            var listener = new Listener(this);
            _listeners[listener.Id] = listener;
            return listener;
        }

        private void RemoveListener(Guid id)
        {
            if (!_listeners.TryRemove(id, out _) || !_listeners.IsEmpty)
            {
                return;
            }

            lock (_lingerGate)
            {
                _linger?.Dispose();
                _linger = new CancellationTokenSource();
                var token = _linger.Token;

                _ = Task.Run(async () =>
                {
                    try
                    {
                        await Task.Delay(Linger, token);
                    }
                    catch (OperationCanceledException)
                    {
                        // Someone reconnected. Keep capturing.
                        return;
                    }

                    if (_listeners.IsEmpty)
                    {
                        _onEmpty();
                        await DisposeAsync();
                    }
                }, CancellationToken.None);
            }
        }

        /// <summary>
        /// Reads, encodes, fans out. Timestamps come from the frame count rather than the
        /// wall clock, so scheduling jitter on this side never reaches the listener's
        /// jitter buffer as if it were network jitter.
        /// </summary>
        private async Task PumpAsync(CancellationToken cancellationToken)
        {
            var pcm = new float[AudioCastFormat.SampleCount(_source.Channels)];
            var packet = new byte[AudioCastPacket.MaxPayloadBytes];

            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    if (!await _source.ReadFrameAsync(pcm, cancellationToken))
                    {
                        _logger.LogInformation("Capture of '{Source}' ended", SourceName);
                        break;
                    }

                    var length = _encoder.Encode(
                        pcm, AudioCastFormat.SamplesPerChannel, packet, packet.Length);

                    if (length <= 0)
                    {
                        _logger.LogWarning("Opus returned {Length} for a frame; skipping", length);
                        continue;
                    }

                    var sequence = _sequence++;
                    var frame = new EncodedAudioFrame(
                        new AudioCastPacketHeader(sequence, sequence * AudioCastFormat.FrameMilliseconds),
                        // One allocation per frame, shared by every listener. At ~80 bytes
                        // and 200 frames a second this is ~16 KB/s, three orders of
                        // magnitude below what the managed encoder churns.
                        packet.AsSpan(0, length).ToArray());

                    foreach (var listener in _listeners.Values)
                    {
                        listener.Offer(frame);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Shutting down.
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Casting '{Source}' failed", SourceName);
            }
            finally
            {
                foreach (var listener in _listeners.Values)
                {
                    listener.Complete();
                }
            }
        }

        public async ValueTask DisposeAsync()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            lock (_lingerGate)
            {
                _linger?.Cancel();
                _linger?.Dispose();
                _linger = null;
            }

            await _stopping.CancelAsync();
            await _source.DisposeAsync();

            try
            {
                await _pump.WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch (TimeoutException)
            {
                _logger.LogWarning("Capture pump for '{Source}' did not stop in time", SourceName);
            }

            _encoders.Return(_encoder);
            _stopping.Dispose();
        }

        /// <summary>One listener's queue onto the shared capture.</summary>
        private sealed class Listener(CaptureGroup group) : IAudioSubscription
        {
            private readonly Channel<EncodedAudioFrame> _queue =
                Channel.CreateBounded<EncodedAudioFrame>(new BoundedChannelOptions(ListenerQueueCapacity)
                {
                    // For live audio, falling behind is better answered by staying current
                    // than by delivering frames that are already too late to play.
                    FullMode = BoundedChannelFullMode.DropOldest,
                    SingleReader = true,
                });

            private long _dropped;

            public Guid Id { get; } = Guid.NewGuid();

            public AudioCastStreamFormat Format { get; } = new()
            {
                Channels = group._source.Channels,
                SourceName = group._source.SourceName,
            };

            public long FramesDropped => Interlocked.Read(ref _dropped);

            public void Offer(EncodedAudioFrame frame)
            {
                if (_queue.Writer.TryWrite(frame))
                {
                    return;
                }

                // Either full past DropOldest's help, or completed.
                Interlocked.Increment(ref _dropped);
            }

            public void Complete() => _queue.Writer.TryComplete();

            public IAsyncEnumerable<EncodedAudioFrame> ReadAllAsync(CancellationToken cancellationToken) =>
                _queue.Reader.ReadAllAsync(cancellationToken);

            public ValueTask DisposeAsync()
            {
                Complete();
                group.RemoveListener(Id);
                return ValueTask.CompletedTask;
            }
        }
    }
}
