using RepoDb.Attributes;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>One cached board row. SQLite has no booleans or dates, hence the int and the text.</summary>
[Map("clipboard_entries")]
public sealed class CachedEntry
{
    [Primary]
    [Map("entry_id")]
    public string EntryId { get; set; } = string.Empty;

    [Map("source_device_id")]
    public string SourceDeviceId { get; set; } = string.Empty;

    [Map("source_device_name")]
    public string SourceDeviceName { get; set; } = string.Empty;

    [Map("owner_name")]
    public string? OwnerName { get; set; }

    [Map("content_type")]
    public string ContentType { get; set; } = string.Empty;

    [Map("byte_size")]
    public int ByteSize { get; set; }

    [Map("visibility")]
    public string Visibility { get; set; } = string.Empty;

    [Map("is_mine")]
    public int IsMine { get; set; }

    [Map("preview")]
    public string? Preview { get; set; }

    /// <summary>Round-trip ("o") format, so string ordering matches time ordering.</summary>
    [Map("copied_at")]
    public string CopiedAt { get; set; } = string.Empty;
}
