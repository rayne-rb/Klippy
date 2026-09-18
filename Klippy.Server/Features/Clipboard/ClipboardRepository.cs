using Klippy.Server.Data;
using Klippy.Shared.Clipboard;
using RepoDb;

namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// All database access for the clipboard. RepoDb's typed insert for the plain case,
/// hand-written SQL wherever the statement is doing the work — the board listing joins
/// two tables and computes a preview, and pruning is a delete driven by a window.
/// </summary>
public sealed class ClipboardRepository(IDbConnectionFactory connections)
{
    public async Task InsertAsync(ClipboardEntryRow row, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.InsertAsync(row, cancellationToken: ct);
    }

    /// <summary>
    /// The board as one account sees it: its own entries, plus everything anyone has
    /// shared server-wide. That pair of conditions is the whole read rule, and it lives
    /// here so no caller has to remember it.
    /// </summary>
    public async Task<IReadOnlyList<ClipboardListRow>> ListForAccountAsync(
        Guid ownerUserId, int limit, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<ClipboardListRow>(
            """
            select e.entry_id, e.source_device_id, d.device_name as source_device_name,
                   u.username as owner_username, e.visibility, e.content_type,
                   e.byte_size, e.copied_at,
                   (e.owner_user_id = @ownerUserId) as is_mine,
                   case when e.content_type = 'text'
                        then regexp_replace(left(e.content_text, @previewLength), '\s+', ' ', 'g')
                   end as preview
            from clipboard_entries e
            join devices d on d.device_id = e.source_device_id
            join users u on u.user_id = e.owner_user_id
            where e.owner_user_id = @ownerUserId or e.visibility = 'server'
            order by e.copied_at desc
            limit @limit
            """,
            new { ownerUserId, limit, previewLength = ClipboardLimits.PreviewLength },
            cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>Every entry on the server, for the admin view. Content still left behind.</summary>
    public async Task<IReadOnlyList<ClipboardListRow>> ListAllAsync(int limit, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<ClipboardListRow>(
            """
            select e.entry_id, e.source_device_id, d.device_name as source_device_name,
                   u.username as owner_username, e.visibility, e.content_type,
                   e.byte_size, e.copied_at, true as is_mine,
                   case when e.content_type = 'text'
                        then regexp_replace(left(e.content_text, @previewLength), '\s+', ' ', 'g')
                   end as preview
            from clipboard_entries e
            join devices d on d.device_id = e.source_device_id
            join users u on u.user_id = e.owner_user_id
            order by e.copied_at desc
            limit @limit
            """,
            new { limit, previewLength = ClipboardLimits.PreviewLength },
            cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>One entry with its content. The only read that touches the blob.</summary>
    public async Task<ClipboardEntryRow?> FindAsync(Guid entryId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.QueryAsync<ClipboardEntryRow>(
            r => r.EntryId == entryId, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    /// <summary>
    /// The account's newest entry's digest, or null when it has none. Compared against
    /// what a device just read off its clipboard so that polling the same unchanged
    /// clipboard does not fill the board with copies of one thing.
    /// </summary>
    public async Task<string?> NewestDigestAsync(Guid ownerUserId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        return await connection.ExecuteScalarAsync<string?>(
            "select digest from clipboard_entries where owner_user_id = @ownerUserId " +
            "order by copied_at desc limit 1",
            new { ownerUserId },
            cancellationToken: ct);
    }

    /// <summary>Deletes an entry, but only out of the account that owns it. Returns whether it did.</summary>
    public async Task<bool> DeleteAsync(Guid entryId, Guid ownerUserId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var affected = await connection.ExecuteNonQueryAsync(
            "delete from clipboard_entries where entry_id = @entryId and owner_user_id = @ownerUserId",
            new { entryId, ownerUserId },
            cancellationToken: ct);
        return affected > 0;
    }

    /// <summary>Deletes an entry whoever owns it. For an admin clearing up on the server's own page.</summary>
    public async Task<bool> DeleteAnyAsync(Guid entryId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var affected = await connection.ExecuteNonQueryAsync(
            "delete from clipboard_entries where entry_id = @entryId",
            new { entryId },
            cancellationToken: ct);
        return affected > 0;
    }

    /// <summary>
    /// Drops everything past the newest <paramref name="keep"/> entries of an account, and
    /// answers which ids went so the boards showing them can be told.
    /// </summary>
    public async Task<IReadOnlyList<Guid>> PruneAsync(Guid ownerUserId, int keep, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<Guid>(
            """
            delete from clipboard_entries
            where entry_id in (
                select entry_id from clipboard_entries
                where owner_user_id = @ownerUserId
                order by copied_at desc
                offset @keep
            )
            returning entry_id
            """,
            new { ownerUserId, keep },
            cancellationToken: ct);
        return rows.ToList();
    }
}
