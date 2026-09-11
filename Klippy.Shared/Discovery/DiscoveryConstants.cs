namespace Klippy.Shared.Discovery;

/// <summary>
/// Zero-configuration discovery over UDP multicast: the server announces itself on a
/// fixed group and also answers direct probes, so a device that just launched does not
/// have to wait for the next scheduled beacon.
///
/// Multicast rather than 255.255.255.255 broadcast because broadcast is dropped by a
/// good number of Wi-Fi drivers and by Android, whereas a joined multicast group is
/// delivered on every platform the three apps run on.
/// </summary>
public static class DiscoveryConstants
{
    /// <summary>Administratively-scoped IPv4 multicast group (RFC 2365), picked to be unused.</summary>
    public const string MulticastAddress = "239.255.71.84";

    public const int Port = 47814;

    /// <summary>Sent by a device that wants an immediate answer instead of waiting for a beacon.</summary>
    public const string ProbeMagic = "KLIPPY-DISCOVER/1";

    /// <summary>Prefix on every beacon datagram, so foreign traffic on the group is cheap to reject.</summary>
    public const string BeaconMagic = "KLIPPY-SERVER/1";

    /// <summary>How often the server re-announces itself.</summary>
    public static readonly TimeSpan BeaconInterval = TimeSpan.FromSeconds(3);

    /// <summary>A server not heard from within this window is treated as gone.</summary>
    public static readonly TimeSpan BeaconTimeout = TimeSpan.FromSeconds(12);

    /// <summary>Enough hops to cross a home network's switches without escaping it.</summary>
    public const int MulticastTtl = 2;
}
