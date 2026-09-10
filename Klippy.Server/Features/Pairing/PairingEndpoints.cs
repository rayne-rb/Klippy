using Klippy.Shared.Pairing;

namespace Klippy.Server.Features.Pairing;

public static class PairingEndpoints
{
    public static IEndpointRouteBuilder MapPairingEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/pairing").WithTags("Pairing");

        // A device asks to be let in. Unauthenticated by definition: this is the only
        // way a device with no token can talk to the server, which is why the human
        // has to confirm the code before anything is issued.
        group.MapPost("/requests", async (
            PairingRequestInput input,
            PairingService pairing,
            CancellationToken ct) =>
        {
            try
            {
                return Results.Ok(await pairing.RequestAsync(input, ct));
            }
            catch (ArgumentException ex)
            {
                return Results.BadRequest(new { error = ex.Message });
            }
        });

        // Polled by the device until it is approved, denied or lapses.
        group.MapGet("/requests/{requestId:guid}", async (
            Guid requestId,
            PairingService pairing,
            CancellationToken ct) =>
        {
            var state = await pairing.GetStateAsync(requestId, ct);
            return state is null ? Results.NotFound() : Results.Ok(state);
        });

        // --- Local administration -------------------------------------------------
        //
        // Approving is the moment trust is granted, so it is restricted to callers on
        // the machine running the server. The Devices page calls PairingService
        // directly and never goes through these; they exist so pairing can also be
        // driven from a script or a terminal on the same box.

        var admin = group.MapGroup("/admin").AddEndpointFilter(LoopbackOnly);

        admin.MapGet("/requests", async (PairingService pairing, CancellationToken ct) =>
            Results.Ok((await pairing.GetOpenRequestsAsync(ct)).Select(r => new
            {
                requestId = r.RequestId,
                code = r.Code,
                deviceKind = r.DeviceKind,
                deviceName = r.DeviceName,
                platform = r.Platform,
                expiresAt = r.ExpiresAt,
            })));

        admin.MapPost("/requests/{requestId:guid}/approve", async (
                Guid requestId, PairingService pairing, CancellationToken ct) =>
            await pairing.ApproveAsync(requestId, ct)
                ? Results.Ok(new { approved = true })
                : Results.BadRequest(new { error = "No pending request with that id." }));

        admin.MapPost("/requests/{requestId:guid}/deny", async (
            Guid requestId, PairingService pairing, CancellationToken ct) =>
        {
            await pairing.DenyAsync(requestId, ct);
            return Results.Ok(new { denied = true });
        });

        admin.MapGet("/devices", async (
                PairingService pairing,
                Link.LinkRegistry registry,
                CancellationToken ct) =>
            Results.Ok((await pairing.GetDevicesAsync(ct)).Select(d => new
            {
                deviceId = d.DeviceId,
                deviceKind = d.DeviceKind,
                deviceName = d.DeviceName,
                platform = d.Platform,
                pairedAt = d.PairedAt,
                lastSeenAt = d.LastSeenAt,
                isConnected = registry.IsConnected(d.DeviceId),
            })));

        admin.MapDelete("/devices/{deviceId:guid}", async (
            Guid deviceId, PairingService pairing, CancellationToken ct) =>
        {
            await pairing.RevokeAsync(deviceId, ct);
            return Results.Ok(new { revoked = true });
        });

        return routes;
    }

    /// <summary>Rejects anything that did not come from this machine.</summary>
    private static async ValueTask<object?> LoopbackOnly(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var remote = context.HttpContext.Connection.RemoteIpAddress;

        if (remote is null || !System.Net.IPAddress.IsLoopback(remote))
        {
            return Results.Problem(
                "Pairing approval is only available from the machine running the server.",
                statusCode: StatusCodes.Status403Forbidden);
        }

        return await next(context);
    }
}
