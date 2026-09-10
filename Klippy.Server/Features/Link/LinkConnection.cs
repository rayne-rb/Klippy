using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.Link;

/// <summary>
/// One connected device. Sends go through a bounded channel drained by a single writer
/// task, because a WebSocket permits only one send at a time and events can arrive from
/// several sources at once.
/// </summary>
public sealed class LinkConnection : IAsyncDisposable
{
    /// <summary>
    /// Enough headroom for a burst; past this the device is not keeping up and the
    /// oldest events are the ones worth losing, since state-carrying events supersede
    /// their predecessors anyway.
    /// </summary>
    private const int OutboundCapacity = 256;

    private readonly WebSocket _socket;
    private readonly ILogger _logger;
    private readonly Channel<string> _outbound;
    private readonly CancellationTokenSource _closed = new();

    public LinkConnection(
        Guid deviceId,
        string deviceKind,
        string deviceName,
        WebSocket socket,
        ILogger logger)
    {
        DeviceId = deviceId;
        DeviceKind = deviceKind;
        DeviceName = deviceName;
        _socket = socket;
        _logger = logger;
        _outbound = Channel.CreateBounded<string>(new BoundedChannelOptions(OutboundCapacity)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        });
    }

    public Guid DeviceId { get; }

    public string DeviceKind { get; }

    public string DeviceName { get; }

    public DateTimeOffset ConnectedAt { get; } = DateTimeOffset.UtcNow;

    public CancellationToken Closed => _closed.Token;

    /// <summary>Queues an envelope. Never blocks on a slow device.</summary>
    public void Enqueue(LinkEnvelope envelope)
    {
        if (!_outbound.Writer.TryWrite(envelope.ToJson()))
        {
            _logger.LogWarning("Dropped {Type} for {DeviceName}: outbound queue closed", envelope.Type, DeviceName);
        }
    }

    /// <summary>Drains the outbound queue onto the socket until the connection ends.</summary>
    public async Task RunSendLoopAsync(CancellationToken ct)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, _closed.Token);

        try
        {
            await foreach (var message in _outbound.Reader.ReadAllAsync(linked.Token))
            {
                var bytes = Encoding.UTF8.GetBytes(message);
                await _socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, linked.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // Connection closing.
        }
        catch (WebSocketException ex)
        {
            _logger.LogDebug(ex, "Send loop ended for {DeviceName}", DeviceName);
        }
    }

    public void SignalClosed()
    {
        _outbound.Writer.TryComplete();

        if (!_closed.IsCancellationRequested)
        {
            _closed.Cancel();
        }
    }

    public async ValueTask DisposeAsync()
    {
        SignalClosed();

        if (_socket.State == WebSocketState.Open)
        {
            try
            {
                await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "closing", CancellationToken.None);
            }
            catch (WebSocketException)
            {
                // Already gone.
            }
        }

        _closed.Dispose();
        _socket.Dispose();
    }
}
