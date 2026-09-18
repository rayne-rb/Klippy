using Klippy.Shared.Clipboard;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// One board entry, dressed for the screen.
///
/// A wrapper rather than extra properties on <see cref="ClipboardEntryView"/>, because
/// that one is a wire contract shared with the server and has no business knowing how a
/// phone lays out a list.
/// </summary>
public sealed class ClipboardRow(ClipboardEntryView entry)
{
    public ClipboardEntryView Entry { get; } = entry;

    public string EntryId => Entry.EntryId;

    public bool IsMine => Entry.IsMine;

    public bool IsText => Entry.ContentType == ClipboardContentTypes.Text;

    public bool IsImage => !IsText;

    public string Preview => Entry.Preview ?? string.Empty;

    public string ImageLabel => $"Image · {Bytes(Entry.ByteSize)}";

    /// <summary>Where it came from, and whether anyone outside this account can see it.</summary>
    public string Origin
    {
        get
        {
            var shared = Entry.Visibility == ClipboardVisibility.Server;

            if (shared && !Entry.IsMine)
            {
                return $"from {Entry.SourceDeviceName} · shared by {Entry.OwnerName ?? "someone"}";
            }

            return shared
                ? $"from {Entry.SourceDeviceName} · shared with everyone"
                : $"from {Entry.SourceDeviceName}";
        }
    }

    private static string Bytes(int bytes) =>
        bytes >= 1024 * 1024 ? $"{bytes / 1024.0 / 1024.0:0.#} MB"
        : bytes >= 1024 ? $"{bytes / 1024.0:0.#} KB"
        : $"{bytes} B";
}
