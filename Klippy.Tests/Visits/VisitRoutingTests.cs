using Klippy.Server.Features.Visits;
using Klippy.Shared.Link;
using Klippy.Tests.Link;
using Xunit;

namespace Klippy.Tests.Visits;

/// <summary>
/// The one hole in the account boundary, tested from both sides.
///
/// <see cref="LinkRoutingTests"/> says a device reaches its own account and nothing
/// else. A visit is the deliberate exception to that — somebody else's monitor is the
/// entire point of it — so these are the tests that say exactly how wide the exception
/// is, and that it is not one inch wider. See <see cref="VisitPolicy"/>.
/// </summary>
public sealed class VisitRoutingTests
{
    private static readonly Guid Tulonga = Guid.NewGuid();
    private static readonly Guid Sam = Guid.NewGuid();

    [Fact]
    public async Task A_visit_reaches_a_friends_klippy_in_another_account()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        var delivered = world.Registry.TryVisitAcrossAccounts(
            theirs.DeviceId, mine.DeviceId, Envelope(KlippyEvents.VisitOpen));

        Assert.True(delivered);
        Assert.NotNull(await theirs.Socket.NextAsync());
    }

    [Theory]
    [InlineData(KlippyEvents.VisitOpen)]
    [InlineData(KlippyEvents.VisitClose)]
    [InlineData(KlippyEvents.VisitArrive)]
    [InlineData(KlippyEvents.VisitArrived)]
    [InlineData(KlippyEvents.VisitRecall)]
    [InlineData(KlippyEvents.VisitDeparted)]
    [InlineData(KlippyEvents.VisitSpeak)]
    [InlineData(KlippyEvents.VisitDeclined)]
    public void Every_step_of_a_visit_may_cross(string eventType)
    {
        // Both directions, because both halves of the doorway are: a visit that could be
        // opened but not answered would strand a pet on a stranger's screen.
        Assert.True(VisitPolicy.MayCrossAccounts(eventType));
    }

    [Theory]
    [InlineData(KlippyEvents.ClipboardApply)]
    [InlineData(KlippyEvents.PetStats)]
    [InlineData(KlippyEvents.PetFeed)]
    [InlineData(KlippyEvents.AudioCastRequest)]
    [InlineData(KlippyEvents.MarketPayout)]
    public async Task Nothing_but_a_visit_crosses_the_boundary(string eventType)
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        // Two Companions that may visit each other, which is the point: being allowed to
        // send a pet over is not being allowed to paste into their machine or aim their
        // audio at yourself.
        var delivered = world.Registry.TryVisitAcrossAccounts(
            theirs.DeviceId, mine.DeviceId, Envelope(eventType));

        Assert.False(delivered);
        Assert.False(await theirs.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_visit_cannot_be_aimed_at_a_phone()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var phone = world.Connect("sam's phone", Sam, DeviceKind.Mobile);

        var delivered = world.Registry.TryVisitAcrossAccounts(
            phone.DeviceId, mine.DeviceId, Envelope(KlippyEvents.VisitArrive));

        Assert.False(delivered);
        Assert.False(await phone.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_phone_cannot_send_one_either()
    {
        using var world = new World();
        var phone = world.Connect("tulonga's phone", Tulonga, DeviceKind.Mobile);
        var theirs = world.Connect("sam's pc", Sam);

        // The exception is between Companions. A phone holding a token is not a way
        // around that.
        var delivered = world.Registry.TryVisitAcrossAccounts(
            theirs.DeviceId, phone.DeviceId, Envelope(KlippyEvents.VisitArrive));

        Assert.False(delivered);
        Assert.False(await theirs.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_visit_needs_both_ends_claimed()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var unclaimed = world.Connect("just paired", ownerUserId: null);

        // An unclaimed device is a group of one, and a group of one has no friends —
        // in either direction, so pairing a machine and never approving it is not a way
        // onto somebody's monitor.
        Assert.False(world.Registry.TryVisitAcrossAccounts(
            unclaimed.DeviceId, mine.DeviceId, Envelope(KlippyEvents.VisitOpen)));
        Assert.False(world.Registry.TryVisitAcrossAccounts(
            mine.DeviceId, unclaimed.DeviceId, Envelope(KlippyEvents.VisitOpen)));

        Assert.False(await unclaimed.Socket.ReceivedAnythingAsync());
        Assert.False(await mine.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public void Your_own_machines_never_come_through_the_exception()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var laptop = world.Connect("tulonga's laptop", Tulonga);

        // Visiting your own laptop is ordinary same-account delivery and has already
        // happened by the time anything asks this. Answering true here as well would
        // make the boundary look like it was crossed when it never was.
        Assert.False(world.Registry.TryVisitAcrossAccounts(
            laptop.DeviceId, pc.DeviceId, Envelope(KlippyEvents.VisitOpen)));
    }

    [Fact]
    public void Friends_are_the_other_accounts_klippys()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        world.Connect("tulonga's laptop", Tulonga);
        world.Connect("tulonga's phone", Tulonga, DeviceKind.Mobile);
        world.Connect("sam's phone", Sam, DeviceKind.Mobile);
        var friend = world.Connect("sam's pc", Sam, ownerName: "sam");

        var friends = world.Registry.CompanionsOutsideAccount(pc.DeviceId);

        // Not your own machines (those are peers), and not anybody's phone.
        Assert.Equal([friend.DeviceId], friends.Select(c => c.DeviceId));
        Assert.Equal("sam", friends[0].OwnerName);
    }

    [Fact]
    public void A_phone_and_an_unclaimed_klippy_have_no_friends()
    {
        using var world = new World();
        world.Connect("sam's pc", Sam);
        var phone = world.Connect("tulonga's phone", Tulonga, DeviceKind.Mobile);
        var unclaimed = world.Connect("just paired", ownerUserId: null);

        Assert.Empty(world.Registry.CompanionsOutsideAccount(phone.DeviceId));
        Assert.Empty(world.Registry.CompanionsOutsideAccount(unclaimed.DeviceId));
    }

    private static LinkEnvelope Envelope(string type) => LinkEnvelope.Create(type);
}
