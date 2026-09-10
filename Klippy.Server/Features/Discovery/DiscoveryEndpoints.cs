using Klippy.Server.Common;
using Klippy.Shared.Discovery;

namespace Klippy.Server.Features.Discovery;

public static class DiscoveryEndpoints
{
    public static IEndpointRouteBuilder MapDiscoveryEndpoints(this IEndpointRouteBuilder routes)
    {
        // The same beacon the server multicasts, over HTTP.
        //
        // Multicast only reaches the local network, which leaves out a phone on a
        // tailnet or mobile data, and an emulator behind user-mode NAT. Those cases
        // need a typed address, and this turns one into the identity a device would
        // otherwise have discovered - so everything downstream is identical whether
        // the server was found or named.
        routes.MapGet("/api/discovery/identity", (ServerIdentity identity, HttpContext context) =>
        {
            // Answer with the address the caller actually used. A device reaching us
            // over Tailscale or through the emulator's NAT must keep talking to that
            // address, not the LAN one the multicast beacon advertises.
            var request = context.Request;
            var authority = request.Host.HasValue ? request.Host.Value : $"{ServerIdentity.GetLanAddress()}:{identity.HttpPort}";

            return Results.Ok(new ServerBeacon
            {
                ServerId = identity.ServerId,
                Name = identity.Name,
                BaseUrl = $"http://{authority}",
                WsUrl = $"ws://{authority}/api/link/ws",
            });
        }).WithTags("Discovery");

        return routes;
    }
}
