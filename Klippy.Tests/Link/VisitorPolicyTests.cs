using Klippy.Server.Features.Link;
using Klippy.Shared.Link;
using Xunit;

namespace Klippy.Tests.Link;

/// <summary>
/// What a visiting device may say and hear.
///
/// These exist because all three of the holes they describe were real: a friend's machine,
/// paired only so their pet could stand on this monitor, could read the household's
/// clipboard and could ask the server to cast its system audio. Nothing looked at what
/// kind of device was asking.
/// </summary>
public sealed class VisitorPolicyTests
{
    [Theory]
    [InlineData(KlippyEvents.VisitArrive)]
    [InlineData(KlippyEvents.VisitRecall)]
    [InlineData(KlippyEvents.VisitSpeak)]
    public void A_visitor_may_send_its_half_of_the_visit(string eventType) =>
        Assert.True(VisitorPolicy.MaySend(DeviceKind.Visitor, eventType));

    [Theory]
    [InlineData(KlippyEvents.AudioCastStart)]
    [InlineData(KlippyEvents.ClipboardSharing)]
    [InlineData(KlippyEvents.PetFeed)]
    [InlineData(KlippyEvents.MarketPayoutAck)]
    [InlineData(KlippyEvents.PetStatsRequest)]
    public void A_visitor_may_send_nothing_else(string eventType) =>
        Assert.False(VisitorPolicy.MaySend(DeviceKind.Visitor, eventType));

    [Theory]
    [InlineData(KlippyEvents.VisitArrived)]
    [InlineData(KlippyEvents.VisitDeparted)]
    [InlineData(KlippyEvents.DeviceConnected)]
    [InlineData(KlippyEvents.DeviceDisconnected)]
    [InlineData(KlippyEvents.LinkWelcome)]
    public void A_visitor_hears_the_visit_and_who_is_here(string eventType) =>
        Assert.True(VisitorPolicy.MayReceive(DeviceKind.Visitor, eventType));

    [Theory]
    [InlineData(KlippyEvents.ClipboardEntry)]
    [InlineData(KlippyEvents.AudioCastOffer)]
    [InlineData(KlippyEvents.AudioCastState)]
    [InlineData(KlippyEvents.PetStats)]
    [InlineData(KlippyEvents.MarketPayout)]
    public void A_visitor_hears_nothing_else(string eventType) =>
        Assert.False(VisitorPolicy.MayReceive(DeviceKind.Visitor, eventType));

    [Theory]
    [InlineData(DeviceKind.Companion)]
    [InlineData(DeviceKind.Mobile)]
    public void The_households_own_devices_are_unaffected(string deviceKind)
    {
        Assert.True(VisitorPolicy.MaySend(deviceKind, KlippyEvents.AudioCastStart));
        Assert.True(VisitorPolicy.MayReceive(deviceKind, KlippyEvents.ClipboardEntry));
        Assert.True(VisitorPolicy.MayUseAccountFeatures(deviceKind));
    }

    [Fact]
    public void A_visitor_may_not_use_the_clipboard_or_the_audio_cast() =>
        // Both are reachable over HTTP with nothing but a token, so the link's rules
        // alone would not have stopped it.
        Assert.False(VisitorPolicy.MayUseAccountFeatures(DeviceKind.Visitor));

    [Fact]
    public void An_unrecognised_event_is_closed_to_a_visitor_by_default() =>
        // A whitelist, so a feature added next year is shut to guests until somebody
        // decides otherwise rather than open until somebody remembers.
        Assert.False(VisitorPolicy.MaySend(DeviceKind.Visitor, "some.future.feature"));
}
