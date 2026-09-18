using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Klippy.Tests.Link;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Klippy.Tests.Visits;

/// <summary>
/// The same rule, asked the way a real socket asks it.
///
/// <see cref="VisitRoutingTests"/> tests the registry directly, which is where the rule
/// lives. This goes in through <see cref="EventDispatcher.DispatchFromDeviceAsync"/> — the
/// one path every envelope a device sends actually takes — so that the exception being
/// written correctly and the exception being reached are two different failures.
///
/// The dispatcher's other two jobs need a database and a service scope; both are absent
/// here on purpose. Persisting is best-effort and already swallows its own failures, and
/// with no handlers registered there are none to run, which leaves routing.
/// </summary>
public sealed class VisitDispatchTests
{
    private static readonly Guid Tulonga = Guid.NewGuid();
    private static readonly Guid Sam = Guid.NewGuid();

    [Fact]
    public async Task A_summons_reaches_a_friend_on_another_account()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        await Dispatcher(world).DispatchFromDeviceAsync(
            Addressed(KlippyEvents.VisitOpen, mine.DeviceId, theirs.DeviceId), Tulonga, default);

        Assert.NotNull(await theirs.Socket.NextAsync());
    }

    [Fact]
    public async Task A_paste_aimed_at_the_same_friend_does_not()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        // The devices, the route and the sender are identical to the test above. Only the
        // event is different, and that is the whole of what decides it.
        await Dispatcher(world).DispatchFromDeviceAsync(
            Addressed(KlippyEvents.ClipboardApply, mine.DeviceId, theirs.DeviceId), Tulonga, default);

        Assert.False(await theirs.Socket.ReceivedAnythingAsync());
    }

    [Fact]
    public async Task A_visit_between_your_own_machines_still_goes_the_ordinary_way()
    {
        using var world = new World();
        var pc = world.Connect("tulonga's pc", Tulonga);
        var laptop = world.Connect("tulonga's laptop", Tulonga);

        await Dispatcher(world).DispatchFromDeviceAsync(
            Addressed(KlippyEvents.VisitOpen, pc.DeviceId, laptop.DeviceId), Tulonga, default);

        Assert.NotNull(await laptop.Socket.NextAsync());
    }

    [Fact]
    public async Task An_untargeted_visit_event_reaches_no_friend()
    {
        using var world = new World();
        var mine = world.Connect("tulonga's pc", Tulonga);
        var theirs = world.Connect("sam's pc", Sam);

        // Every visit event is addressed at one companion. Dropping the target must not
        // turn one into an announcement to the whole server.
        await Dispatcher(world).DispatchFromDeviceAsync(
            LinkEnvelope.Create(KlippyEvents.VisitArrive, source: mine.DeviceId.ToString()),
            Tulonga,
            default);

        Assert.False(await theirs.Socket.ReceivedAnythingAsync());
    }

    private static EventDispatcher Dispatcher(World world) =>
        new(world.Registry,
            new ServiceCollection().BuildServiceProvider().GetRequiredService<IServiceScopeFactory>(),
            NullLogger<EventDispatcher>.Instance);

    private static LinkEnvelope Addressed(string type, Guid source, Guid target) =>
        LinkEnvelope.Create(type, source: source.ToString(), target: target.ToString());
}
