using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.Visits;

/// <summary>
/// Who each Companion can see to visit, kept up to date on every Companion.
///
/// A visit needs one thing the account boundary will not give it: knowing that somebody
/// else's Klippy is out there. Presence cannot be the answer — <c>device.connected</c> and
/// the welcome's peers stay inside one account on purpose, because that is what the
/// clipboard and the audio relay are routed by, and widening them to make visits work
/// would widen them for everything. So this is a second, much smaller list: for each
/// Companion, the other accounts' Companions, by name, and nothing else about them.
///
/// It is pushed whole rather than patched. The connected set changes a handful of times a
/// day on a home server, a full list cannot drift from the truth the way a stream of
/// add-and-remove can, and a Companion that reconnects gets the same list in its welcome.
///
/// Sent through <see cref="LinkRegistry.SendTo"/> rather than the dispatcher: this is the
/// server's own derived state, so there is no handler to run and nothing worth writing to
/// <c>link_events</c> — the connects and disconnects it is computed from are already there.
/// </summary>
public sealed class VisitNeighborhood(LinkRegistry registry, ILogger<VisitNeighborhood> logger) : IHostedService
{
    /// <summary>
    /// The friends list for one device, as it goes on the wire. Also read by the link's
    /// welcome, so a Companion knows who is about the moment its socket opens.
    /// </summary>
    public IReadOnlyList<VisitNeighborPayload> NeighborsFor(Guid deviceId) =>
        registry.CompanionsOutsideAccount(deviceId)
            .Select(c => new VisitNeighborPayload
            {
                DeviceId = c.DeviceId.ToString(),
                DeviceName = c.DeviceName,
                // Only ever reached for a claimed device; CompanionsOutsideAccount drops
                // the rest, and OwnerName is null exactly when the account id is.
                OwnerName = c.OwnerName ?? string.Empty,
            })
            .ToList();

    public Task StartAsync(CancellationToken cancellationToken)
    {
        registry.ConnectionsChanged += OnConnectionsChanged;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        registry.ConnectionsChanged -= OnConnectionsChanged;
        return Task.CompletedTask;
    }

    /// <summary>
    /// A device came or went, so everyone's friends list may have changed. Recomputed per
    /// Companion because each one's list is "everybody but my own account".
    /// </summary>
    private void OnConnectionsChanged()
    {
        try
        {
            foreach (var connection in registry.Connections)
            {
                if (!VisitPolicy.CanTakePart(connection.DeviceKind) || connection.OwnerUserId is null)
                {
                    continue;
                }

                registry.SendTo(connection.DeviceId, LinkEnvelope.Create(
                    KlippyEvents.VisitNeighbors,
                    new VisitNeighborsPayload { Neighbors = NeighborsFor(connection.DeviceId) }));
            }
        }
        catch (Exception ex)
        {
            // Raised straight from the registry's add and remove: a throw here would take
            // a device's connection or disconnection down with it, over a list that the
            // next change — or the next welcome — puts right anyway.
            logger.LogError(ex, "Could not announce the visit neighbourhood");
        }
    }
}
