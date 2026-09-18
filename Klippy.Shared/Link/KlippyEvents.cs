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

    // ---- Clipboard --------------------------------------------------------------
    //
    // None of these carry what was copied. Reading and writing entries is plain
    // request/response and goes over HTTP (/api/clipboard), for the same reason the audio
    // cast keeps its bytes off this socket, plus one of its own: EventDispatcher persists
    // every payload that crosses the Link into link_events, and a clipboard archived
    // forever is every password its owner ever copied. What travels here is the fact that
    // something changed, and an id to go and fetch.

    /// <summary>
    /// Server to an account's devices, or to everyone for a server-wide entry: something
    /// was copied. Payload: <see cref="Clipboard.ClipboardEntryPayload"/>. A device that
    /// cares refetches the board; the payload itself is metadata only.
    /// </summary>
    public const string ClipboardEntry = "clipboard.entry";

    /// <summary>
    /// Server to the same audience: an entry is gone. Payload:
    /// <see cref="Clipboard.ClipboardRemovedPayload"/>.
    /// </summary>
    public const string ClipboardRemoved = "clipboard.removed";

    /// <summary>
    /// Device to one device of its own account, targeted: put this on your clipboard.
    /// Payload: <see cref="Clipboard.ClipboardApplyPayload"/>.
    ///
    /// Routing refuses to carry this across accounts (see LinkRegistry.TrySendWithinGroup),
    /// which is the whole of why nobody can paste into a stranger's machine.
    /// </summary>
    public const string ClipboardApply = "clipboard.apply";

    /// <summary>
    /// Device to server: my clipboard skill is on or off, and this is who I copy for.
    /// Payload: <see cref="Clipboard.ClipboardSharingPayload"/>.
    /// </summary>
    public const string ClipboardSharing = "clipboard.sharing";

    /// <summary>
    /// Companion to server: I credited myself for this payout, stop resending it.
    /// Payload: <see cref="Payloads.MarketPayoutAckPayload"/>.
    /// </summary>
    public const string MarketPayoutAck = "market.payout.ack";

    // ---- Visits -----------------------------------------------------------------
    //
    // A visit connects two Companion devices paired to the same server — the
    // klippy network is the server's device list — so these ride the ordinary
    // link, always targeted at the companion on the other end. The server has no
    // handler for any of them — it only routes; both ends are Companions. Nothing
    // here is queued or caught up on: a visit is a live moment, and if it is
    // missed the pet simply never left home.

    /// <summary>
    /// Summoner to the chosen companion, targeted: I picked your monitor — open
    /// your half of the friend portal. Answered by nothing; the portals open
    /// together and each side manages its own half from here.
    /// </summary>
    public const string VisitOpen = "visit.open";

    /// <summary>
    /// Summoner to the chosen companion, targeted: take your half of the friend
    /// portal back down. No payload.
    /// </summary>
    public const string VisitClose = "visit.close";

    /// <summary>
    /// Visitor to host, targeted: my pet jumped into the friend portal and wants
    /// to appear on your monitor. Payload:
    /// <see cref="Payloads.VisitArrivePayload"/>. Answered with
    /// <see cref="VisitArrived"/>.
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

    /// <summary>
    /// Host to summoner, targeted: not right now. No payload. Sent when the person at
    /// the other monitor turns a knock down, so the summoner can take its own half of
    /// the doorway back down instead of waiting on a pet that is never going to arrive.
    /// </summary>
    public const string VisitDeclined = "visit.declined";

    /// <summary>
    /// Server to one Companion: the Companions on this server that belong to
    /// <em>other</em> accounts — the friends it may visit. Payload:
    /// <see cref="Payloads.VisitNeighborsPayload"/>, also carried in the welcome.
    ///
    /// Presence and this are deliberately two different lists.
    /// <see cref="DeviceConnected"/> and the welcome's peers stay inside one account,
    /// because that is what the clipboard and the audio cast are routed by; a friend
    /// is not a peer and never becomes one. All this says is "there is a Klippy over
    /// there you could knock on", which is the least a visit can be built from.
    ///
    /// Resent in full whenever the connected set changes, so it is never patched and
    /// never drifts.
    /// </summary>
    public const string VisitNeighbors = "visit.neighbors";
}
