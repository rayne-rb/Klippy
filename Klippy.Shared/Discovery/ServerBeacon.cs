using System.Text.Json.Serialization;

namespace Klippy.Shared.Discovery;

/// <summary>
/// What a Klippy server shouts onto the LAN. Kept small enough to always fit one
/// datagram, and flat enough that GDScript can read it without ceremony.
/// </summary>
public sealed record ServerBeacon
{
    [JsonPropertyName("v")]
    public int Version { get; init; } = 1;

    /// <summary>Stable per server install, so a device can recognise a server across restarts and IP changes.</summary>
    [JsonPropertyName("serverId")]
    public required string ServerId { get; init; }

    /// <summary>Shown in device pickers. Defaults to the machine's host name.</summary>
    [JsonPropertyName("name")]
    public required string Name { get; init; }

    /// <summary>Base HTTP address for the REST API, e.g. http://192.168.1.42:5217.</summary>
    [JsonPropertyName("baseUrl")]
    public required string BaseUrl { get; init; }

    /// <summary>Full WebSocket address for the link, e.g. ws://192.168.1.42:5217/api/link/ws.</summary>
    [JsonPropertyName("wsUrl")]
    public required string WsUrl { get; init; }

    /// <summary>Wire form: magic prefix, newline, JSON. The prefix keeps parsing off the hot path for foreign packets.</summary>
    public string ToDatagram() => $"{DiscoveryConstants.BeaconMagic}\n{KlippyJson.Serialize(this)}";

    /// <summary>Parses a datagram, returning null for anything that is not a well-formed beacon.</summary>
    public static ServerBeacon? TryParse(string datagram)
    {
        if (datagram is null || !datagram.StartsWith(DiscoveryConstants.BeaconMagic, StringComparison.Ordinal))
        {
            return null;
        }

        var newline = datagram.IndexOf('\n');
        if (newline < 0)
        {
            return null;
        }

        try
        {
            var beacon = KlippyJson.Deserialize<ServerBeacon>(datagram[(newline + 1)..]);
            return string.IsNullOrWhiteSpace(beacon?.ServerId) || string.IsNullOrWhiteSpace(beacon.BaseUrl)
                ? null
                : beacon;
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}
