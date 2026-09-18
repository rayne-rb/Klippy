using RepoDb.Attributes;

namespace Klippy.Server.Features.Clipboard;

/// <summary>Row in <c>clipboard_entries</c>. Owned by the clipboard slice.</summary>
[Map("clipboard_entries")]
public sealed class ClipboardEntryRow
{
    [Primary]
    [Map("entry_id")]
    public Guid EntryId { get; set; }

    [Map("owner_user_id")]
    public Guid OwnerUserId { get; set; }

    [Map("source_device_id")]
    public Guid SourceDeviceId { get; set; }

    /// <summary>See <see cref="Klippy.Shared.Clipboard.ClipboardVisibility"/>.</summary>
    [Map("visibility")]
    public string Visibility { get; set; } = string.Empty;

    /// <summary>See <see cref="Klippy.Shared.Clipboard.ClipboardContentTypes"/>.</summary>
    [Map("content_type")]
    public string ContentType { get; set; } = string.Empty;

    /// <summary>Set for a text entry, null for an image. The table insists on exactly one.</summary>
    [Map("content_text")]
    public string? ContentText { get; set; }

    /// <summary>Set for an image, null for text.</summary>
    [Map("content_blob")]
    public byte[]? ContentBlob { get; set; }

    [Map("byte_size")]
    public int ByteSize { get; set; }

    /// <summary>SHA-256 of the content, lowercase hex. What dedupe compares.</summary>
    [Map("digest")]
    public string Digest { get; set; } = string.Empty;

    [Map("copied_at")]
    public DateTimeOffset CopiedAt { get; set; }
}
