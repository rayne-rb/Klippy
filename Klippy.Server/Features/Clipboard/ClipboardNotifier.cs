namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// Bridges clipboard activity to anything watching it, same reason as
/// <c>MarketNotifier</c>: a copy lands on its own HTTP request scope, while the
/// /clipboard page lives in a Blazor circuit with a different one, so a scoped event
/// would never reach it.
/// </summary>
public sealed class ClipboardNotifier
{
    public event Action? Changed;

    public void NotifyChanged() => Changed?.Invoke();
}
