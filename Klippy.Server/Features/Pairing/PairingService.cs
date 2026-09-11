using Klippy.Shared.Link;
using Klippy.Shared.Pairing;

namespace Klippy.Server.Features.Pairing;

/// <summary>
/// The pairing rules. A device asks, a human approves in the server UI, the device
/// collects a token on its next poll. Same flow for the Companion and the phone.
/// </summary>
public sealed class PairingService(
    PairingRepository repository,
    ApprovedTokenCache approvedTokens,
    PairingNotifier notifier,
    ILogger<PairingService> logger)
{
    private static readonly TimeSpan RequestLifetime = TimeSpan.FromMinutes(5);

    public async Task<PairingRequestCreated> RequestAsync(PairingRequestInput input, CancellationToken ct)
    {
        if (!DeviceKind.IsKnown(input.DeviceKind))
        {
            throw new ArgumentException($"Unknown device kind '{input.DeviceKind}'.", nameof(input));
        }

        var row = new PairingRequestRow
        {
            RequestId = Guid.NewGuid(),
            Code = PairingTokens.NewCode(),
            DeviceKind = input.DeviceKind,
            DeviceName = Truncate(input.DeviceName, 80),
            Platform = Truncate(input.Platform, 80),
            Status = PairingStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.Add(RequestLifetime),
        };

        await repository.InsertRequestAsync(row, ct);
        logger.LogInformation("Pairing requested by {Kind} '{Name}', code {Code}",
            row.DeviceKind, row.DeviceName, row.Code);

        notifier.NotifyChanged();

        return new PairingRequestCreated
        {
            RequestId = row.RequestId.ToString(),
            Code = row.Code,
            ExpiresAt = row.ExpiresAt,
        };
    }

    /// <summary>What the device polls. The token comes back exactly once.</summary>
    public async Task<PairingRequestState?> GetStateAsync(Guid requestId, CancellationToken ct)
    {
        await repository.ExpireStaleRequestsAsync(ct);

        var row = await repository.GetRequestAsync(requestId, ct);
        if (row is null)
        {
            return null;
        }

        if (row.Status != PairingStatus.Approved)
        {
            return new PairingRequestState { Status = row.Status };
        }

        return new PairingRequestState
        {
            Status = PairingStatus.Approved,
            DeviceId = row.DeviceId?.ToString(),
            // Null on a second poll or after a restart. The device treats that as
            // "start over" rather than as a usable pairing.
            Token = approvedTokens.Collect(row.RequestId),
        };
    }

    public async Task<IReadOnlyList<PairingRequestRow>> GetOpenRequestsAsync(CancellationToken ct)
    {
        await repository.ExpireStaleRequestsAsync(ct);
        return await repository.GetOpenRequestsAsync(ct);
    }

    public async Task<bool> ApproveAsync(Guid requestId, CancellationToken ct)
    {
        var request = await repository.GetRequestAsync(requestId, ct);
        if (request is null || request.Status != PairingStatus.Pending)
        {
            return false;
        }

        if (request.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            await repository.ExpireStaleRequestsAsync(ct);
            notifier.NotifyChanged();
            return false;
        }

        var token = PairingTokens.NewToken();
        var device = new PairedDeviceRow
        {
            DeviceId = Guid.NewGuid(),
            DeviceKind = request.DeviceKind,
            DeviceName = request.DeviceName,
            Platform = request.Platform,
            TokenHash = PairingTokens.Hash(token),
            PairedAt = DateTimeOffset.UtcNow,
        };

        await repository.ApproveAsync(request, device, ct);
        approvedTokens.Store(request.RequestId, token);

        logger.LogInformation("Paired {Kind} '{Name}' as {DeviceId}",
            device.DeviceKind, device.DeviceName, device.DeviceId);

        notifier.NotifyChanged();
        return true;
    }

    public async Task<bool> DenyAsync(Guid requestId, CancellationToken ct)
    {
        await repository.DenyAsync(requestId, ct);
        notifier.NotifyChanged();
        return true;
    }

    /// <summary>Resolves a bearer token to a device, or null if it is unknown or revoked.</summary>
    public async Task<PairedDeviceRow?> AuthenticateAsync(string? token, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }

        var device = await repository.FindByTokenHashAsync(PairingTokens.Hash(token), ct);
        if (device is not null)
        {
            await repository.TouchLastSeenAsync(device.DeviceId, ct);
        }

        return device;
    }

    public Task<IReadOnlyList<PairedDeviceRow>> GetDevicesAsync(CancellationToken ct) =>
        repository.GetActiveDevicesAsync(ct);

    public async Task RevokeAsync(Guid deviceId, CancellationToken ct)
    {
        await repository.RevokeAsync(deviceId, ct);
        logger.LogInformation("Revoked device {DeviceId}", deviceId);
        notifier.NotifyRevoked(deviceId);
    }

    private static string Truncate(string value, int max) =>
        string.IsNullOrWhiteSpace(value) ? "unnamed"
        : value.Length <= max ? value
        : value[..max];
}
