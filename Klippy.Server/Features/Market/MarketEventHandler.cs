using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.Market;

/// <summary>
/// The other half of the mailbox payout: a seller who was offline when their item sold
/// gets caught up the moment they reconnect, and the server stops resending once they
/// confirm they applied it.
///
/// Publishing <see cref="KlippyEvents.MarketPayout"/> from inside a handler for
/// <see cref="KlippyEvents.DeviceConnected"/> is safe from the loop <see cref="IEventPublisher"/>
/// warns about: they are different event types, so this handler is never re-entered by
/// its own publish.
/// </summary>
public sealed class MarketEventHandler(MarketRepository repository, IEventPublisher publisher) : IKlippyEventHandler
{
    public bool CanHandle(string eventType) =>
        eventType is KlippyEvents.DeviceConnected or KlippyEvents.MarketPayoutAck;

    public Task HandleAsync(LinkEnvelope envelope, CancellationToken cancellationToken) =>
        envelope.Type == KlippyEvents.MarketPayoutAck
            ? AcknowledgeAsync(envelope, cancellationToken)
            : DeliverPendingPayoutsAsync(envelope, cancellationToken);

    private async Task AcknowledgeAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        var ack = envelope.PayloadAs<MarketPayoutAckPayload>();
        if (ack is null || !Guid.TryParse(ack.PayoutId, out var payoutId))
        {
            return;
        }

        await repository.MarkPayoutDeliveredAsync(payoutId, ct);
    }

    private async Task DeliverPendingPayoutsAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        // The connecting device is the source of its own "device.connected" event
        // (see LinkEndpoints), and is already registered in LinkRegistry by the time
        // handlers run, so a targeted publish here reaches it on this same connect.
        if (!Guid.TryParse(envelope.Source, out var deviceId))
        {
            return;
        }

        var pending = await repository.GetPendingPayoutsAsync(deviceId, ct);
        foreach (var payout in pending)
        {
            await publisher.PublishAsync(LinkEnvelope.Create(
                KlippyEvents.MarketPayout,
                new MarketPayoutPayload
                {
                    PayoutId = payout.PayoutId.ToString(),
                    ItemType = payout.ItemType,
                    Price = payout.Price,
                },
                target: deviceId.ToString()), ct);
        }
    }
}
