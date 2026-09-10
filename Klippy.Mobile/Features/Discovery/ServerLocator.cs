using System.Net;
using System.Net.Sockets;
using System.Text;
using Klippy.Shared.Discovery;

namespace Klippy.Mobile.Features.Discovery;

/// <summary>
/// Finds the Klippy server on the local network so the user never types an address.
///
/// We send a probe to the multicast group and wait for the server's unicast reply,
/// rather than listening for its periodic beacon. That matters on Android: incoming
/// multicast is filtered unless the app holds a WifiManager multicast lock, but a
/// unicast reply to a socket we sent from is delivered normally. Same code, no
/// platform-specific lock, and it answers in milliseconds instead of up to a beacon
/// interval.
/// </summary>
public sealed class ServerLocator(ILogger<ServerLocator> logger)
{
    /// <summary>Probes until a server answers or the timeout runs out.</summary>
    public async Task<ServerBeacon?> FindAsync(TimeSpan timeout, CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);

        using var udp = new UdpClient(AddressFamily.InterNetwork);
        udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, 0));
        udp.Ttl = DiscoveryConstants.MulticastTtl;

        var group = new IPEndPoint(IPAddress.Parse(DiscoveryConstants.MulticastAddress), DiscoveryConstants.Port);
        var probe = Encoding.UTF8.GetBytes(DiscoveryConstants.ProbeMagic);

        var probing = ProbeLoopAsync(udp, group, probe, cts.Token);

        try
        {
            while (!cts.Token.IsCancellationRequested)
            {
                var result = await udp.ReceiveAsync(cts.Token);
                var beacon = ServerBeacon.TryParse(Encoding.UTF8.GetString(result.Buffer));
                if (beacon is not null)
                {
                    logger.LogInformation("Found '{Name}' at {BaseUrl}", beacon.Name, beacon.BaseUrl);
                    await cts.CancelAsync();
                    return beacon;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Timed out with nothing found.
        }
        catch (SocketException ex)
        {
            logger.LogWarning(ex, "Discovery socket failed");
        }
        finally
        {
            await cts.CancelAsync();
            try
            {
                await probing;
            }
            catch (OperationCanceledException)
            {
                // Expected.
            }
        }

        return null;
    }

    private static async Task ProbeLoopAsync(UdpClient udp, IPEndPoint group, byte[] probe, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await udp.SendAsync(probe, group, ct);
            }
            catch (SocketException)
            {
                // Wi-Fi may not be up yet; the next attempt can succeed.
            }

            await Task.Delay(TimeSpan.FromSeconds(1), ct);
        }
    }
}
