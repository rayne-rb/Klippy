namespace Klippy.Server.Features.Pairing;

/// <summary>
/// Bridges pairing activity to anything watching it.
///
/// This has to be a singleton: a pairing request arrives on its own HTTP request with
/// its own scope, while the Devices page lives in a Blazor circuit with a different
/// one. An event on the scoped service would be raised on an instance the page has
/// never seen.
/// </summary>
public sealed class PairingNotifier
{
    public event Action? Changed;

    /// <summary>
    /// A device's access was withdrawn. The link slice listens for this so a revoked
    /// device is dropped immediately rather than lingering until its socket happens
    /// to break. Pairing raises it without knowing anything is listening.
    /// </summary>
    public event Action<Guid>? DeviceRevoked;

    public void NotifyChanged() => Changed?.Invoke();

    public void NotifyRevoked(Guid deviceId)
    {
        DeviceRevoked?.Invoke(deviceId);
        Changed?.Invoke();
    }
}
