using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text;
using Klippy.Shared;
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
    /// <summary>
    /// Resolves a server the user named, for when multicast cannot reach it: a phone
    /// on a tailnet or on mobile data, or an emulator behind user-mode NAT.
    ///
    /// Accepts what a person would actually type - "192.168.1.42", "10.0.2.2:5068",
    /// "http://box:5068" - and asks the server to identify itself, so the result is
    /// the same beacon discovery would have produced.
    /// </summary>
    public async Task<ServerBeacon?> ResolveAsync(string address, CancellationToken ct = default)
    {
        var baseUrl = NormaliseAddress(address);
        if (baseUrl is null)
        {
            return null;
        }

        try
        {
            using var http = new HttpClient { BaseAddress = new Uri(baseUrl), Timeout = TimeSpan.FromSeconds(8) };
            var beacon = await http.GetFromJsonAsync<ServerBeacon>(
                "/api/discovery/identity", KlippyJson.Options, ct);

            if (beacon is not null)
            {
                logger.LogInformation("Resolved '{Name}' at {BaseUrl}", beacon.Name, beacon.BaseUrl);
            }

            return beacon;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or UriFormatException
                                       or System.Text.Json.JsonException)
        {
            logger.LogWarning("Nothing answering as a Klippy server at {BaseUrl}", baseUrl);
            return null;
        }
    }

    /// <summary>The port the server listens on, so nobody has to type it.</summary>
    public const int DefaultServerPort = 5068;

    /// <summary>
    /// Turns whatever the user typed into a base URL, or null if it cannot be one.
    /// Handles "192.168.1.42", "10.0.2.2:5068", "http://box:5068" and "[::1]:5068".
    /// </summary>
    public static string? NormaliseAddress(string? address)
    {
        var trimmed = address?.Trim().TrimEnd('/');
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        var schemeAt = trimmed.IndexOf("://", StringComparison.Ordinal);
        var authority = schemeAt >= 0 ? trimmed[(schemeAt + 3)..] : trimmed;

        // Whether a port was given is a property of the authority alone: the colon in
        // "http://" is not one, and neither are the colons inside an IPv6 literal.
        var host = authority.Split('/')[0];
        var hasPort = host.StartsWith('[')
            ? host.Contains("]:", StringComparison.Ordinal)
            : host.Contains(':');

        if (schemeAt < 0)
        {
            trimmed = "http://" + trimmed;
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) || string.IsNullOrEmpty(uri.Host))
        {
            return null;
        }

        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
        {
            return null;
        }

        var port = hasPort ? uri.Port : DefaultServerPort;

        // IdnHost drops the brackets from an IPv6 literal, which would make the
        // result unparseable once a port is appended. Put them back.
        var resolvedHost = uri.HostNameType == UriHostNameType.IPv6 ? $"[{uri.IdnHost}]" : uri.IdnHost;

        return $"{uri.Scheme}://{resolvedHost}:{port}";
    }

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
