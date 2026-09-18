using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Klippy.Tests.Link;

/// <summary>
/// The account boundary, tested directly.
///
/// This is the rule the whole clipboard rests on: a device reaches the rest of its own
/// account and nothing else. It used to be that every paired device shared one flat
/// space — broadcast went to everyone and a targeted envelope could name anyone — so
/// these are the tests that say it no longer does.
/// </summary>
public sealed class LinkRoutingTests
{
    private static readonly Guid Tulonga = Guid.NewGuid();
    private static readonly Guid Sam = Guid.NewGuid();

    [Fact]
    public async Task Broadcast_reaches_the_senders_own_account_only()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var phone = world.Connect("tulonga's phone", Tulonga);
        var stranger = world.Connect("sam's pc", Sam);

        world.Registry.BroadcastToGroup(Tulonga, Envelope("pet.stats"), exceptDeviceId: pc.DeviceId);

        Assert.NotNull(await phone.Socket.NextAsync());
        Assert.False(await stranger.Socket.ReceivedAnythingAsync());
        Assert.False(await pc.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_targeted_envelope_will_not_cross_accounts()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's phone", Sam);

        // Exactly the shape of the hole this closes: one account's Companion naming
        // another account's phone, which used to be delivered.
        var delivered = world.Registry.TrySendWithinGroup(
            theirs.DeviceId, senderOwner: Tulonga, Envelope(KlippyEvents.ClipboardApply));

        Assert.False(delivered);
        Assert.False(await theirs.Socket.ReceivedAnythingAsync());
        Assert.False(await mine.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_targeted_envelope_reaches_a_device_in_the_same_account()
    {
        using var world = new World();
        var phone = world.Connect("tulonga's phone", Tulonga);

        var delivered = world.Registry.TrySendWithinGroup(
            phone.DeviceId, senderOwner: Tulonga, Envelope(KlippyEvents.ClipboardApply));

        Assert.True(delivered);
        Assert.NotNull(await phone.Socket.NextAsync());
    }

    [Fact]
    public async Task An_unclaimed_device_can_reach_nobody()
    {
        using var world = new World();
        var claimed = world.Connect("tulonga's pc", Tulonga);
        var unclaimed = world.Connect("just paired", ownerUserId: null);

        // A device nobody has approved is a group of one. It is not a member of every
        // group, which is the mistake a null owner could quietly become.
        var delivered = world.Registry.TrySendWithinGroup(
            claimed.DeviceId, senderOwner: unclaimed.OwnerUserId, Envelope("pet.feed"));

        Assert.False(delivered);
        Assert.False(await claimed.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public void Peers_lists_the_rest_of_the_account_and_nobody_else()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var phone = world.Connect("tulonga's phone", Tulonga);
        world.Connect("sam's pc", Sam);

        var peers = world.Registry.PeersOf(pc.DeviceId);

        Assert.Equal([phone.DeviceId.ToString()], peers.Select(p => p.DeviceId));
    }

    [Fact]
    public void An_unclaimed_device_has_no_peers()
    {
        using var world = new World();
        world.Connect("tulonga's pc", Tulonga);
        var unclaimed = world.Connect("just paired", ownerUserId: null);

        // Not even the other unclaimed devices: "no account" is not itself an account.
        world.Connect("also just paired", ownerUserId: null);

        Assert.Empty(world.Registry.PeersOf(unclaimed.DeviceId));
    }

    [Fact]
    public void Connected_groups_and_their_devices_are_reported_per_account()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var phone = world.Connect("tulonga's phone", Tulonga);
        var stranger = world.Connect("sam's pc", Sam);
        world.Connect("just paired", ownerUserId: null);

        // Both sides sorted: these come out of a concurrent dictionary and the order is
        // not something the registry promises or that anything relies on.
        Assert.Equal(
            new[] { Tulonga, Sam }.Order(),
            world.Registry.ConnectedGroups().Order());

        Assert.Equal(
            new[] { pc.DeviceId, phone.DeviceId }.Order(),
            world.Registry.DeviceIdsInGroup(Tulonga).Order());

        Assert.Equal([stranger.DeviceId], world.Registry.DeviceIdsInGroup(Sam));
    }

    [Fact]
    public async Task Broadcast_without_a_group_still_reaches_everyone()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        // The server's own reach is deliberately unchanged. It is what the market's
        // payouts and the server's own announcements ride on.
        world.Registry.Broadcast(Envelope(KlippyEvents.LinkPing));

        Assert.NotNull(await mine.Socket.NextAsync());
        Assert.NotNull(await theirs.Socket.NextAsync());
    }

    [Fact]
    public async Task A_visitor_is_not_told_the_households_business()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var guest = world.Connect("a friend's pc", Tulonga, DeviceKind.Visitor);

        // Approving a visitor puts it in the approver's account, so it is in the group by
        // every measure routing has. What keeps it out is the kind, not the account.
        world.Registry.BroadcastToGroup(Tulonga, Envelope(KlippyEvents.ClipboardEntry), pc.DeviceId);
        world.Registry.BroadcastToGroup(Tulonga, Envelope(KlippyEvents.PetStats), pc.DeviceId);
        world.Registry.BroadcastToGroup(Tulonga, Envelope(KlippyEvents.AudioCastState), pc.DeviceId);

        Assert.False(await guest.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_visitor_is_told_what_the_visit_needs()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var guest = world.Connect("a friend's pc", Tulonga, DeviceKind.Visitor);

        // Presence, so it can find the Companion to address and notice it leaving.
        world.Registry.BroadcastToGroup(Tulonga, Envelope(KlippyEvents.DeviceConnected), pc.DeviceId);
        Assert.NotNull(await guest.Socket.NextAsync());

        // And the host's half of the visit, addressed straight at it.
        Assert.True(world.Registry.TrySendWithinGroup(
            guest.DeviceId, Tulonga, Envelope(KlippyEvents.VisitArrived)));
        Assert.NotNull(await guest.Socket.NextAsync());
    }

    [Fact]
    public async Task A_visitor_cannot_be_handed_a_stream_offer()
    {
        using var world = new World();
        var guest = world.Connect("a friend's pc", Tulonga, DeviceKind.Visitor);

        // The offer carries the ephemeral key for this PC's system audio. It is sent
        // straight at a device rather than published, so this path needs the check too.
        Assert.False(world.Registry.SendTo(guest.DeviceId, Envelope(KlippyEvents.AudioCastOffer)));
        Assert.False(await guest.Socket.ReceivedAnythingAsync());
    }

    private static LinkEnvelope Envelope(string type) => LinkEnvelope.Create(type);

    /// <summary>A registry with connections in it, each pumping into a socket we can read.</summary>
    private sealed class World : IDisposable
    {
        private readonly List<LinkConnection> _connections = [];
        private readonly CancellationTokenSource _cts = new();

        public LinkRegistry Registry { get; } = new(NullLogger<LinkRegistry>.Instance);

        public (Guid DeviceId, Guid? OwnerUserId, FakeSocket Socket) Connect(
            string name, Guid? ownerUserId, string deviceKind = DeviceKind.Companion)
        {
            var socket = new FakeSocket();
            var connection = new LinkConnection(
                Guid.NewGuid(), deviceKind, name, ownerUserId, socket, NullLogger.Instance);

            Registry.AddAsync(connection).GetAwaiter().GetResult();
            _connections.Add(connection);

            // The send loop is what moves an enqueued envelope onto the socket, which is
            // where these tests observe it.
            _ = connection.RunSendLoopAsync(_cts.Token);

            return (connection.DeviceId, ownerUserId, socket);
        }

        public void Dispose()
        {
            _cts.Cancel();

            foreach (var connection in _connections)
            {
                connection.SignalClosed();
            }

            _cts.Dispose();
        }
    }
}
