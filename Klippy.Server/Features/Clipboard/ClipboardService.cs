using System.Security.Cryptography;
using System.Text;
using Klippy.Server.Features.Link;
using Klippy.Server.Features.Pairing;
using Klippy.Shared.Clipboard;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// The clipboard rules: what may be stored, who may see it, and who gets told.
///
/// Content only ever moves over HTTP. What goes onto the Link is the fact that an entry
/// exists — see the note on <see cref="KlippyEvents.ClipboardEntry"/> for why an event
/// carrying the content would be the wrong shape twice over.
/// </summary>
public sealed class ClipboardService(
    ClipboardRepository repository,
    IEventPublisher publisher,
    ClipboardNotifier notifier,
    ILogger<ClipboardService> logger)
{
    /// <summary>What went wrong, or null when nothing did.</summary>
    public sealed record AddResult(ClipboardEntryRow? Entry, string? Error, bool WasDuplicate);

    public Task<IReadOnlyList<ClipboardListRow>> ListForAccountAsync(Guid ownerUserId, CancellationToken ct) =>
        repository.ListForAccountAsync(ownerUserId, ClipboardLimits.HistoryPerAccount, ct);

    public Task<IReadOnlyList<ClipboardListRow>> ListAllAsync(CancellationToken ct) =>
        repository.ListAllAsync(ClipboardLimits.HistoryPerAccount, ct);

    public Task<ClipboardEntryRow?> FindAsync(Guid entryId, CancellationToken ct) =>
        repository.FindAsync(entryId, ct);

    /// <summary>
    /// Whether an account may read an entry: its own, or one somebody shared server-wide.
    /// The same rule the board listing is built on, in the form a single fetch needs.
    /// </summary>
    public static bool CanRead(ClipboardEntryRow entry, Guid? ownerUserId) =>
        entry.Visibility == ClipboardVisibility.Server || entry.OwnerUserId == ownerUserId;

    /// <summary>
    /// What is wrong with this text, or null when nothing is. Separate from the storing so
    /// the rules can be checked without a database behind them.
    /// </summary>
    public static string? DescribeTextProblem(string? text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return "There was nothing to copy.";
        }

        var bytes = Encoding.UTF8.GetByteCount(text);
        return bytes > ClipboardLimits.MaxTextBytes
            ? $"That is {bytes} bytes of text; the limit is {ClipboardLimits.MaxTextBytes}."
            : null;
    }

    /// <summary>The same for an image.</summary>
    public static string? DescribeImageProblem(byte[] png)
    {
        if (png.Length == 0)
        {
            return "There was nothing to copy.";
        }

        if (png.Length > ClipboardLimits.MaxImageBytes)
        {
            return $"That image is {png.Length} bytes; the limit is {ClipboardLimits.MaxImageBytes}.";
        }

        // Everything downstream is told this is a PNG - the board renders it as one, and a
        // phone hands it to the OS as one. Checking the header here is cheaper than every
        // one of those finding out for itself.
        return LooksLikePng(png) ? null : "That does not look like a PNG.";
    }

    public Task<AddResult> AddTextAsync(
        PairedDeviceRow device, string? text, string? visibility, CancellationToken ct)
    {
        if (DescribeTextProblem(text) is { } problem)
        {
            return Task.FromResult(new AddResult(null, problem, false));
        }

        return AddAsync(device, visibility, ClipboardContentTypes.Text, text,
            null, Encoding.UTF8.GetByteCount(text!), Digest(Encoding.UTF8.GetBytes(text!)), ct);
    }

    public Task<AddResult> AddImageAsync(
        PairedDeviceRow device, byte[] png, string? visibility, CancellationToken ct)
    {
        if (DescribeImageProblem(png) is { } problem)
        {
            return Task.FromResult(new AddResult(null, problem, false));
        }

        return AddAsync(device, visibility, ClipboardContentTypes.Png, null, png, png.Length,
            Digest(png), ct);
    }

    private async Task<AddResult> AddAsync(
        PairedDeviceRow device,
        string? visibility,
        string contentType,
        string? text,
        byte[]? blob,
        int byteSize,
        string digest,
        CancellationToken ct)
    {
        if (device.OwnerUserId is not { } owner)
        {
            // A device nobody has claimed has no board to put this on. Saying so plainly
            // is better than inventing a private one that its owner will never find.
            return new AddResult(
                null, "This device has not been approved into an account yet.", false);
        }

        // A clipboard is read by polling it, so the same content arrives over and over.
        // Only the newest is compared: copying A, then B, then A again is three real
        // copies and should look like three.
        if (await repository.NewestDigestAsync(owner, ct) == digest)
        {
            return new AddResult(null, null, true);
        }

        var row = new ClipboardEntryRow
        {
            EntryId = Guid.NewGuid(),
            OwnerUserId = owner,
            SourceDeviceId = device.DeviceId,
            Visibility = ClipboardVisibility.IsKnown(visibility) ? visibility! : ClipboardVisibility.Group,
            ContentType = contentType,
            ContentText = text,
            ContentBlob = blob,
            ByteSize = byteSize,
            Digest = digest,
            CopiedAt = DateTimeOffset.UtcNow,
        };

        await repository.InsertAsync(row, ct);

        var pruned = await repository.PruneAsync(owner, ClipboardLimits.HistoryPerAccount, ct);

        await AnnounceAsync(row, device.DeviceName, ct);

        foreach (var gone in pruned)
        {
            await AnnounceRemovalAsync(gone, owner, row.Visibility, ct);
        }

        logger.LogInformation(
            "Clipboard: {Kind} of {Bytes} B from '{Device}' ({Visibility})",
            contentType, byteSize, device.DeviceName, row.Visibility);

        notifier.NotifyChanged();
        return new AddResult(row, null, false);
    }

    /// <summary>Deletes an entry out of its own account, telling whoever could see it.</summary>
    public async Task<bool> DeleteAsync(Guid entryId, Guid ownerUserId, CancellationToken ct)
    {
        var entry = await repository.FindAsync(entryId, ct);
        if (entry is null || !await repository.DeleteAsync(entryId, ownerUserId, ct))
        {
            return false;
        }

        await AnnounceRemovalAsync(entryId, entry.OwnerUserId, entry.Visibility, ct);
        notifier.NotifyChanged();
        return true;
    }

    /// <summary>The same, for an admin on the server's own page, whoever owns the entry.</summary>
    public async Task<bool> DeleteAnyAsync(Guid entryId, CancellationToken ct)
    {
        var entry = await repository.FindAsync(entryId, ct);
        if (entry is null || !await repository.DeleteAnyAsync(entryId, ct))
        {
            return false;
        }

        await AnnounceRemovalAsync(entryId, entry.OwnerUserId, entry.Visibility, ct);
        notifier.NotifyChanged();
        return true;
    }

    /// <summary>
    /// Tells the devices that can see this entry that it is there. A server-wide entry
    /// goes to every connected device; anything else stops at the account that made it.
    /// Either way the payload is metadata — the content stays behind an authenticated
    /// fetch, so being told about an entry is not the same as being given it.
    /// </summary>
    private async Task AnnounceAsync(ClipboardEntryRow row, string deviceName, CancellationToken ct)
    {
        var envelope = LinkEnvelope.Create(KlippyEvents.ClipboardEntry, new ClipboardEntryPayload
        {
            EntryId = row.EntryId.ToString(),
            SourceDeviceId = row.SourceDeviceId.ToString(),
            SourceDeviceName = deviceName,
            ContentType = row.ContentType,
            ByteSize = row.ByteSize,
            Visibility = row.Visibility,
        });

        if (row.Visibility == ClipboardVisibility.Server)
        {
            await publisher.PublishAsync(envelope, ct);
        }
        else
        {
            await publisher.PublishToGroupAsync(row.OwnerUserId, envelope, ct);
        }
    }

    private async Task AnnounceRemovalAsync(
        Guid entryId, Guid ownerUserId, string visibility, CancellationToken ct)
    {
        var envelope = LinkEnvelope.Create(KlippyEvents.ClipboardRemoved, new ClipboardRemovedPayload
        {
            EntryId = entryId.ToString(),
        });

        if (visibility == ClipboardVisibility.Server)
        {
            await publisher.PublishAsync(envelope, ct);
        }
        else
        {
            await publisher.PublishToGroupAsync(ownerUserId, envelope, ct);
        }
    }

    /// <summary>SHA-256, lowercase hex. What dedupe compares, and what the devices hash too.</summary>
    public static string Digest(byte[] content) =>
        Convert.ToHexStringLower(SHA256.HashData(content));

    /// <summary>The eight bytes every PNG starts with.</summary>
    public static bool LooksLikePng(byte[] content) =>
        content.Length > 8
        && content[0] == 0x89 && content[1] == 0x50 && content[2] == 0x4E && content[3] == 0x47
        && content[4] == 0x0D && content[5] == 0x0A && content[6] == 0x1A && content[7] == 0x0A;
}
