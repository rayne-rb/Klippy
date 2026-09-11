using Xunit;

namespace Klippy.Tests.AudioCast.Probe;

/// <summary>
/// The probe's argument handling is the one part of it with no audio device, no server
/// and no timing in the way, so it is the part a test can pin down. Everything else in
/// <c>Probe</c> is driven by hand from the command line.
/// </summary>
public class ProbeArgsTests
{
    [Fact]
    public void Value_returns_the_token_after_the_flag()
    {
        Assert.Equal("out.wav", ProbeArgs.Value(["capture", "--out", "out.wav"], "--out"));
    }

    [Fact]
    public void Value_is_null_when_the_flag_is_absent()
    {
        Assert.Null(ProbeArgs.Value(["capture"], "--out"));
    }

    [Fact]
    public void Value_is_null_when_the_flag_is_last_and_has_no_argument()
    {
        Assert.Null(ProbeArgs.Value(["capture", "--out"], "--out"));
    }

    [Fact]
    public void Flag_reports_presence_only()
    {
        Assert.True(ProbeArgs.Flag(["capture", "--play"], "--play"));
        Assert.False(ProbeArgs.Flag(["capture"], "--play"));
    }

    [Fact]
    public void Channels_defaults_to_stereo()
    {
        Assert.Equal(2, ProbeArgs.Channels(["capture"]));
        Assert.Equal(1, ProbeArgs.Channels(["capture", "--channels", "1"]));
    }

    [Fact]
    public void Seconds_falls_back_when_unspecified()
    {
        Assert.Equal(5.0, ProbeArgs.Seconds(["capture"], 5.0));
        Assert.Equal(3.0, ProbeArgs.Seconds(["capture", "--seconds", "3"], 5.0));
    }
}
