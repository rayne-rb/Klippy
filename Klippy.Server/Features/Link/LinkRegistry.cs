using System.Collections.Concurrent;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.Link;

/// <summary>
/// Who is currently connected, and how to reach them. A device that reconnects
/// displaces its previous connection rather than doubling up, which is what happens
/// in practice when a phone's socket dies without a close frame.
/// </summary>
public sealed class LinkRegistry(ILogger<LinkRegistry> logger)
{
    private readonly ConcurrentDictionary<Guid, LinkConnection> _connections = new();

    /// <summary>Fires whenever the connected set changes, for the live view in the UI.</summary>
    public event Action? ConnectionsChanged;

    public IReadOnlyCollection<LinkConnection> Connections => _connections.Values.ToList();

    public bool IsConnected(Guid deviceId) => _connections.ContainsKey(deviceId);

    /// <summary>Registers a connection, evicting any earlier one for the same device.</summary>
    public async Task AddAsync(LinkConnection connection)
    {
        if (_connections.TryRemove(connection.DeviceId, out var previous))
        {
            logger.LogInformation("Replacing an existing connection for {DeviceName}", previous.DeviceName);
            previous.SignalClosed();
            await previous.DisposeAsync();
        }

        _connections[connection.DeviceId] = connection;
        logger.LogInformation("{DeviceKind} '{DeviceName}' connected ({Count} online)",
            connection.DeviceKind, connection.DeviceName, _connections.Count);

        ConnectionsChanged?.Invoke();
    }

    public void Remove(LinkConnection connection)
    {
        // Only remove if it is still the current one: a reconnect may have replaced it.
        if (_connections.TryGetValue(connection.DeviceId, out var current) && ReferenceEquals(current, connection))
        {
            _connections.TryRemove(connection.DeviceId, out _);
            logger.LogInformation("{DeviceKind} '{DeviceName}' disconnected ({Count} online)",
                connection.DeviceKind, connection.DeviceName, _connections.Count);
            ConnectionsChanged?.Invoke();
        }
    }

    /// <summary>Hangs up on a device, if it is connected. Used when access is withdrawn.</summary>
    public async Task DisconnectAsync(Guid deviceId)
    {
        if (!_connections.TryRemove(deviceId, out var connection))
        {
            return;
        }

        logger.LogInformation("Dropping '{DeviceName}': access was withdrawn", connection.DeviceName);
        connection.SignalClosed();
        await connection.DisposeAsync();
        ConnectionsChanged?.Invoke();
    }

    /// <summary>Delivers to one device. Returns false when it is not connected.</summary>
    public bool SendTo(Guid deviceId, LinkEnvelope envelope)
    {
        if (!_connections.TryGetValue(deviceId, out var connection))
        {
            return false;
        }

        connection.Enqueue(envelope);
        return true;
    }

    /// <summary>Delivers to everyone except the device that produced it.</summary>
    public int Broadcast(LinkEnvelope envelope, Guid? exceptDeviceId = null)
    {
        var delivered = 0;

        foreach (var connection in _connections.Values)
        {
            if (exceptDeviceId is { } skip && connection.DeviceId == skip)
            {
                continue;
            }

            connection.Enqueue(envelope);
            delivered++;
        }

        return delivered;
    }

    public IReadOnlyList<DevicePresencePayload> PeersOf(Guid deviceId) =>
        _connections.Values
            .Where(c => c.DeviceId != deviceId)
            .Select(c => new DevicePresencePayload
            {
                DeviceId = c.DeviceId.ToString(),
                DeviceKind = c.DeviceKind,
                DeviceName = c.DeviceName,
            })
            .ToList();
}
