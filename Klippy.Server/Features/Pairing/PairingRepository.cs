using Klippy.Server.Data;
using RepoDb;

namespace Klippy.Server.Features.Pairing;

/// <summary>
/// All database access for pairing. RepoDb's typed helpers for the plain cases,
/// hand-written SQL where a single statement beats a read-modify-write round trip.
/// </summary>
public sealed class PairingRepository(IDbConnectionFactory connections)
{
    public async Task InsertRequestAsync(PairingRequestRow row, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.InsertAsync(row, cancellationToken: ct);
    }

    public async Task<PairingRequestRow?> GetRequestAsync(Guid requestId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.QueryAsync<PairingRequestRow>(r => r.RequestId == requestId, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    /// <summary>Pending requests that have not lapsed, newest first.</summary>
    public async Task<IReadOnlyList<PairingRequestRow>> GetOpenRequestsAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<PairingRequestRow>(
            """
            select * from pairing_requests
            where status = 'pending' and expires_at > now()
            order by created_at desc
            """,
            cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>
    /// Flips lapsed requests to 'expired' in one statement. Cheap enough to call on
    /// every poll, which keeps the Devices page from showing dead requests.
    /// </summary>
    public async Task ExpireStaleRequestsAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update pairing_requests set status = 'expired', decided_at = now() " +
            "where status = 'pending' and expires_at <= now()",
            cancellationToken: ct);
    }

    /// <summary>
    /// Creates the device and marks the request approved together, so a crash between
    /// the two cannot leave an approved request pointing at no device.
    /// </summary>
    public async Task ApproveAsync(PairingRequestRow request, PairedDeviceRow device, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await using var transaction = await connection.BeginTransactionAsync(ct);

        await connection.InsertAsync(device, transaction: transaction, cancellationToken: ct);
        await connection.ExecuteNonQueryAsync(
            """
            update pairing_requests
            set status = 'approved', device_id = @DeviceId, decided_at = now()
            where request_id = @RequestId and status = 'pending'
            """,
            new { device.DeviceId, request.RequestId },
            transaction: transaction,
            cancellationToken: ct);

        await transaction.CommitAsync(ct);
    }

    public async Task DenyAsync(Guid requestId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update pairing_requests set status = 'denied', decided_at = now() " +
            "where request_id = @requestId and status = 'pending'",
            new { requestId },
            cancellationToken: ct);
    }

    public async Task<PairedDeviceRow?> FindByTokenHashAsync(string tokenHash, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<PairedDeviceRow>(
            "select * from devices where token_hash = @tokenHash and revoked_at is null limit 1",
            new { tokenHash },
            cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    public async Task<IReadOnlyList<PairedDeviceRow>> GetActiveDevicesAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<PairedDeviceRow>(
            "select * from devices where revoked_at is null order by paired_at desc",
            cancellationToken: ct);
        return rows.ToList();
    }

    public async Task TouchLastSeenAsync(Guid deviceId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update devices set last_seen_at = now() where device_id = @deviceId",
            new { deviceId },
            cancellationToken: ct);
    }

    /// <summary>Soft delete: the row stays for history, the token stops working immediately.</summary>
    public async Task RevokeAsync(Guid deviceId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update devices set revoked_at = now() where device_id = @deviceId and revoked_at is null",
            new { deviceId },
            cancellationToken: ct);
    }
}
