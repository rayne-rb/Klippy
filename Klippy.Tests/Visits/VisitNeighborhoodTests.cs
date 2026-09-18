using Klippy.Server.Features.Visits;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;
using Klippy.Tests.Link;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Klippy.Tests.Visits;

/// <summary>
/// The friends list, and who is told about it.
///
/// A visit needs the one thing presence will not give it: knowing somebody else's Klippy
/// is out there. These say that this second list carries only that, reaches only the
/// Companions that could act on it, and keeps up when a friend comes or goes.
/// </summary>
public sealed class VisitNeighborhoodTests
{
    private static readonly Guid Tulonga = Guid.NewGuid();
    private static readonly Guid Sam = Guid.NewGuid();

    [Fact]
    public async Task A_friend_coming_online_is_announced_to_the_others()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga, ownerName: "tulonga");

        // Subscribed after our own arrival, so the only announcement in flight is the
        // one the friend causes.
        using var neighborhood = await StartAsync(world);

        var friend = world.Connect("sam's pc", Sam, ownerName: "sam");

        var announced = await ReadNeighborsAsync(mine);
        Assert.NotNull(announced);
        Assert.Equal([friend.DeviceId.ToString()], announced.Neighbors.Select(n => n.DeviceId));
        Assert.Equal("sam", announced.Neighbors[0].OwnerName);
        Assert.Equal("sam's pc", announced.Neighbors[0].DeviceName);
    }

    [Fact]
    public async Task A_friend_going_offline_is_the_list_arriving_without_them()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga, ownerName: "tulonga");
        var friend = world.Connect("sam's pc", Sam, ownerName: "sam");

        using var neighborhood = await StartAsync(world);

        // A friend's Klippy has no device.disconnected to offer another account, so the
        // whole list is how the other end finds out — which is why it is sent whole.
        await world.Registry.DisconnectAsync(friend.DeviceId);

        var announced = await ReadNeighborsAsync(mine);
        Assert.NotNull(announced);
        Assert.Empty(announced.Neighbors);
    }

    [Fact]
    public async Task A_phone_is_not_told_who_is_visitable()
    {
        using var world = new World();
        var phone = world.Connect("tulonga's phone", Tulonga, DeviceKind.Mobile);

        using var neighborhood = await StartAsync(world);

        world.Connect("sam's pc", Sam, ownerName: "sam");

        // Nothing a phone can do with it, and it is somebody else's business.
        Assert.False(await phone.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task An_unclaimed_klippy_is_not_told_either()
    {
        using var world = new World();
        var unclaimed = world.Connect("just paired", ownerUserId: null);

        using var neighborhood = await StartAsync(world);

        world.Connect("sam's pc", Sam, ownerName: "sam");

        Assert.False(await unclaimed.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task The_welcome_list_is_the_same_list()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga, ownerName: "tulonga");
        var friend = world.Connect("sam's pc", Sam, ownerName: "sam");

        var neighborhood = new VisitNeighborhood(world.Registry, NullLogger<VisitNeighborhood>.Instance);

        // What a Companion is handed on connecting and what it is pushed later come from
        // one place, so a reconnect cannot disagree with an announcement.
        var forWelcome = neighborhood.NeighborsFor(mine.DeviceId);

        Assert.Equal([friend.DeviceId.ToString()], forWelcome.Select(n => n.DeviceId));
    }

    private static async Task<Subscription> StartAsync(World world)
    {
        var neighborhood = new VisitNeighborhood(world.Registry, NullLogger<VisitNeighborhood>.Instance);
        await neighborhood.StartAsync(CancellationToken.None);
        return new Subscription(neighborhood);
    }

    /// <summary>The next announcement on this socket, or null if it was not told.</summary>
    private static async Task<VisitNeighborsPayload?> ReadNeighborsAsync(World.Device device)
    {
        var message = await device.Socket.NextAsync();
        if (message is null)
        {
            return null;
        }

        var envelope = LinkEnvelope.TryParse(message);
        Assert.Equal(KlippyEvents.VisitNeighbors, envelope?.Type);
        return envelope?.PayloadAs<VisitNeighborsPayload>();
    }

    /// <summary>Unsubscribes the neighbourhood when the test ends.</summary>
    private sealed class Subscription(VisitNeighborhood neighborhood) : IDisposable
    {
        public void Dispose() => neighborhood.StopAsync(CancellationToken.None).GetAwaiter().GetResult();
    }
}
