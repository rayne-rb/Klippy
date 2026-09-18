namespace Klippy.Shared.Clipboard;

/// <summary>Who an entry is for. Chosen per device, stamped on each entry as it is copied.</summary>
public static class ClipboardVisibility
{
    /// <summary>The account that copied it, and nobody else. The default everywhere.</summary>
    public const string Group = "group";

    /// <summary>Everyone on this server, whatever account they are in.</summary>
    public const string Server = "server";

    public static bool IsKnown(string? value) => value is Group or Server;
}

public static class ClipboardContentTypes
{
    public const string Text = "text";
    public const string Png = "image/png";

    public static bool IsKnown(string? value) => value is Text or Png;
}

public static class ClipboardLimits
{
    /// <summary>
    /// The largest text entry, in UTF-8 bytes. Well under the Link's 64 KB message cap,
    /// though nothing about an entry crosses the Link anyway — see
    /// <see cref="Link.KlippyEvents.ClipboardEntry"/>.
    /// </summary>
    public const int MaxTextBytes = 32 * 1024;

    /// <summary>The largest image entry. A screenshot, not a photo library.</summary>
    public const int MaxImageBytes = 8 * 1024 * 1024;

    /// <summary>
    /// How many entries an account keeps. Older ones are dropped as new ones arrive: a
    /// clipboard is a recent history, and an unbounded one is a growing pile of things
    /// people have long since stopped meaning to share.
    /// </summary>
    public const int HistoryPerAccount = 100;

    /// <summary>
    /// How much of a text entry a listing shows. The full content is a separate fetch, so
    /// a board of a hundred entries does not move megabytes to draw itself.
    /// </summary>
    public const int PreviewLength = 280;
}

/// <summary>
/// A new entry landed. Sent over the Link to say <em>that</em> something was copied, never
/// <em>what</em>: the content is fetched over HTTP by whoever wants it.
/// </summary>
public sealed record ClipboardEntryPayload
{
    public required string EntryId { get; init; }
    public required string SourceDeviceId { get; init; }
    public required string SourceDeviceName { get; init; }
    public required string ContentType { get; init; }
    public required int ByteSize { get; init; }
    public required string Visibility { get; init; }
}

/// <summary>An entry was deleted and should leave every board showing it.</summary>
public sealed record ClipboardRemovedPayload
{
    public required string EntryId { get; init; }
}

/// <summary>
/// Put this entry on your clipboard. Addressed at one device, and only ever at one in the
/// sender's own account. Carries the id alone — the target fetches the content itself,
/// with its own token.
/// </summary>
public sealed record ClipboardApplyPayload
{
    public required string EntryId { get; init; }
}

/// <summary>
/// A device saying whether its clipboard skill is on, and who it is copying for. Lets the
/// server skip announcing to devices that are not listening, and lets its own page show
/// who is taking part.
/// </summary>
public sealed record ClipboardSharingPayload
{
    public required bool Enabled { get; init; }
    public required string Visibility { get; init; }
}

/// <summary>
/// One entry as a board shows it: enough to list, not enough to be the content. Returned
/// by <c>GET /api/clipboard</c>.
/// </summary>
public sealed record ClipboardEntryView
{
    public required string EntryId { get; init; }
    public required string SourceDeviceId { get; init; }
    public required string SourceDeviceName { get; init; }
    public required string ContentType { get; init; }
    public required int ByteSize { get; init; }
    public required string Visibility { get; init; }
    public required DateTimeOffset CopiedAt { get; init; }

    /// <summary>True when this entry belongs to the caller's own account.</summary>
    public required bool IsMine { get; init; }

    /// <summary>The account it came from. Only interesting for an entry shared server-wide.</summary>
    public string? OwnerName { get; init; }

    /// <summary>The first of a text entry's content, truncated. Null for an image.</summary>
    public string? Preview { get; init; }
}
