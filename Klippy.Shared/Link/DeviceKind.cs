namespace Klippy.Shared.Link;

/// <summary>What kind of thing is on the other end of a link.</summary>
public static class DeviceKind
{
    public const string Companion = "companion";
    public const string Mobile = "mobile";

    /// <summary>
    /// Another user's Companion, paired so its pet can visit this server's monitor.
    /// It speaks only the visit events and is revoked like any other device.
    /// </summary>
    public const string Visitor = "visitor";

    public static bool IsKnown(string? value) =>
        value is Companion or Mobile or Visitor;
}
