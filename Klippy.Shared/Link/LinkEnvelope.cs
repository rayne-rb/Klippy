using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Klippy.Shared.Link;

/// <summary>
/// The single message shape on the wire, in both directions, for every feature.
/// Payload stays untyped here on purpose: slices own their own payload records and
/// the set of them is meant to keep growing without this type ever changing.
/// </summary>
public sealed record LinkEnvelope
{
    /// <summary>Unique per message. Used to drop echoes and to correlate replies.</summary>
    [JsonPropertyName("id")]
    public string Id { get; init; } = Guid.NewGuid().ToString("n");

    /// <summary>Event name, e.g. "pet.feed". See <see cref="KlippyEvents"/>.</summary>
    [JsonPropertyName("type")]
    public required string Type { get; init; }

    /// <summary>Device id that produced it. Null means the server itself.</summary>
    [JsonPropertyName("source")]
    public string? Source { get; init; }

    /// <summary>Device id to deliver to. Null means every other device on the pair group.</summary>
    [JsonPropertyName("target")]
    public string? Target { get; init; }

    /// <summary>Unix milliseconds.</summary>
    [JsonPropertyName("ts")]
    public long Ts { get; init; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    [JsonPropertyName("payload")]
    public JsonNode? Payload { get; init; }

    public static LinkEnvelope Create<T>(string type, T payload, string? source = null, string? target = null) => new()
    {
        Type = type,
        Source = source,
        Target = target,
        Payload = JsonSerializer.SerializeToNode(payload, KlippyJson.Options),
    };

    public static LinkEnvelope Create(string type, string? source = null, string? target = null) => new()
    {
        Type = type,
        Source = source,
        Target = target,
    };

    /// <summary>Reads the payload as <typeparamref name="T"/>, or null when it is absent or the wrong shape.</summary>
    public T? PayloadAs<T>()
    {
        if (Payload is null)
        {
            return default;
        }

        try
        {
            return Payload.Deserialize<T>(KlippyJson.Options);
        }
        catch (JsonException)
        {
            return default;
        }
    }

    public string ToJson() => KlippyJson.Serialize(this);

    /// <summary>Parses a wire message, returning null rather than throwing on malformed input.</summary>
    public static LinkEnvelope? TryParse(string json)
    {
        try
        {
            var envelope = KlippyJson.Deserialize<LinkEnvelope>(json);
            return string.IsNullOrWhiteSpace(envelope?.Type) ? null : envelope;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
