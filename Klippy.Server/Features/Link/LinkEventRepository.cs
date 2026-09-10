using Klippy.Server.Data;
using Klippy.Shared.Link;
using RepoDb;

namespace Klippy.Server.Features.Link;

/// <summary>
/// Persists the event stream. Written with explicit SQL rather than RepoDb's typed
/// insert because the payload column is jsonb and needs the cast spelled out.
/// </summary>
public sealed class LinkEventRepository(IDbConnectionFactory connections)
{
    public async Task AppendAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            """
            insert into link_events (event_id, event_type, source_device, target_device, payload, occurred_at)
            values (@EventId, @EventType, @SourceDevice, @TargetDevice, cast(@Payload as jsonb), @OccurredAt)
            on conflict (event_id) do nothing
            """,
            new
            {
                EventId = ParseGuid(envelope.Id) ?? Guid.NewGuid(),
                EventType = envelope.Type,
                SourceDevice = ParseGuid(envelope.Source),
                TargetDevice = ParseGuid(envelope.Target),
                Payload = envelope.Payload?.ToJsonString(),
                OccurredAt = DateTimeOffset.FromUnixTimeMilliseconds(envelope.Ts),
            },
            cancellationToken: ct);
    }

    /// <summary>Most recent events first, for the live view and for a device catching up.</summary>
    public async Task<IReadOnlyList<LinkEventRow>> GetRecentAsync(int limit, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<LinkEventRow>(
            "select * from link_events order by occurred_at desc limit @limit",
            new { limit },
            cancellationToken: ct);
        return rows.ToList();
    }

    private static Guid? ParseGuid(string? value) =>
        Guid.TryParse(value, out var parsed) ? parsed : null;
}
