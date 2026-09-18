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

    // ---- Audio cast control ---------------------------------------------------
    //
    // Control only. The audio itself never touches this socket: events here are
    // persisted, capped at 64 KB, text-framed, and queued DropOldest — all correct
    // for state, all wrong for a stream. The bytes go over UDP; see
    // Klippy.Shared.Audio.

    /// <summary>
    /// Phone to server: begin casting to me. Payload:
    /// <see cref="Audio.AudioCastStartPayload"/>. Answered with <see cref="AudioCastOffer"/>.
    /// </summary>
    public const string AudioCastStart = "audio.cast.start";

    /// <summary>Phone to server: stop casting to me. No payload.</summary>
    public const string AudioCastStop = "audio.cast.stop";

    /// <summary>
    /// Server to one listener: the UDP port and the ephemeral key to prove itself
    /// with. Payload: <see cref="Audio.AudioCastOfferPayload"/>.
    ///
    /// Always addressed with a Target. It carries the stream key, so unlike
    /// <see cref="AudioCastState"/> it must never be broadcast.
    /// </summary>
    public const string AudioCastOffer = "audio.cast.offer";

    /// <summary>
    /// Server to everyone: what is casting and to whom. Payload:
    /// <see cref="Audio.AudioCastStatePayload"/>. Carries no key.
    /// </summary>
    public const string AudioCastState = "audio.cast.state";

    /// <summary>
    /// Companion to one phone, targeted: please start listening to this PC's audio,
    /// or stop. Payload: <see cref="Audio.AudioCastRequestPayload"/>.
    ///
    /// The phone answers it by running its own <see cref="AudioCastStart"/> negotiation,
    /// rather than the server pushing an unasked-for <see cref="AudioCastOffer"/> at it.
    /// The phone is the only end that knows whether it can actually play right now, and
    /// this way that stays true however the cast was set off.
    /// </summary>
    public const string AudioCastRequest = "audio.cast.request";

    // ---- Market ----------------------------------------------------------------
    //
    // Listing and buying are plain request/response, so they go over the HTTP API
    // (/api/market) rather than this link. Only the seller's payout rides the link:
    // it has to reach a device that may not be looking at the market, or may not
    // even be online yet, at the moment its item sells.

    /// <summary>
    /// Server to the seller, targeted: an item of yours sold. Payload:
    /// <see cref="Payloads.MarketPayoutPayload"/>. Queued server-side ("mailbox
    /// payout") and delivered both the instant a sale happens if the seller is
    /// online, and again on every reconnect until acknowledged, so it survives the
    /// seller being offline when their item sells.
    /// </summary>
    public const string MarketPayout = "market.payout";

    /// <summary>
    /// Companion to server: I credited myself for this payout, stop resending it.
    /// Payload: <see cref="Payloads.MarketPayoutAckPayload"/>.
    /// </summary>
    public const string MarketPayoutAck = "market.payout.ack";

    // ---- Visits -----------------------------------------------------------------
    //
    // A Companion whose pet has jumped into a friend portal pairs with the other
    // user's server as a "visitor" device and speaks these over that second socket,
    // always targeted at the companion hosting the visit. The server has no handler
    // for any of them — it only routes; both ends are Companions. Nothing here is
    // queued or caught up on: a visit is a live moment, and if it is missed the pet
    // simply never left home.

    /// <summary>
    /// Visitor to host, targeted: my pet jumped into the friend portal and wants to
    /// appear on your monitor. Payload: <see cref="Payloads.VisitArrivePayload"/>.
    /// Answered with <see cref="VisitArrived"/>.
    /// </summary>
    public const string VisitArrive = "visit.arrive";

    /// <summary>
    /// Host to visitor, targeted: the visiting pet is now on my screen. No payload.
    /// The visitor treats this as the proof the trip worked; without it inside a few
    /// seconds the pet pops back out of the home portal.
    /// </summary>
    public const string VisitArrived = "visit.arrived";

    /// <summary>
    /// Visitor's owner to host, targeted: send my pet home. No payload. The host
    /// plays the exit and answers with <see cref="VisitDeparted"/>.
    /// </summary>
    public const string VisitRecall = "visit.recall";

    /// <summary>
    /// Host to visitor's owner, targeted: your pet has left my screen. No payload.
    /// On receipt the owner pops the pet back out of the home portal and closes the
    /// portals behind him.
    /// </summary>
    public const string VisitDeparted = "visit.departed";

    /// <summary>
    /// Visitor's owner to host, targeted: make the visiting pet say this on the
    /// host's monitor (an owner-side reminder that came due while the pet is away).
    /// Payload: <see cref="Payloads.SayPayload"/>.
    /// </summary>
    public const string VisitSpeak = "visit.speak";
}
