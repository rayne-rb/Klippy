using Klippy.Mobile.Data;
using Klippy.Shared.Clipboard;
using RepoDb;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// Whether this phone shares its clipboard, and with whom. Kept in the same key/value
/// bag as the typed server address, since both are small user choices rather than
/// records of anything.
///
/// Off by default, and private by default once on — a clipboard carries passwords as
/// often as it carries a link, so neither default is one to be clever about.
/// </summary>
public sealed class ClipboardSettings(MobileDatabase database)
{
    private const string EnabledKey = "clipboard_enabled";
    private const string VisibilityKey = "clipboard_visibility";

    public async Task<bool> GetEnabledAsync(CancellationToken ct = default) =>
        await ReadAsync(EnabledKey, ct) == "true";

    public Task SetEnabledAsync(bool enabled, CancellationToken ct = default) =>
        WriteAsync(EnabledKey, enabled ? "true" : "false", ct);

    public async Task<string> GetVisibilityAsync(CancellationToken ct = default)
    {
        var stored = await ReadAsync(VisibilityKey, ct);

        // A value written by a newer version, or edited by hand, must never leave this
        // sharing more widely than the user last chose.
        return stored == ClipboardVisibility.Server
            ? ClipboardVisibility.Server
            : ClipboardVisibility.Group;
    }

    public Task SetVisibilityAsync(string visibility, CancellationToken ct = default) =>
        WriteAsync(
            VisibilityKey,
            visibility == ClipboardVisibility.Server ? ClipboardVisibility.Server : ClipboardVisibility.Group,
            ct);

    private async Task<string?> ReadAsync(string key, CancellationToken ct)
    {
        await using var connection = await database.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<string>(
            "select value from app_settings where key = @key", new { key }, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    private async Task WriteAsync(string key, string value, CancellationToken ct)
    {
        await using var connection = await database.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            """
            insert into app_settings (key, value) values (@key, @value)
            on conflict (key) do update set value = excluded.value
            """,
            new { key, value },
            cancellationToken: ct);
    }
}
