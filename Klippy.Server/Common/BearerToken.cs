namespace Klippy.Server.Common;

/// <summary>
/// Reads a device's bearer token from a request: the Authorization header normally,
/// or the query string for clients that cannot set headers on a WebSocket upgrade.
/// Shared by every endpoint that authenticates a device the way <c>/api/link/ws</c> does.
/// </summary>
public static class BearerToken
{
    public static string? Read(HttpContext context)
    {
        var header = context.Request.Headers.Authorization.ToString();
        if (header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return header["Bearer ".Length..].Trim();
        }

        return context.Request.Query["token"].FirstOrDefault();
    }
}
