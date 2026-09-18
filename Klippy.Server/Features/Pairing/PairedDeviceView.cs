using RepoDb.Attributes;

namespace Klippy.Server.Features.Pairing;

/// <summary>
/// A paired device with the name of the account that owns it, for the Devices page.
/// Not a table of its own.
/// </summary>
public sealed class PairedDeviceView
{
    [Map("device_id")]
    public Guid DeviceId { get; set; }

    [Map("device_kind")]
    public string DeviceKind { get; set; } = string.Empty;

    [Map("device_name")]
    public string DeviceName { get; set; } = string.Empty;

    [Map("platform")]
    public string Platform { get; set; } = string.Empty;

    [Map("paired_at")]
    public DateTimeOffset PairedAt { get; set; }

    [Map("last_seen_at")]
    public DateTimeOffset? LastSeenAt { get; set; }

    [Map("owner_user_id")]
    public Guid? OwnerUserId { get; set; }

    /// <summary>Null for a device nobody has approved into an account — a group of one.</summary>
    [Map("owner_username")]
    public string? OwnerUsername { get; set; }
}
