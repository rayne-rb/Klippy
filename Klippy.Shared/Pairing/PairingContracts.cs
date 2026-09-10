namespace Klippy.Shared.Pairing;

/// <summary>
/// Pairing is deliberately approve-on-the-server rather than type-a-code-on-the-device:
/// the device shows a short code, the human confirms that same code in the server's
/// Devices page, and the device gets a long-lived token back. The Companion and the
/// phone use the identical flow, so there is only one thing to get right.
/// </summary>
public static class PairingStatus
{
    public const string Pending = "pending";
    public const string Approved = "approved";
    public const string Denied = "denied";
    public const string Expired = "expired";
}

/// <summary>What a device tells the server about itself when asking to pair.</summary>
public sealed record PairingRequestInput
{
    /// <summary>One of <see cref="Link.DeviceKind"/>.</summary>
    public required string DeviceKind { get; init; }

    /// <summary>Shown to the human doing the approving, e.g. "Tulonga's Pixel".</summary>
    public required string DeviceName { get; init; }

    /// <summary>Free text, e.g. "Android 15" or "Linux/Godot 4.7.1".</summary>
    public required string Platform { get; init; }
}

/// <summary>Handed back immediately; the device displays <see cref="Code"/> and polls.</summary>
public sealed record PairingRequestCreated
{
    public required string RequestId { get; init; }

    /// <summary>Six characters, unambiguous alphabet, shown on both screens for comparison.</summary>
    public required string Code { get; init; }

    public required DateTimeOffset ExpiresAt { get; init; }
}

/// <summary>Poll result. Token is populated exactly once, on the transition to approved.</summary>
public sealed record PairingRequestState
{
    /// <summary>One of <see cref="PairingStatus"/>.</summary>
    public required string Status { get; init; }

    public string? DeviceId { get; init; }

    /// <summary>Bearer token for the link socket. Only present when <see cref="Status"/> is approved.</summary>
    public string? Token { get; init; }
}

/// <summary>A device the server has already accepted.</summary>
public sealed record PairedDeviceInfo
{
    public required string DeviceId { get; init; }
    public required string DeviceKind { get; init; }
    public required string DeviceName { get; init; }
    public required string Platform { get; init; }
    public required DateTimeOffset PairedAt { get; init; }
    public DateTimeOffset? LastSeenAt { get; init; }
    public bool IsConnected { get; init; }
}
