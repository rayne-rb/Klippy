using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using Klippy.Mobile.Features.Link;
using Klippy.Mobile.Features.Pairing;
using Klippy.Shared;
using Klippy.Shared.Audio;
using Klippy.Shared.Link;

namespace Klippy.Mobile.Features.AudioCast;

/// <summary>
/// The phone's end of the cast: ask over the Link, prove the key over UDP, then decode
/// and play what arrives.
///
/// Control and media are deliberately split. The Link is authenticated, ordered and
/// reliable, which is what negotiation needs; the audio wants none of that, because a
/// retransmit only ever delivers a frame that is already too late to play.
///
/// Playback is paced by the sink rather than by a timer: the device's write blocks when
/// its buffer is full, so the audio hardware's own clock drives the loop and there is no
/// second clock to drift against it.
/// </summary>
public sealed class AudioCastClient(
    KlippyLinkClient link,
    PairedServerStore store,
    IAudioSink sink,
    ILogger<AudioCastClient> logger) : IAsyncDisposable
{
    private readonly Stopwatch _clock = Stopwatch.StartNew();

    private CancellationTokenSource? _stopping;
    private TaskCompletionSource<AudioCastOfferPayload>? _pendingOffer;
    private AdaptiveJitterBuffer? _buffer;
    private Task? _receiving;
    private Task? _playing;
    private Task? _keepalive;

    /// <summary>True while audio is being received and played.</summary>
    public bool IsCasting { get; private set; }

    public AdaptiveJitterBuffer? Buffer => _buffer;

    public event Action<bool>? CastingChanged;

    /// <summary>
    /// Asks the server to cast here and waits for the offer that carries the key.
    /// </summary>
    public async Task<bool> StartAsync(int channels = 2, string? outputDeviceId = null)
    {
        if (IsCasting)
        {
            return true;
        }

        var server = await store.GetAsync();
        if (server is null)
        {
            logger.LogWarning("Cannot cast: this phone is not paired with a server yet");
            return false;
        }

        _pendingOffer = new TaskCompletionSource<AudioCastOfferPayload>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        link.EventReceived += OnLinkEvent;

        try
        {
            link.Publish(KlippyEvents.AudioCastStart, new AudioCastStartPayload
            {
                Channels = channels,
                DeviceId = outputDeviceId,
            });

            // A capture that cannot open never answers, so this cannot wait forever.
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var offer = await _pendingOffer.Task.WaitAsync(timeout.Token);

            await BeginAsync(new Uri(server.BaseUrl).Host, offer);
            return true;
        }
        catch (OperationCanceledException)
        {
            logger.LogWarning("The server did not offer a stream within 10s");
            return false;
        }
        finally
        {
            link.EventReceived -= OnLinkEvent;
            _pendingOffer = null;
        }
    }

    public async Task StopAsync()
    {
        if (!IsCasting)
        {
            return;
        }

        link.Publish(KlippyEvents.AudioCastStop);
        await TearDownAsync();
    }

    private void OnLinkEvent(LinkEnvelope envelope)
    {
        if (envelope.Type != KlippyEvents.AudioCastOffer)
        {
            return;
        }

        if (envelope.PayloadAs<AudioCastOfferPayload>() is { } offer)
        {
            _pendingOffer?.TrySetResult(offer);
        }
    }

    private async Task BeginAsync(string host, AudioCastOfferPayload offer)
    {
        var addresses = await Dns.GetHostAddressesAsync(host);
        var endpoint = new IPEndPoint(
            addresses.First(a => a.AddressFamily == AddressFamily.InterNetwork), offer.UdpPort);

        await sink.StartAsync(offer.Format.Channels, offer.Format.SourceName, CancellationToken.None);

        _buffer = new AdaptiveJitterBuffer(sink.Route);
        sink.RouteChanged += OnRouteChanged;

        _stopping = new CancellationTokenSource();
        var token = _stopping.Token;

        var udp = new UdpClient(new IPEndPoint(IPAddress.Any, 0));
        var hello = Encoding.UTF8.GetBytes(KlippyJson.Serialize(new AudioCastHello
        {
            StreamKey = offer.StreamKey,
        }));

        await udp.SendAsync(hello, endpoint, token);

        IsCasting = true;
        CastingChanged?.Invoke(true);

        logger.LogInformation(
            "Casting '{Source}' at {Channels} ch from {Endpoint}, route {Route}, target {Target} ms",
            offer.Format.SourceName, offer.Format.Channels, endpoint, sink.Route, _buffer.TargetMs);

        _receiving = Task.Run(() => ReceiveAsync(udp, token), CancellationToken.None);
        _keepalive = Task.Run(() => KeepAliveAsync(udp, endpoint, hello, token), CancellationToken.None);
        _playing = Task.Run(() => Play(offer.Format, token), CancellationToken.None);
    }

    /// <summary>Takes datagrams off the socket and hands them to the buffer, in whatever order they turn up.</summary>
    private async Task ReceiveAsync(UdpClient udp, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var received = await udp.ReceiveAsync(cancellationToken);

                if (AudioCastPacket.TryRead(received.Buffer, out var header, out var payload))
                {
                    // Copied because the buffer holds it past this iteration.
                    _buffer?.Push(header, payload.ToArray(), _clock.ElapsedMilliseconds);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Cast ending.
        }
        catch (SocketException ex)
        {
            logger.LogWarning(ex, "Audio socket failed");
        }
        finally
        {
            udp.Dispose();
        }
    }

    /// <summary>
    /// Repeats the hello. Also what makes the stream survive the phone changing network:
    /// the server takes the address from whichever hello it last saw.
    /// </summary>
    private async Task KeepAliveAsync(
        UdpClient udp,
        IPEndPoint endpoint,
        byte[] hello,
        CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(AudioCastTransport.HelloInterval);

        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                await udp.SendAsync(hello, endpoint, cancellationToken);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or SocketException or ObjectDisposedException)
        {
            // Cast ending, or the socket has already gone.
        }
    }

    /// <summary>
    /// The playback loop. Every slot gets a frame — real, concealed, or silence — because
    /// the one thing that must not happen is handing the device nothing.
    /// </summary>
    private void Play(AudioCastStreamFormat format, CancellationToken cancellationToken)
    {
        using var decoder = new OpusStreamDecoder(format.SampleRate, format.Channels);

        while (!cancellationToken.IsCancellationRequested)
        {
            var buffer = _buffer;
            if (buffer is null)
            {
                break;
            }

            var frame = buffer.Next();

            var pcm = frame.Action switch
            {
                JitterBufferAction.Play => decoder.Decode(frame.Payload.Span),
                JitterBufferAction.Conceal => decoder.Conceal(),
                _ => decoder.Silence(),
            };

            // Blocks when the device is full, which is what keeps this loop at real time.
            sink.Write(pcm);
        }

        logger.LogInformation(
            "Playback ended: {Decoded} decoded, {Concealed} concealed", decoder.Decoded, decoder.Concealed);
    }

    /// <summary>
    /// Rebuilds the buffer for the new route. Plugging in headphones mid-stream changes
    /// how much buffering sits downstream of us, and therefore how much we should hold.
    /// </summary>
    private void OnRouteChanged(AudioRoute route)
    {
        logger.LogInformation("Output route is now {Route}; retargeting the jitter buffer", route);
        _buffer = new AdaptiveJitterBuffer(route);
    }

    private async Task TearDownAsync()
    {
        sink.RouteChanged -= OnRouteChanged;

        if (_stopping is { } stopping)
        {
            await stopping.CancelAsync();
        }

        foreach (var task in new[] { _receiving, _keepalive, _playing })
        {
            if (task is null)
            {
                continue;
            }

            try
            {
                await task.WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch (Exception ex) when (ex is TimeoutException or OperationCanceledException)
            {
                // Nothing useful left to do about it during teardown.
            }
        }

        await sink.StopAsync();

        _stopping?.Dispose();
        _stopping = null;
        _receiving = _keepalive = _playing = null;
        _buffer = null;

        IsCasting = false;
        CastingChanged?.Invoke(false);
    }

    public async ValueTask DisposeAsync()
    {
        await TearDownAsync();
        await sink.DisposeAsync();
    }
}
