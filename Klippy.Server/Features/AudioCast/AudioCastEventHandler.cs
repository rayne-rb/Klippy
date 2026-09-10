using Klippy.Server.Features.Link;
using Klippy.Shared.Audio;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Turns <c>audio.cast.*</c> control events into captures.
///
/// Control lives on the Link because that socket already has authentication, delivery
/// and fan-out; only the bytes need their own transport. This is the shape every
/// server-side reaction takes — implement <see cref="IKlippyEventHandler"/>, register it
/// from the slice, and the dispatcher finds it.
/// </summary>
public sealed class AudioCastEventHandler(
    AudioBroadcaster broadcaster,
    AudioCastSessions sessions,
    AudioCastUdpServer udp,
    LinkRegistry registry,
    ILogger<AudioCastEventHandler> logger) : IKlippyEventHandler
{
    public bool CanHandle(string eventType) => eventType is
        KlippyEvents.AudioCastStart or
        KlippyEvents.AudioCastStop or
        // A phone that closes the app never says stop. Without this its capture would
        // keep running until the hello timeout noticed.
        KlippyEvents.DeviceDisconnected;

    public async Task HandleAsync(LinkEnvelope envelope, CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(envelope.Source, out var deviceId))
        {
            logger.LogWarning("{Type} arrived without a usable source device", envelope.Type);
            return;
        }

        switch (envelope.Type)
        {
            case KlippyEvents.AudioCastStart:
                await StartAsync(deviceId, envelope, cancellationToken);
                break;

            case KlippyEvents.AudioCastStop:
            case KlippyEvents.DeviceDisconnected:
                await sessions.StopAsync(deviceId);
                break;
        }
    }

    private async Task StartAsync(Guid deviceId, LinkEnvelope envelope, CancellationToken cancellationToken)
    {
        var request = envelope.PayloadAs<AudioCastStartPayload>() ?? new AudioCastStartPayload();
        var deviceName = registry.Connections.FirstOrDefault(c => c.DeviceId == deviceId)?.DeviceName
            ?? deviceId.ToString();

        // Deliberately unguarded: a capture that cannot open throws, the dispatcher
        // contains and logs it, and the requester's wait for an offer times out. Worth
        // improving once there is a place to put a targeted failure.
        var subscription = await broadcaster.SubscribeAsync(request.DeviceId, request.Channels, cancellationToken);

        var session = sessions.Create(
            deviceId, deviceName, subscription, request.DeviceId, subscription.Format.SourceName);

        var offer = LinkEnvelope.Create(
            KlippyEvents.AudioCastOffer,
            new AudioCastOfferPayload
            {
                UdpPort = udp.Port,
                StreamKey = session.StreamKey,
                Format = subscription.Format,
            },
            target: deviceId.ToString());

        // Sent straight to the one device rather than published. Publishing would put an
        // ephemeral credential into link_events for good, and this message needs none of
        // what the dispatcher adds — no history, no fan-out, no server-side handlers.
        if (!registry.SendTo(deviceId, offer))
        {
            logger.LogWarning("'{Device}' asked to cast but is no longer connected", deviceName);
            await sessions.StopAsync(deviceId);
            return;
        }

        logger.LogInformation(
            "Offered '{Source}' to '{Device}' at {Channels} ch on UDP {Port}",
            subscription.Format.SourceName, deviceName, subscription.Format.Channels, udp.Port);
    }
}
