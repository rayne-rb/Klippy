using Klippy.Shared.Link;

namespace Klippy.Server.Features.Link;

/// <summary>
/// Lets the server itself put an event onto the link, from a background service, an
/// HTTP endpoint, a Blazor page, or an <see cref="IKlippyEventHandler"/> reacting to
/// something else.
/// </summary>
public interface IEventPublisher
{
    /// <summary>
    /// Publishes an envelope: persisted, offered to the server-side handlers, then
    /// routed to the connected devices.
    ///
    /// A handler that publishes in response to an event it also handles will loop.
    /// Emit a different event type than the one being handled.
    /// </summary>
    Task PublishAsync(LinkEnvelope envelope, CancellationToken cancellationToken = default);

    /// <summary>
    /// The same, but delivered to one account's devices only.
    ///
    /// <see cref="PublishAsync"/> reaches every connected device, which is right for the
    /// handful of things that genuinely are server-wide and wrong for everything that
    /// belongs to somebody. When an event describes one account's devices — who is
    /// listening to its audio, what is on its clipboard — this is the one to use.
    /// </summary>
    Task PublishToGroupAsync(
        Guid ownerUserId, LinkEnvelope envelope, CancellationToken cancellationToken = default);
}
