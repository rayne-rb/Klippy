using Klippy.Server.Features.Link;
using Klippy.Shared.Clipboard;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// Keeps <see cref="ClipboardSessions"/> in step with what the devices say.
///
/// Nothing here routes or stores an entry — that is all HTTP, in
/// <see cref="ClipboardEndpoints"/>. This is only the bookkeeping behind "who has the
/// skill on", which the server's own page shows and which nothing else depends on.
/// </summary>
public sealed class ClipboardEventHandler(
    ClipboardSessions sessions,
    LinkRegistry registry) : IKlippyEventHandler
{
    public bool CanHandle(string eventType) =>
        eventType is KlippyEvents.ClipboardSharing or KlippyEvents.DeviceDisconnected;

    public Task HandleAsync(LinkEnvelope envelope, CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(envelope.Source, out var deviceId))
        {
            return Task.CompletedTask;
        }

        if (envelope.Type == KlippyEvents.DeviceDisconnected)
        {
            // A device that is not here is not sharing. Its own switch is remembered on
            // the device, and it says so again on the next connect.
            sessions.Forget(deviceId);
            return Task.CompletedTask;
        }

        if (envelope.PayloadAs<ClipboardSharingPayload>() is not { } sharing)
        {
            return Task.CompletedTask;
        }

        sessions.Set(
            deviceId,
            registry.OwnerOf(deviceId),
            DeviceNameOf(deviceId),
            sharing.Enabled,
            sharing.Visibility);

        return Task.CompletedTask;
    }

    /// <summary>The connected device's name, or its id when it has already gone.</summary>
    private string DeviceNameOf(Guid deviceId) =>
        registry.Connections.FirstOrDefault(c => c.DeviceId == deviceId)?.DeviceName
        ?? deviceId.ToString();
}
