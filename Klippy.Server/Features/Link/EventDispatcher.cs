using Klippy.Shared.Link;

namespace Klippy.Server.Features.Link;

/// <summary>
/// The one path every event takes, whichever end it came from.
///
/// Order matters: persist first so nothing is lost if a handler throws, then let the
/// server's own slices react, then fan out to devices. Handlers run before delivery so
/// a slice can act on an event in the same beat the devices see it.
/// </summary>
public sealed class EventDispatcher(
    LinkRegistry registry,
    IServiceScopeFactory scopeFactory,
    ILogger<EventDispatcher> logger) : IEventPublisher
{
    public Task PublishAsync(LinkEnvelope envelope, CancellationToken cancellationToken = default) =>
        DispatchAsync(envelope, cancellationToken);

    public async Task PublishToGroupAsync(
        Guid ownerUserId, LinkEnvelope envelope, CancellationToken cancellationToken = default)
    {
        await PersistAsync(envelope, cancellationToken);
        await RunHandlersAsync(envelope, cancellationToken);
        registry.BroadcastToGroup(ownerUserId, envelope);
    }

    /// <summary>
    /// An envelope the server itself produced. It is trusted: a target is delivered to
    /// whoever it names, and an untargeted one reaches every connected device.
    /// </summary>
    public async Task DispatchAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        await PersistAsync(envelope, ct);
        await RunHandlersAsync(envelope, ct);
        Route(envelope);
    }

    /// <summary>
    /// An envelope a device sent us, routed inside that device's own account and no
    /// further.
    ///
    /// <paramref name="senderOwner"/> comes from the authenticated connection, never from
    /// the envelope: a device saying which group it is in is a device choosing its own
    /// audience. Passed in rather than looked up because the presence events are
    /// dispatched either side of the connection being in the registry at all.
    /// </summary>
    public async Task DispatchFromDeviceAsync(
        LinkEnvelope envelope, Guid? senderOwner, CancellationToken ct)
    {
        await PersistAsync(envelope, ct);
        await RunHandlersAsync(envelope, ct);
        RouteFromDevice(envelope, senderOwner);
    }

    private async Task PersistAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        // Keepalives are noise; everything else is worth a row.
        if (envelope.Type is KlippyEvents.LinkPing or KlippyEvents.LinkPong)
        {
            return;
        }

        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var events = scope.ServiceProvider.GetRequiredService<LinkEventRepository>();
            await events.AppendAsync(envelope, ct);
        }
        catch (Exception ex)
        {
            // The link is more important than its audit trail: log and keep going.
            logger.LogError(ex, "Could not record {Type}", envelope.Type);
        }
    }

    private async Task RunHandlersAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var handlers = scope.ServiceProvider.GetServices<IKlippyEventHandler>();

        foreach (var handler in handlers)
        {
            if (!handler.CanHandle(envelope.Type))
            {
                continue;
            }

            try
            {
                await handler.HandleAsync(envelope, ct);
            }
            catch (Exception ex)
            {
                // Contained on purpose: one bad handler must not cost the other
                // handlers their turn, nor the devices their event.
                logger.LogError(ex, "{Handler} failed on {Type}", handler.GetType().Name, envelope.Type);
            }
        }
    }

    private void Route(LinkEnvelope envelope)
    {
        var source = Guid.TryParse(envelope.Source, out var parsedSource) ? parsedSource : (Guid?)null;

        if (Guid.TryParse(envelope.Target, out var target))
        {
            if (!registry.SendTo(target, envelope))
            {
                logger.LogDebug("{Type} addressed to {Target}, which is not connected", envelope.Type, target);
            }

            return;
        }

        // No target means everyone but the sender: a device does not need its own
        // event handed back to it.
        registry.Broadcast(envelope, source);
    }

    private void RouteFromDevice(LinkEnvelope envelope, Guid? senderOwner)
    {
        var source = Guid.TryParse(envelope.Source, out var parsedSource) ? parsedSource : (Guid?)null;

        if (Guid.TryParse(envelope.Target, out var target))
        {
            if (registry.TrySendWithinGroup(target, senderOwner, envelope))
            {
                return;
            }

            // Inside the account first, then the one way out of it. A visit is aimed at
            // somebody else's monitor by definition, so it is tried here rather than
            // refused — on the registry's terms, which are narrow: a visit event, between
            // two claimed Companions, and nothing else (see VisitPolicy).
            if (source is { } sender && registry.TryVisitAcrossAccounts(target, sender, envelope))
            {
                return;
            }

            // Deliberately one message for both "offline" and "not yours to address".
            // Telling them apart would let a device map out the rest of the server.
            logger.LogDebug(
                "{Type} addressed to {Target}, which is not reachable from this device",
                envelope.Type, target);

            return;
        }

        if (senderOwner is not { } owner)
        {
            // An unclaimed device is a group of one, so an untargeted event from it has
            // nowhere to go. It is still persisted and still ran through the handlers
            // above, which is what makes a device usable before anyone approves it.
            logger.LogDebug("{Type} from an unowned device reaches nobody", envelope.Type);
            return;
        }

        registry.BroadcastToGroup(owner, envelope, source);
    }
}
