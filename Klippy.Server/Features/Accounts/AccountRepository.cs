using Klippy.Server.Data;
using RepoDb;

namespace Klippy.Server.Features.Accounts;

/// <summary>
/// All database access for accounts, plus the one write that hands a device to one.
/// RepoDb's typed helpers for the plain cases, hand-written SQL where a single
/// statement beats a read-modify-write round trip.
/// </summary>
public sealed class AccountRepository(IDbConnectionFactory connections)
{
    public async Task<bool> AnyAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        return await connection.ExecuteScalarAsync<long>(
            "select count(*) from users", cancellationToken: ct) > 0;
    }

    public async Task<AccountRow?> FindByUsernameAsync(string username, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.QueryAsync<AccountRow>(
            r => r.Username == username, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    public async Task<AccountRow?> FindAsync(Guid userId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.QueryAsync<AccountRow>(
            r => r.UserId == userId, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    /// <summary>
    /// The oldest admin account, or null when there is none. Used where something has to
    /// act on behalf of "whoever runs this server" — the loopback approval API, which has
    /// a request but no signed-in account behind it.
    /// </summary>
    public async Task<AccountRow?> FindFirstAdminAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<AccountRow>(
            "select * from users where is_admin order by created_at asc limit 1",
            cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    public async Task<IReadOnlyList<AccountRow>> GetAllAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<AccountRow>(
            "select * from users order by created_at asc", cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>Every account with the number of devices it owns, oldest first.</summary>
    public async Task<IReadOnlyList<AccountSummary>> GetSummariesAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<AccountSummary>(
            """
            select u.user_id, u.username, u.is_admin, u.created_at,
                   count(d.device_id) filter (where d.revoked_at is null) as device_count
            from users u
            left join devices d on d.owner_user_id = u.user_id
            group by u.user_id, u.username, u.is_admin, u.created_at
            order by u.created_at asc
            """,
            cancellationToken: ct);
        return rows.ToList();
    }

    public async Task InsertAsync(AccountRow row, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.InsertAsync(row, cancellationToken: ct);
    }

    public async Task DeleteAsync(Guid userId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        // devices.owner_user_id is "on delete set null", so the deleted account's
        // devices stay paired and fall back to being a group of one each.
        await connection.ExecuteNonQueryAsync(
            "delete from users where user_id = @userId", new { userId }, cancellationToken: ct);
    }

    public async Task SetPasswordAsync(Guid userId, string passwordHash, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update users set password_hash = @passwordHash where user_id = @userId",
            new { userId, passwordHash },
            cancellationToken: ct);
    }

    /// <summary>Hands one device to an account. Writing the column the pairing slice owns.</summary>
    public async Task AssignDeviceAsync(Guid deviceId, Guid ownerUserId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update devices set owner_user_id = @ownerUserId where device_id = @deviceId",
            new { deviceId, ownerUserId },
            cancellationToken: ct);
    }

    /// <summary>Takes a device back out of every account. It becomes a group of one.</summary>
    public async Task ReleaseDeviceAsync(Guid deviceId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update devices set owner_user_id = null where device_id = @deviceId",
            new { deviceId },
            cancellationToken: ct);
    }

    /// <summary>How many paired devices have no account yet. Read by the first-run setup.</summary>
    public async Task<int> CountUnownedDevicesAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        return (int)await connection.ExecuteScalarAsync<long>(
            "select count(*) from devices where owner_user_id is null and revoked_at is null",
            cancellationToken: ct);
    }

    /// <summary>
    /// Hands every currently unowned device to an account, and answers how many there
    /// were. Used once, by the first-run setup: a server that paired devices before
    /// accounts existed would otherwise leave them all stranded in groups of one.
    /// </summary>
    public async Task<int> ClaimUnownedDevicesAsync(Guid ownerUserId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        return await connection.ExecuteNonQueryAsync(
            "update devices set owner_user_id = @ownerUserId where owner_user_id is null",
            new { ownerUserId },
            cancellationToken: ct);
    }
}
