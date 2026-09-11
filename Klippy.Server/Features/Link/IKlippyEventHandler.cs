using Klippy.Shared.Link;

namespace Klippy.Server.Features.Link;

/// <summary>
/// How a feature slice reacts to something that happened on a device.
///
/// Implementations are resolved per event from a fresh scope, so they can take scoped
/// dependencies like a repository. Register one with
/// <c>services.AddScoped&lt;IKlippyEventHandler, MyHandler&gt;()</c> from the slice's own
/// registration method; nothing central needs to know the slice exists.
/// </summary>
public interface IKlippyEventHandler
{
    /// <summary>Called for every event. Keep it cheap: it runs before <see cref="HandleAsync"/> is considered.</summary>
    bool CanHandle(string eventType);

    /// <summary>
    /// Reacts to the event. Throwing is contained and logged, so one failing handler
    /// cannot stop the event reaching the other handlers or the connected devices.
    /// </summary>
    Task HandleAsync(LinkEnvelope envelope, CancellationToken cancellationToken);
}
