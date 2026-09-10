using Klippy.Mobile.Data;
using RepoDb;

namespace Klippy.Mobile.Features.Discovery;

/// <summary>
/// Remembers a server address the user typed in, for the cases multicast cannot
/// reach: a tailnet, mobile data, or an emulator behind user-mode NAT.
///
/// Kept apart from the pairing record on purpose — the address is how we *find* the
/// server, and it stays useful across unpairing and re-pairing.
/// </summary>
public sealed class ManualAddressStore(MobileDatabase database)
{
    private const string Key = "manual_server_address";

    public async Task<string?> GetAsync(CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<string>(
            "select value from app_settings where key = @Key", new { Key }, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    public async Task SetAsync(string? address, CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);

        if (string.IsNullOrWhiteSpace(address))
        {
            await connection.ExecuteNonQueryAsync(
                "delete from app_settings where key = @Key", new { Key }, cancellationToken: ct);
            return;
        }

        await connection.ExecuteNonQueryAsync(
            """
            insert into app_settings (key, value) values (@Key, @Value)
            on conflict (key) do update set value = excluded.value
            """,
            new { Key, Value = address.Trim() },
            cancellationToken: ct);
    }
}
