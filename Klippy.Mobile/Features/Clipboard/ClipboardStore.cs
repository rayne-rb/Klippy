using Klippy.Mobile.Data;
using Klippy.Shared.Clipboard;
using RepoDb;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// The board as it was last fetched, so the tab has something to show before the socket
/// is up — the same job <c>last_pet_stats</c> does for the pet.
///
/// Only the listing is cached, never the content. What a phone carries around should not
/// be a copy of everything anyone has ever copied; the bytes are fetched at the moment
/// they are actually wanted.
/// </summary>
public sealed class ClipboardStore(MobileDatabase database)
{
    public async Task<IReadOnlyList<ClipboardEntryView>> GetAsync(CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<CachedEntry>(
            "select * from clipboard_entries order by copied_at desc", cancellationToken: ct);

        return rows.Select(r => new ClipboardEntryView
        {
            EntryId = r.EntryId,
            SourceDeviceId = r.SourceDeviceId,
            SourceDeviceName = r.SourceDeviceName,
            ContentType = r.ContentType,
            ByteSize = r.ByteSize,
            Visibility = r.Visibility,
            CopiedAt = DateTimeOffset.TryParse(r.CopiedAt, out var at) ? at : DateTimeOffset.MinValue,
            IsMine = r.IsMine != 0,
            OwnerName = r.OwnerName,
            Preview = r.Preview,
        }).ToList();
    }

    /// <summary>Replaces the cache with what the server just said. The server's list is the truth.</summary>
    public async Task SaveAsync(IReadOnlyList<ClipboardEntryView> entries, CancellationToken ct = default)
    {
        await using var connection = await database.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync("delete from clipboard_entries", cancellationToken: ct);

        foreach (var entry in entries)
        {
            // RepoDb's typed insert, not raw SQL: a mapped entity handed to a raw
            // statement has its parameters named after the columns, so "@EntryId" would
            // never bind. Same trap PairedServerStore documents.
            await connection.InsertAsync(new CachedEntry
            {
                EntryId = entry.EntryId,
                SourceDeviceId = entry.SourceDeviceId,
                SourceDeviceName = entry.SourceDeviceName,
                OwnerName = entry.OwnerName,
                ContentType = entry.ContentType,
                ByteSize = entry.ByteSize,
                Visibility = entry.Visibility,
                IsMine = entry.IsMine ? 1 : 0,
                Preview = entry.Preview,
                CopiedAt = entry.CopiedAt.ToString("o"),
            }, cancellationToken: ct);
        }
    }
}
