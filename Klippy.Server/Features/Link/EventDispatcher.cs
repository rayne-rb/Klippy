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

    public async Task DispatchAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        await PersistAsync(envelope, ct);
        await RunHandlersAsync(envelope, ct);
        Route(envelope);
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
}
