using Klippy.Shared.Link;

namespace Klippy.Server.Features.Link;

/// <summary>
/// What a visiting device is allowed to say and hear.
///
/// A visitor is another person's Companion, paired here only so their pet can stand on
/// this monitor. <see cref="DeviceKind.Visitor"/> already says it "speaks only the visit
/// events" — this is where that stops being a comment.
///
/// It needs saying in code because approving a visitor puts it in the approver's account,
/// and an account is what the link routes by. Without this, a friend's machine is a full
/// member of the household: it could read the clipboard, and it could ask the server to
/// cast this PC's system audio to it. Both were true, and neither was noticed, because
/// nothing anywhere looked at the kind of device it was talking to.
///
/// A whitelist rather than a blacklist, deliberately: a new feature is then closed to
/// visitors until somebody decides otherwise, instead of open until somebody remembers.
/// </summary>
public static class VisitorPolicy
{
    /// <summary>
    /// What a visitor may send. Its own half of the visit and nothing else — the pet
    /// arriving, being called home, and speaking while it is here.
    ///
    /// Keepalives are absent because they never reach routing; see
    /// <c>LinkEndpoints.ReceiveLoopAsync</c>, which answers them itself.
    /// </summary>
    private static readonly HashSet<string> Sendable =
    [
        KlippyEvents.VisitArrive,
        KlippyEvents.VisitRecall,
        KlippyEvents.VisitSpeak,
    ];

    /// <summary>
    /// What a visitor may be told. The host's half of the visit, plus presence — it has
    /// to learn which device here is the Companion to address, and to notice when that
    /// Companion goes away mid-visit.
    ///
    /// Everything else an account broadcasts — vitals, who is listening to the audio,
    /// that something was copied — is the household's business, not a guest's.
    /// </summary>
    private static readonly HashSet<string> Receivable =
    [
        KlippyEvents.VisitArrived,
        KlippyEvents.VisitDeparted,
        KlippyEvents.DeviceConnected,
        KlippyEvents.DeviceDisconnected,
        KlippyEvents.LinkWelcome,
    ];

    /// <summary>Whether a device of <paramref name="deviceKind"/> may send this event.</summary>
    public static bool MaySend(string deviceKind, string eventType) =>
        deviceKind != DeviceKind.Visitor || Sendable.Contains(eventType);

    /// <summary>Whether a device of <paramref name="deviceKind"/> may be delivered this event.</summary>
    public static bool MayReceive(string deviceKind, string eventType) =>
        deviceKind != DeviceKind.Visitor || Receivable.Contains(eventType);

    /// <summary>
    /// Whether a device may use the features that belong to an account rather than to the
    /// link — the clipboard, the audio cast. Read by the HTTP endpoints, which a visitor
    /// can reach with its token without going near a socket.
    /// </summary>
    public static bool MayUseAccountFeatures(string deviceKind) =>
        deviceKind != DeviceKind.Visitor;

    /// <summary>What to tell a visitor that tried anyway.</summary>
    public const string Refusal =
        "This device is paired as a visitor, which can only take part in a visit.";
}
