using RepoDb.Attributes;

namespace Klippy.Server.Features.Pairing;

/// <summary>Row in <c>pairing_requests</c>.</summary>
[Map("pairing_requests")]
public sealed class PairingRequestRow
{
    [Primary]
    [Map("request_id")]
    public Guid RequestId { get; set; }

    [Map("code")]
    public string Code { get; set; } = string.Empty;

    [Map("device_kind")]
    public string DeviceKind { get; set; } = string.Empty;

    [Map("device_name")]
    public string DeviceName { get; set; } = string.Empty;

    [Map("platform")]
    public string Platform { get; set; } = string.Empty;

    [Map("status")]
    public string Status { get; set; } = string.Empty;

    [Map("device_id")]
    public Guid? DeviceId { get; set; }

    [Map("created_at")]
    public DateTimeOffset CreatedAt { get; set; }

    [Map("expires_at")]
    public DateTimeOffset ExpiresAt { get; set; }

    [Map("decided_at")]
    public DateTimeOffset? DecidedAt { get; set; }
}
