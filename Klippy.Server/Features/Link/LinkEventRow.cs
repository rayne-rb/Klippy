using RepoDb.Attributes;

namespace Klippy.Server.Features.Link;

/// <summary>Row in <c>link_events</c>, the record of everything that crossed the link.</summary>
[Map("link_events")]
public sealed class LinkEventRow
{
    [Primary]
    [Map("event_id")]
    public Guid EventId { get; set; }

    [Map("event_type")]
    public string EventType { get; set; } = string.Empty;

    [Map("source_device")]
    public Guid? SourceDevice { get; set; }

    [Map("target_device")]
    public Guid? TargetDevice { get; set; }

    [Map("payload")]
    public string? Payload { get; set; }

    [Map("occurred_at")]
    public DateTimeOffset OccurredAt { get; set; }
}
