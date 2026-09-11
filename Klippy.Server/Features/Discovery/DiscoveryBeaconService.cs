using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using Klippy.Server.Common;
using Klippy.Shared.Discovery;

namespace Klippy.Server.Features.Discovery;

/// <summary>
/// Makes the server findable with no configuration on either side.
///
/// Two halves: a beacon sent to the multicast group every few seconds so anything
/// already listening notices us, and a responder that answers a device's probe
/// straight away so a freshly launched app does not sit through the beacon interval.
///
/// Sending goes out once per network interface rather than relying on the default
/// route, because on a dev machine the default route is often a VPN or a container
/// bridge the phone cannot see.
/// </summary>
public sealed class DiscoveryBeaconService(
    ServerIdentity identity,
    ILogger<DiscoveryBeaconService> logger) : BackgroundService
{
    private static readonly IPAddress GroupAddress = IPAddress.Parse(DiscoveryConstants.MulticastAddress);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // The port is only known once Kestrel has bound, and the beacon is useless
        // without it.
        while (identity.HttpPort == 0 && !stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(100, stoppingToken);
        }

        if (stoppingToken.IsCancellationRequested)
        {
            return;
        }

        using var receiver = CreateReceiver();
        var senders = CreateSenders();

        try
        {
            logger.LogInformation(
                "Discovery beacon live on {Group}:{Port} across {Count} interface(s), advertising {BaseUrl}",
                DiscoveryConstants.MulticastAddress, DiscoveryConstants.Port, senders.Count, identity.BaseUrl);

            await Task.WhenAll(
                BeaconLoopAsync(senders, stoppingToken),
                RespondLoopAsync(receiver, stoppingToken));
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
        finally
        {
            foreach (var sender in senders)
            {
                sender.Dispose();
            }
        }
    }

    private UdpClient CreateReceiver()
    {
        var receiver = new UdpClient(AddressFamily.InterNetwork);
        receiver.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        receiver.Client.Bind(new IPEndPoint(IPAddress.Any, DiscoveryConstants.Port));

        // Join on every usable interface: a single join only covers the default one.
        var joined = 0;
        foreach (var local in LocalAddresses())
        {
            try
            {
                receiver.JoinMulticastGroup(GroupAddress, local);
                joined++;
            }
            catch (SocketException ex)
            {
                logger.LogDebug(ex, "Could not join the discovery group on {Address}", local);
            }
        }

        if (joined == 0)
        {
            receiver.JoinMulticastGroup(GroupAddress);
        }

        return receiver;
    }

    private List<UdpClient> CreateSenders()
    {
        var senders = new List<UdpClient>();

        foreach (var local in LocalAddresses())
        {
            try
            {
                var sender = new UdpClient(new IPEndPoint(local, 0));
                sender.Ttl = DiscoveryConstants.MulticastTtl;
                sender.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive,
                    DiscoveryConstants.MulticastTtl);
                senders.Add(sender);
            }
            catch (SocketException ex)
            {
                logger.LogDebug(ex, "Could not open a discovery sender on {Address}", local);
            }
        }

        if (senders.Count == 0)
        {
            senders.Add(new UdpClient(AddressFamily.InterNetwork) { Ttl = DiscoveryConstants.MulticastTtl });
        }

        return senders;
    }

    private async Task BeaconLoopAsync(List<UdpClient> senders, CancellationToken ct)
    {
        var groupEndpoint = new IPEndPoint(GroupAddress, DiscoveryConstants.Port);

        while (!ct.IsCancellationRequested)
        {
            var datagram = Encoding.UTF8.GetBytes(CurrentBeacon().ToDatagram());

            foreach (var sender in senders)
            {
                try
                {
                    await sender.SendAsync(datagram, groupEndpoint, ct);
                }
                catch (SocketException ex)
                {
                    // An interface going down mid-run is routine; the others still carry.
                    logger.LogDebug(ex, "Beacon send failed on one interface");
                }
            }

            await Task.Delay(DiscoveryConstants.BeaconInterval, ct);
        }
    }

    private async Task RespondLoopAsync(UdpClient receiver, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await receiver.ReceiveAsync(ct);
            }
            catch (SocketException ex)
            {
                logger.LogDebug(ex, "Discovery receive failed; continuing");
                continue;
            }

            var text = Encoding.UTF8.GetString(result.Buffer);
            if (!text.StartsWith(DiscoveryConstants.ProbeMagic, StringComparison.Ordinal))
            {
                // Our own beacons land here too. Nothing to do with them.
                continue;
            }

            var reply = Encoding.UTF8.GetBytes(CurrentBeacon().ToDatagram());
            try
            {
                // Unicast straight back to the asker rather than re-flooding the group.
                await receiver.SendAsync(reply, result.RemoteEndPoint, ct);
                logger.LogDebug("Answered a discovery probe from {Remote}", result.RemoteEndPoint);
            }
            catch (SocketException ex)
            {
                logger.LogDebug(ex, "Could not answer a probe from {Remote}", result.RemoteEndPoint);
            }
        }
    }

    private ServerBeacon CurrentBeacon() => new()
    {
        ServerId = identity.ServerId,
        Name = identity.Name,
        BaseUrl = identity.BaseUrl,
        WsUrl = identity.WebSocketUrl,
    };

    private static IEnumerable<IPAddress> LocalAddresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(nic => nic.OperationalStatus == OperationalStatus.Up)
            .Where(nic => nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .Where(nic => nic.SupportsMulticast)
            .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
            .Select(addr => addr.Address)
            .Where(addr => addr.AddressFamily == AddressFamily.InterNetwork)
            .Where(addr => !IPAddress.IsLoopback(addr))
            .Distinct();
}
