using Klippy.Server.Features.Link;
using Klippy.Server.Features.Pairing;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.PetState;

public static class PetStateEndpoints
{
    public static IEndpointRouteBuilder MapPetStateEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/pet").WithTags("Pet");

        // Last known vitals, without needing a socket. Handy for a phone widget or a
        // quick check that the whole chain is alive.
        group.MapGet("/state", (PetStateStore store) =>
        {
            var (stats, updatedAt) = store.Current;
            return stats is null
                ? Results.Ok(new { known = false })
                : Results.Ok(new { known = true, updatedAt, stats });
        });

        // Ask the Companion to re-report. Useful when the server's picture looks stale.
        group.MapPost("/refresh", async (IEventPublisher publisher, CancellationToken ct) =>
        {
            await publisher.PublishAsync(LinkEnvelope.Create(KlippyEvents.PetStatsRequest), ct);
            return Results.Accepted();
        });

        return routes;
    }
}
