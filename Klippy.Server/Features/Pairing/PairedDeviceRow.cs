using RepoDb.Attributes;

namespace Klippy.Server.Features.Pairing;

/// <summary>Row in <c>devices</c>. Owned by the pairing slice; nothing else writes it.</summary>
[Map("devices")]
public sealed class PairedDeviceRow
{
    [Primary]
    [Map("device_id")]
    public Guid DeviceId { get; set; }

    [Map("device_kind")]
    public string DeviceKind { get; set; } = string.Empty;

    [Map("device_name")]
    public string DeviceName { get; set; } = string.Empty;

    [Map("platform")]
    public string Platform { get; set; } = string.Empty;

    [Map("token_hash")]
    public string TokenHash { get; set; } = string.Empty;

    [Map("paired_at")]
    public DateTimeOffset PairedAt { get; set; }

    [Map("last_seen_at")]
    public DateTimeOffset? LastSeenAt { get; set; }

    [Map("revoked_at")]
    public DateTimeOffset? RevokedAt { get; set; }
}
