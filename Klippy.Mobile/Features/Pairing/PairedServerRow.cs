using RepoDb.Attributes;

namespace Klippy.Mobile.Features.Pairing;

/// <summary>The one server this phone is paired with.</summary>
[Map("paired_server")]
public sealed class PairedServerRow
{
    [Primary]
    [Map("server_id")]
    public string ServerId { get; set; } = string.Empty;

    [Map("name")]
    public string Name { get; set; } = string.Empty;

    [Map("base_url")]
    public string BaseUrl { get; set; } = string.Empty;

    [Map("ws_url")]
    public string WsUrl { get; set; } = string.Empty;

    [Map("device_id")]
    public string DeviceId { get; set; } = string.Empty;

    [Map("token")]
    public string Token { get; set; } = string.Empty;

    [Map("paired_at")]
    public string PairedAt { get; set; } = string.Empty;
}
