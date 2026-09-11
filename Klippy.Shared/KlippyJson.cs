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
    public static readonly JsonSerializerOptions Options = Apply(new JsonSerializerOptions());

    /// <summary>
    /// Stamps the wire settings onto options owned by someone else, so hosts that
    /// bring their own instance still serialize identically. ASP.NET Core's HTTP
    /// JSON options are the case in point: minimal-API results ignore
    /// <see cref="Options"/> entirely, and their default is to write nulls, which
    /// GDScript's <c>Dictionary.get(key, default)</c> does not substitute for.
    /// </summary>
    public static JsonSerializerOptions Apply(JsonSerializerOptions options)
    {
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.PropertyNameCaseInsensitive = true;
        options.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        options.NumberHandling = JsonNumberHandling.AllowReadingFromString;
        return options;
    }

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static T? Deserialize<T>(string json) => JsonSerializer.Deserialize<T>(json, Options);
}
