using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;

namespace Klippy.Tests.Link;

/// <summary>
/// A WebSocket that records what was sent to it instead of sending it anywhere.
///
/// <c>LinkConnection</c> needs a real <see cref="WebSocket"/>, and the routing rules are
/// only observable through what each connection ends up being handed — so rather than
/// reach inside the connection, these tests run its send loop against this and read the
/// messages off the other end.
/// </summary>
public sealed class FakeSocket : WebSocket
{
    private readonly Channel<string> _sent = Channel.CreateUnbounded<string>();

    public override WebSocketCloseStatus? CloseStatus => null;
    public override string? CloseStatusDescription => null;
    public override WebSocketState State => WebSocketState.Open;
    public override string? SubProtocol => null;

    public override Task SendAsync(
        ArraySegment<byte> buffer, WebSocketMessageType messageType, bool endOfMessage, CancellationToken ct)
    {
        _sent.Writer.TryWrite(Encoding.UTF8.GetString(buffer.Array!, buffer.Offset, buffer.Count));
        return Task.CompletedTask;
    }

    /// <summary>
    /// The next message, or null if none arrives in time. A null here is the assertion in
    /// most of these tests — "this device was not told" — so the wait has to be long enough
    /// not to pass by accident on a slow machine and short enough to keep the suite quick.
    /// </summary>
    public async Task<string?> NextAsync(TimeSpan? within = null)
    {
        using var timeout = new CancellationTokenSource(within ?? TimeSpan.FromSeconds(2));

        try
        {
            return await _sent.Reader.ReadAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            return null;
        }
    }

    /// <summary>Whether anything at all arrived within a short grace period.</summary>
    public async Task<bool> ReceivedAnythingAsync() =>
        await NextAsync(TimeSpan.FromMilliseconds(250)) is not null;

    public override void Abort()
    {
    }

    public override Task CloseAsync(WebSocketCloseStatus status, string? description, CancellationToken ct) =>
        Task.CompletedTask;

    public override Task CloseOutputAsync(WebSocketCloseStatus status, string? description, CancellationToken ct) =>
        Task.CompletedTask;

    public override Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken ct) =>
        // Nothing in these tests reads from a socket; routing is a send-side concern.
        Task.FromException<WebSocketReceiveResult>(new NotSupportedException());

    public override void Dispose() => _sent.Writer.TryComplete();
}
