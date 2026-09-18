using Klippy.Shared.Link;

namespace Klippy.Server.Features.Visits;

/// <summary>
/// The one thing that may cross the account boundary, and the whole of what that means.
///
/// Everything else on this server is routed by account: a device reaches the rest of its
/// own account and nothing else, which is what makes "my clipboard" mean something and
/// what stops an audio relay being aimed at a stranger's phone. A visit is the deliberate
/// exception, because the whole point of it is somebody else's monitor.
///
/// So it is spelled out here rather than loosened over there. A visit may cross when, and
/// only when:
/// <list type="bullet">
/// <item>the event is one of the <c>visit.*</c> names below — a whitelist, so a feature
/// added next year is closed across accounts until somebody decides otherwise;</item>
/// <item>both ends are Companions — a phone neither hosts a pet nor sends one, and
/// nothing about a visit should be addressable at one;</item>
/// <item>both ends belong to an account — an unclaimed device is a group of one, and a
/// group of one has no friends.</item>
/// </list>
///
/// What this does <em>not</em> decide is whether the visit is welcome. That is the host's
/// to answer, on the host's own machine: the Companion knocks before it opens a door for
/// a stranger (see VisitHost.gd). The server carries the knock; it does not answer it.
/// </summary>
public static class VisitPolicy
{
    /// <summary>
    /// The events a visit is made of. Both directions are here because both halves of the
    /// doorway are: the summoner asks and recalls, the host answers and reports.
    /// </summary>
    private static readonly HashSet<string> CrossesAccounts =
    [
        KlippyEvents.VisitOpen,
        KlippyEvents.VisitClose,
        KlippyEvents.VisitArrive,
        KlippyEvents.VisitArrived,
        KlippyEvents.VisitRecall,
        KlippyEvents.VisitDeparted,
        KlippyEvents.VisitSpeak,
        KlippyEvents.VisitDeclined,
    ];

    /// <summary>Whether this event is allowed out of the sender's account at all.</summary>
    public static bool MayCrossAccounts(string eventType) => CrossesAccounts.Contains(eventType);

    /// <summary>
    /// Whether a device of this kind can be either end of a visit. Both ends are asked,
    /// so a phone can neither send one nor be sent one.
    /// </summary>
    public static bool CanTakePart(string deviceKind) => deviceKind == DeviceKind.Companion;
}
