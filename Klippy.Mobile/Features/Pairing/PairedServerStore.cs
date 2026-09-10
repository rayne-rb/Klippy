using Klippy.Mobile.Data;
using RepoDb;

namespace Klippy.Mobile.Features.Pairing;

/// <summary>Reads and writes the phone's pairing. At most one row ever exists.</summary>
public sealed class PairedServerStore(MobileDatabase database)
{
    public async Task<PairedServerRow?> GetAsync(CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<PairedServerRow>(
            "select * from paired_server limit 1", cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    public async Task SaveAsync(PairedServerRow row, CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);

        // One server at a time: replace rather than accumulate stale pairings.
        await connection.ExecuteNonQueryAsync("delete from paired_server", cancellationToken: ct);
        await connection.ExecuteNonQueryAsync(
            """
            insert into paired_server (server_id, name, base_url, ws_url, device_id, token, paired_at)
            values (@ServerId, @Name, @BaseUrl, @WsUrl, @DeviceId, @Token, @PairedAt)
            """,
            row,
            cancellationToken: ct);
    }

    /// <summary>Keeps the stored address current when the server turns up on a new IP.</summary>
    public async Task UpdateAddressAsync(string serverId, string baseUrl, string wsUrl, CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update paired_server set base_url = @baseUrl, ws_url = @wsUrl where server_id = @serverId",
            new { serverId, baseUrl, wsUrl },
            cancellationToken: ct);
    }

    public async Task ClearAsync(CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync("delete from paired_server", cancellationToken: ct);
    }
}
