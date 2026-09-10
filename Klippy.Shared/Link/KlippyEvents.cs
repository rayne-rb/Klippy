namespace Klippy.Shared.Link;

/// <summary>
/// Event names carried in <see cref="LinkEnvelope.Type"/>.
///
/// Naming is "<![CDATA[<area>.<thing>[.<verb>]]]>". Past tense means "this happened"
/// and is safe to ignore; imperative means "please do this" and is addressed at a
/// device that can act on it. A feature slice adds its own names here alongside the
/// payload records it owns.
/// </summary>
public static class KlippyEvents
{
    // ---- Reported by the Companion, of interest to everyone -------------------

    /// <summary>Pet vitals changed. Payload: <see cref="Payloads.PetStatsPayload"/>.</summary>
    public const string PetStats = "pet.stats";

    /// <summary>The pet starved or was thrown to death. No payload.</summary>
    public const string PetDied = "pet.died";

    /// <summary>The pet was brought back. No payload.</summary>
    public const string PetRevived = "pet.revived";

    /// <summary>The pet said something out loud. Payload: <see cref="Payloads.SayPayload"/>.</summary>
    public const string PetSpoke = "pet.spoke";

    // ---- Commands aimed at the Companion --------------------------------------

    /// <summary>Drop a food item next to the pet. Payload: <see cref="Payloads.FeedPayload"/> (optional).</summary>
    public const string PetFeed = "pet.feed";

    /// <summary>Make the pet say something. Payload: <see cref="Payloads.SayPayload"/>.</summary>
    public const string PetSay = "pet.say";

    /// <summary>Turn DVD-bounce mode on or off. Payload: <see cref="Payloads.TogglePayload"/>.</summary>
    public const string PetDvdToggle = "pet.dvd.toggle";

    /// <summary>Ask the Companion to report its current vitals. No payload.</summary>
    public const string PetStatsRequest = "pet.stats.request";

    // ---- Link lifecycle, emitted by the server --------------------------------

    /// <summary>A device came online. Payload: <see cref="Payloads.DevicePresencePayload"/>.</summary>
    public const string DeviceConnected = "device.connected";

    /// <summary>A device went away. Payload: <see cref="Payloads.DevicePresencePayload"/>.</summary>
    public const string DeviceDisconnected = "device.disconnected";

    /// <summary>Sent to a device right after its socket opens. Payload: <see cref="Payloads.WelcomePayload"/>.</summary>
    public const string LinkWelcome = "link.welcome";

    /// <summary>Keepalive, either direction. No payload.</summary>
    public const string LinkPing = "link.ping";

    /// <summary>Reply to <see cref="LinkPing"/>. No payload.</summary>
    public const string LinkPong = "link.pong";
}
