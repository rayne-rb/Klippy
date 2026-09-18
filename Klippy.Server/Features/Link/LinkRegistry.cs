using System.Collections.Concurrent;
using Klippy.Server.Features.Visits;
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

    /// <summary>
    /// Delivers to one device, with no regard for who owns it. Only for envelopes the
    /// server itself produced: a device's own targeted envelope goes through
    /// <see cref="TrySendWithinGroup"/>, which will not cross an account boundary.
    /// </summary>
    public bool SendTo(Guid deviceId, LinkEnvelope envelope)
    {
        if (!_connections.TryGetValue(deviceId, out var connection))
        {
            return false;
        }

        connection.Enqueue(envelope);
        return true;
    }

    /// <summary>
    /// Delivers one device's envelope to another, but only inside the sender's own
    /// account. Returns false when the target is not connected or is not theirs to
    /// address — the caller cannot tell those apart, and should not be able to: a device
    /// that could probe for the existence of another account's devices has already been
    /// told more than it should know.
    ///
    /// A sender with no owner (<paramref name="senderOwner"/> null) can reach nobody. An
    /// unclaimed device is a group of one, so there is no one else in it.
    /// </summary>
    public bool TrySendWithinGroup(Guid deviceId, Guid? senderOwner, LinkEnvelope envelope)
    {
        if (senderOwner is not { } owner)
        {
            return false;
        }

        if (!_connections.TryGetValue(deviceId, out var connection) || connection.OwnerUserId != owner)
        {
            return false;
        }

        connection.Enqueue(envelope);
        return true;
    }

    /// <summary>
    /// Delivers to every connected device, whoever owns them. Reserved for the few
    /// things that really are server-wide; anything carrying one account's business
    /// wants <see cref="BroadcastToGroup"/>.
    /// </summary>
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

    /// <summary>Delivers to one account's devices, optionally skipping the one that caused it.</summary>
    public int BroadcastToGroup(Guid ownerUserId, LinkEnvelope envelope, Guid? exceptDeviceId = null)
    {
        var delivered = 0;

        foreach (var connection in _connections.Values)
        {
            if (connection.OwnerUserId != ownerUserId)
            {
                continue;
            }

            if (exceptDeviceId is { } skip && connection.DeviceId == skip)
            {
                continue;
            }

            connection.Enqueue(envelope);
            delivered++;
        }

        return delivered;
    }

    /// <summary>The account a connected device belongs to, or null if it is unowned or gone.</summary>
    public Guid? OwnerOf(Guid deviceId) =>
        _connections.TryGetValue(deviceId, out var connection) ? connection.OwnerUserId : null;

    /// <summary>
    /// The accounts with at least one device connected. Lets something that has to
    /// announce per group — the audio cast's state, say — know which groups there are.
    /// </summary>
    public IReadOnlyList<Guid> ConnectedGroups() =>
        _connections.Values
            .Select(c => c.OwnerUserId)
            .OfType<Guid>()
            .Distinct()
            .ToList();

    /// <summary>The connected devices belonging to one account.</summary>
    public IReadOnlySet<Guid> DeviceIdsInGroup(Guid ownerUserId) =>
        _connections.Values
            .Where(c => c.OwnerUserId == ownerUserId)
            .Select(c => c.DeviceId)
            .ToHashSet();

    /// <summary>
    /// The other devices a device may know about: the rest of its own account, and
    /// nobody else. An unowned device has no peers.
    /// </summary>
    public IReadOnlyList<DevicePresencePayload> PeersOf(Guid deviceId)
    {
        if (!_connections.TryGetValue(deviceId, out var self) || self.OwnerUserId is not { } owner)
        {
            return [];
        }

        return _connections.Values
            .Where(c => c.DeviceId != deviceId && c.OwnerUserId == owner)
            .Select(c => new DevicePresencePayload
            {
                DeviceId = c.DeviceId.ToString(),
                DeviceKind = c.DeviceKind,
                DeviceName = c.DeviceName,
            })
            .ToList();
    }

    /// <summary>
    /// The Companions on this server that belong to somebody else: who this device could
    /// go and visit. Empty unless the asker is itself a claimed Companion, so a phone and
    /// a device nobody has approved both get nowhere.
    ///
    /// Deliberately not folded into <see cref="PeersOf"/>. A peer is a device of your own
    /// that the link will carry anything to; a friend is a stranger you may knock on and
    /// nothing more, and the two lists exist separately so that difference cannot be lost
    /// by accident. See <see cref="VisitPolicy"/>.
    /// </summary>
    public IReadOnlyList<LinkConnection> CompanionsOutsideAccount(Guid deviceId)
    {
        if (!_connections.TryGetValue(deviceId, out var self)
            || !VisitPolicy.CanTakePart(self.DeviceKind)
            || self.OwnerUserId is not { } owner)
        {
            return [];
        }

        return _connections.Values
            .Where(c => VisitPolicy.CanTakePart(c.DeviceKind)
                        && c.OwnerUserId is { } theirs
                        && theirs != owner)
            .ToList();
    }

    /// <summary>
    /// Carries one Companion's envelope to a Companion in another account — the visit
    /// exception, and the only thing on this server that crosses that line.
    ///
    /// Every condition is re-asked here rather than trusted from the caller, because this
    /// is the method that makes the boundary leak on purpose and it is the last place
    /// anything is checked. <see cref="VisitPolicy"/> says what may cross; this says who
    /// it may cross between. Returns false when the answer is no, for any of the reasons,
    /// which the caller cannot tell apart — the same silence <see cref="TrySendWithinGroup"/>
    /// keeps, and for the same reason.
    /// </summary>
    public bool TryVisitAcrossAccounts(Guid deviceId, Guid senderDeviceId, LinkEnvelope envelope)
    {
        if (!VisitPolicy.MayCrossAccounts(envelope.Type))
        {
            return false;
        }

        if (!_connections.TryGetValue(senderDeviceId, out var sender)
            || !_connections.TryGetValue(deviceId, out var target))
        {
            return false;
        }

        if (!VisitPolicy.CanTakePart(sender.DeviceKind) || !VisitPolicy.CanTakePart(target.DeviceKind))
        {
            return false;
        }

        // Both claimed, and by different people. Same-account delivery is
        // TrySendWithinGroup's job and has already had its turn by the time anything asks
        // this, so a visit between your own two machines never reaches here.
        if (sender.OwnerUserId is not { } from || target.OwnerUserId is not { } to || from == to)
        {
            return false;
        }

        target.Enqueue(envelope);
        return true;
    }
}
