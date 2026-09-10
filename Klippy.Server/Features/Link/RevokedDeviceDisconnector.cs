using Klippy.Server.Features.Pairing;

namespace Klippy.Server.Features.Link;

/// <summary>
/// Drops a device's connection the moment its pairing is revoked.
///
/// Lives in the link slice and reaches out to pairing, rather than the other way
/// around: pairing raises "this device is revoked" and does not care who acts on it,
/// which keeps the dependency pointing one way.
/// </summary>
public sealed class RevokedDeviceDisconnector(
    PairingNotifier notifier,
    LinkRegistry registry,
    ILogger<RevokedDeviceDisconnector> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        notifier.DeviceRevoked += OnRevoked;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        notifier.DeviceRevoked -= OnRevoked;
        return Task.CompletedTask;
    }

    private void OnRevoked(Guid deviceId) => _ = DisconnectAsync(deviceId);

    private async Task DisconnectAsync(Guid deviceId)
    {
        try
        {
            await registry.DisconnectAsync(deviceId);
        }
        catch (Exception ex)
        {
            // The revocation itself already succeeded; failing to hang up only means
            // the device stays on until its socket breaks on its own.
            logger.LogWarning(ex, "Could not drop revoked device {DeviceId}", deviceId);
        }
    }
}
