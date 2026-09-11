namespace Klippy.Shared.Link;

/// <summary>What kind of thing is on the other end of a link.</summary>
public static class DeviceKind
{
    public const string Companion = "companion";
    public const string Mobile = "mobile";

    public static bool IsKnown(string? value) =>
        value is Companion or Mobile;
}
