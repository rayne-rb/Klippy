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

    /// <summary>
    /// The account this device belongs to, or null when no one has claimed it yet. A
    /// device with no account is a group of one: its peer list is empty and its events
    /// reach nobody, so the apps use this to say why rather than look broken.
    /// </summary>
    public string? OwnerName { get; init; }

    public required IReadOnlyList<DevicePresencePayload> Peers { get; init; }

    /// <summary>
    /// The Companions on this server owned by <em>other</em> accounts: the friends this
    /// device could knock on for a visit. Empty for a phone, and for a device nobody has
    /// claimed. Kept apart from <see cref="Peers"/> on purpose — see
    /// <see cref="Link.KlippyEvents.VisitNeighbors"/>.
    ///
    /// Not required, so a device built before neighbours existed still reads a welcome.
    /// </summary>
    public IReadOnlyList<VisitNeighborPayload> Neighbors { get; init; } = [];
}

/// <summary>An item you listed on the market sold. See <see cref="Link.KlippyEvents.MarketPayout"/>.</summary>
public sealed record MarketPayoutPayload
{
    public required string PayoutId { get; init; }
    public required string ItemType { get; init; }
    public required int Price { get; init; }
}

/// <summary>Confirms a <see cref="MarketPayoutPayload"/> was applied, so the server stops resending it.</summary>
public sealed record MarketPayoutAckPayload
{
    public required string PayoutId { get; init; }
}

/// <summary>
/// How a visiting pet should look on the host's monitor. Cosmetic ids are catalog
/// ids the host resolves against its own copies of the same catalogs, falling back
/// to the defaults for anything it does not recognise (an older host meeting a
/// newer visitor, say).
/// </summary>
public sealed record VisitArrivePayload
{
    /// <summary>The visitor device's own name, e.g. "Klippy on Alice" — for log lines and host UI.</summary>
    public required string VisitorName { get; init; }

    public required string BodyId { get; init; }
    public required string ExpressionId { get; init; }
    public required string EyesId { get; init; }
    public required string PupilsId { get; init; }
    public required string HatId { get; init; }

    /// <summary>The pet's window size in pixels; the host mirrors it so he lands the size he left.</summary>
    public required int Size { get; init; }
}

/// <summary>
/// One Klippy on this server that belongs to somebody else. Carries the owner's name
/// as well as the device's, because "Klippy on studio-pc" means nothing to a visitor
/// who has to decide whose monitor they are about to stand on.
/// </summary>
public sealed record VisitNeighborPayload
{
    public required string DeviceId { get; init; }
    public required string DeviceName { get; init; }

    /// <summary>The account that owns it. Never null: an unclaimed device is nobody's friend.</summary>
    public required string OwnerName { get; init; }
}

/// <summary>Who a Companion may visit, as a whole list. See <see cref="Link.KlippyEvents.VisitNeighbors"/>.</summary>
public sealed record VisitNeighborsPayload
{
    public required IReadOnlyList<VisitNeighborPayload> Neighbors { get; init; }
}
