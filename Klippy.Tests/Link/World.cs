using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Microsoft.Extensions.Logging.Abstractions;

namespace Klippy.Tests.Link;

/// <summary>
/// A registry with connections in it, each pumping into a socket we can read.
///
/// Shared by every test about who reaches whom, because that question is always asked
/// the same way: put a few devices on a server, hand one of them an envelope, and see
/// which sockets it lands on.
/// </summary>
public sealed class World : IDisposable
{
    private readonly List<LinkConnection> _connections = [];
    private readonly CancellationTokenSource _cts = new();

    public LinkRegistry Registry { get; } = new(NullLogger<LinkRegistry>.Instance);

    /// <summary>One connected device, as the tests refer to it.</summary>
    public readonly record struct Device(Guid DeviceId, Guid? OwnerUserId, FakeSocket Socket);

    public Device Connect(
        string name,
        Guid? ownerUserId,
        string kind = DeviceKind.Companion,
        string? ownerName = null)
    {
        var socket = new FakeSocket();
        var connection = new LinkConnection(
            Guid.NewGuid(), kind, name, ownerUserId, socket, NullLogger.Instance,
            ownerName ?? (ownerUserId is null ? null : "somebody"));

        Registry.AddAsync(connection).GetAwaiter().GetResult();
        _connections.Add(connection);

        // The send loop is what moves an enqueued envelope onto the socket, which is
        // where these tests observe it.
        _ = connection.RunSendLoopAsync(_cts.Token);

        return new Device(connection.DeviceId, ownerUserId, socket);
    }

    public void Dispose()
    {
        _cts.Cancel();

        foreach (var connection in _connections)
        {
            connection.SignalClosed();
        }

        _cts.Dispose();
    }
}
