namespace Klippy.Server.Features.Market;

/// <summary>
/// Bridges market activity to anything watching it, same reason as <c>PairingNotifier</c>:
/// a sale lands on its own HTTP request scope, while the /market page lives in a Blazor
/// circuit with a different one, so a scoped event would never reach it.
/// </summary>
public sealed class MarketNotifier
{
    public event Action? Changed;

    public void NotifyChanged() => Changed?.Invoke();
}
