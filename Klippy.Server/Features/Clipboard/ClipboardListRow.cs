using RepoDb.Attributes;

namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// What a board listing selects: an entry without its content, joined with the names
/// around it. Deliberately never selects <c>content_blob</c> — a hundred rows of image
/// bytes is not a list, and nothing drawing a board needs them.
///
/// Projected onto <see cref="Klippy.Shared.Clipboard.ClipboardEntryView"/>, which is the
/// shape the devices see.
/// </summary>
public sealed class ClipboardListRow
{
    [Map("entry_id")]
    public Guid EntryId { get; set; }

    [Map("source_device_id")]
    public Guid SourceDeviceId { get; set; }

    [Map("source_device_name")]
    public string SourceDeviceName { get; set; } = string.Empty;

    [Map("owner_username")]
    public string? OwnerUsername { get; set; }

    [Map("visibility")]
    public string Visibility { get; set; } = string.Empty;

    [Map("content_type")]
    public string ContentType { get; set; } = string.Empty;

    [Map("byte_size")]
    public int ByteSize { get; set; }

    [Map("copied_at")]
    public DateTimeOffset CopiedAt { get; set; }

    [Map("is_mine")]
    public bool IsMine { get; set; }

    /// <summary>Null for an image entry; truncated and whitespace-collapsed for text.</summary>
    [Map("preview")]
    public string? Preview { get; set; }
}
