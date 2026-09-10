using System.Text.Json;
using System.Text.Json.Serialization;

namespace Klippy.Shared;

/// <summary>
/// One serializer configuration for everything that crosses the wire. The Companion
/// parses this JSON in GDScript, so the shape has to stay boring: camelCase names,
/// no type discriminators, no reference handling.
/// </summary>
public static class KlippyJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static T? Deserialize<T>(string json) => JsonSerializer.Deserialize<T>(json, Options);
}
