using System.Collections.Concurrent;
using Klippy.Shared.Clipboard;

namespace Klippy.Server.Features.Clipboard;

/// <summary>Which devices have the clipboard skill on, and who each is copying for.</summary>
/// <remarks>
/// In memory only, like <c>AudioCastSessions</c> and <c>PetStateStore</c>: the skill is a
/// switch on a running device, and a device that is not connected is not sharing anything.
///
/// Nothing routes by this. A device that has the skill off is still told an entry landed
/// and simply ignores it, and one that is off never sends anything in the first place —
/// deciding not to copy is the device's own business, not something the server enforces on
/// its behalf. What this is for is being able to say, on the server's own page, who is
/// taking part.
/// </remarks>
public sealed class ClipboardSessions
{
    private readonly ConcurrentDictionary<Guid, ClipboardSharer> _sharers = new();

    /// <summary>Raised when the sharing set changes, for the live view on the server's page.</summary>
    public event Action? Changed;

    public IReadOnlyCollection<ClipboardSharer> All => _sharers.Values.ToList();

    public ClipboardSharer? Find(Guid deviceId) =>
        _sharers.TryGetValue(deviceId, out var sharer) ? sharer : null;

    public void Set(Guid deviceId, Guid? ownerUserId, string deviceName, bool enabled, string? visibility)
    {
        if (!enabled)
        {
            Forget(deviceId);
            return;
        }

        _sharers[deviceId] = new ClipboardSharer
        {
            DeviceId = deviceId,
            OwnerUserId = ownerUserId,
            DeviceName = deviceName,
            Visibility = ClipboardVisibility.IsKnown(visibility) ? visibility! : ClipboardVisibility.Group,
            Since = DateTimeOffset.UtcNow,
        };

        Changed?.Invoke();
    }

    public void Forget(Guid deviceId)
    {
        if (_sharers.TryRemove(deviceId, out _))
        {
            Changed?.Invoke();
        }
    }
}

/// <summary>One device with the skill switched on.</summary>
public sealed class ClipboardSharer
{
    public required Guid DeviceId { get; init; }
    public required Guid? OwnerUserId { get; init; }
    public required string DeviceName { get; init; }
    public required string Visibility { get; init; }
    public required DateTimeOffset Since { get; init; }
}
