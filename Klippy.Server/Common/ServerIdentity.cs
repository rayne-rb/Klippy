using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace Klippy.Server.Common;

/// <summary>
/// Who this server is on the network. Both the discovery beacon and the link welcome
/// message need it, so it lives outside either slice.
///
/// The id is generated once and kept next to the app's data, so a device that paired
/// yesterday still recognises this server after a restart or a DHCP address change.
/// </summary>
public sealed class ServerIdentity
{
    private readonly ILogger<ServerIdentity> _logger;

    public ServerIdentity(IConfiguration configuration, ILogger<ServerIdentity> logger)
    {
        _logger = logger;
        Name = configuration["Server:Name"] is { Length: > 0 } configured
            ? configured
            : Environment.MachineName;
        ServerId = LoadOrCreateServerId();
    }

    public string ServerId { get; }

    public string Name { get; }

    /// <summary>
    /// The port the app is actually listening on. Set during startup once Kestrel has
    /// bound, because the configured URL may say port 0 or use a wildcard host.
    /// </summary>
    public int HttpPort { get; private set; }

    public void SetHttpPort(int port) => HttpPort = port;

    /// <summary>Base URL a device on the LAN should call, using this machine's routable address.</summary>
    public string BaseUrl => $"http://{GetLanAddress()}:{HttpPort}";

    public string WebSocketUrl => $"ws://{GetLanAddress()}:{HttpPort}/api/link/ws";

    /// <summary>
    /// First IPv4 address on an up, non-loopback interface. Beacons carry a concrete
    /// address rather than a host name so the client never has to resolve anything.
    /// </summary>
    public static IPAddress GetLanAddress()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(nic => nic.OperationalStatus == OperationalStatus.Up)
            .Where(nic => nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
            .Select(addr => addr.Address)
            .Where(addr => addr.AddressFamily == AddressFamily.InterNetwork)
            .Where(addr => !IPAddress.IsLoopback(addr))
            .ToList();

        // Prefer a private-range address: on a machine with a VPN or container bridge
        // up, the first interface is often not the one the phone can reach.
        return candidates.FirstOrDefault(IsPrivate)
               ?? candidates.FirstOrDefault()
               ?? IPAddress.Loopback;
    }

    private static bool IsPrivate(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes[0] switch
        {
            10 => true,
            172 => bytes[1] >= 16 && bytes[1] <= 31,
            192 => bytes[1] == 168,
            _ => false,
        };
    }

    private string LoadOrCreateServerId()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Klippy");
        var path = Path.Combine(directory, "server-id");

        try
        {
            if (File.Exists(path))
            {
                var existing = File.ReadAllText(path).Trim();
                if (Guid.TryParse(existing, out var parsed))
                {
                    return parsed.ToString("n");
                }
            }

            Directory.CreateDirectory(directory);
            var created = Guid.NewGuid().ToString("n");
            File.WriteAllText(path, created);
            return created;
        }
        catch (IOException ex)
        {
            // A per-run id still works; devices just re-discover instead of recognising us.
            _logger.LogWarning(ex, "Could not persist the server id at {Path}; using a transient one.", path);
            return Guid.NewGuid().ToString("n");
        }
    }
}
