namespace Klippy.Shared.Link.Payloads;

/// <summary>Pet vitals as the Companion currently sees them. Values are 0..max, not percentages.</summary>
public sealed record PetStatsPayload
{
    public required double Food { get; init; }
    public required double Mood { get; init; }
    public required double Health { get; init; }
    public required bool IsDead { get; init; }
    public required bool FeedingEnabled { get; init; }

    /// <summary>Human-readable bands, so the phone does not have to duplicate the thresholds.</summary>
    public string? FoodStatus { get; init; }
    public string? MoodStatus { get; init; }
    public string? HealthStatus { get; init; }
}

/// <summary>Optional detail on a feed command.</summary>
public sealed record FeedPayload
{
    /// <summary>How many food items to drop. Clamped by the Companion to what it can hold.</summary>
    public int Count { get; init; } = 1;
}

/// <summary>Something for the pet to say, or something it just said.</summary>
public sealed record SayPayload
{
    public required string Text { get; init; }
}

/// <summary>A plain on/off command.</summary>
public sealed record TogglePayload
{
    public required bool Enabled { get; init; }
}

/// <summary>A device appearing or disappearing on the link.</summary>
public sealed record DevicePresencePayload
{
    public required string DeviceId { get; init; }
    public required string DeviceKind { get; init; }
    public required string DeviceName { get; init; }
}

/// <summary>First message a device receives, telling it who it is and who else is here.</summary>
public sealed record WelcomePayload
{
    public required string DeviceId { get; init; }
    public required string ServerId { get; init; }
    public required string ServerName { get; init; }
    public required IReadOnlyList<DevicePresencePayload> Peers { get; init; }
}
