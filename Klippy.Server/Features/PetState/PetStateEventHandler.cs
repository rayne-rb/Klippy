using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.PetState;

/// <summary>
/// Keeps <see cref="PetStateStore"/> in step with what the Companion reports.
///
/// This is the shape every server-side reaction takes: implement
/// <see cref="IKlippyEventHandler"/>, register it from the slice, and the dispatcher
/// finds it. Nothing in the link slice knows this one exists.
/// </summary>
public sealed class PetStateEventHandler(PetStateStore store, ILogger<PetStateEventHandler> logger)
    : IKlippyEventHandler
{
    public bool CanHandle(string eventType) => eventType is
        KlippyEvents.PetStats or
        KlippyEvents.PetDied or
        KlippyEvents.PetRevived;

    public Task HandleAsync(LinkEnvelope envelope, CancellationToken cancellationToken)
    {
        switch (envelope.Type)
        {
            case KlippyEvents.PetStats:
                if (envelope.PayloadAs<PetStatsPayload>() is { } stats)
                {
                    store.Update(stats);
                }

                break;

            case KlippyEvents.PetDied:
                logger.LogInformation("The pet died.");
                store.MarkDead();
                break;

            case KlippyEvents.PetRevived:
                logger.LogInformation("The pet was revived.");
                store.MarkRevived();
                break;
        }

        return Task.CompletedTask;
    }
}
