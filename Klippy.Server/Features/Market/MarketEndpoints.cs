using Klippy.Server.Common;
using Klippy.Server.Features.Link;
using Klippy.Server.Features.Pairing;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.Market;

public static class MarketEndpoints
{
    public static IEndpointRouteBuilder MapMarketEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/market").WithTags("Market");

        // Anonymous: browsing what is for sale carries no more risk than the rest of
        // this LAN-only server's read views (see Devices, Pet).
        group.MapGet("/listings", async (MarketRepository market, CancellationToken ct) =>
            Results.Ok(await market.GetActiveListingsAsync(ct)));

        // A Companion posts here once the item has already left its desktop through
        // the sell portal — see ConsumablePortal/SellPortal on that side. Failing this
        // call is the Companion's cue to hand the item back rather than lose it.
        group.MapPost("/listings", async (
            HttpContext context,
            MarketListingCreateRequest input,
            PairingService pairing,
            MarketRepository market,
            MarketNotifier notifier,
            CancellationToken ct) =>
        {
            var seller = await pairing.AuthenticateAsync(BearerToken.Read(context), ct);
            if (seller is null)
            {
                return Results.Unauthorized();
            }

            if (string.IsNullOrWhiteSpace(input.ItemType))
            {
                return Results.BadRequest(new { error = "ItemType is required." });
            }

            if (input.Price <= 0)
            {
                return Results.BadRequest(new { error = "Price must be positive." });
            }

            var row = new MarketListingRow
            {
                ListingId = Guid.NewGuid(),
                SellerDeviceId = seller.DeviceId,
                ItemType = input.ItemType,
                Price = input.Price,
                ListedAt = DateTimeOffset.UtcNow,
            };

            await market.InsertListingAsync(row, ct);
            notifier.NotifyChanged();
            return Results.Ok(new { listingId = row.ListingId });
        });

        group.MapPost("/listings/{listingId:guid}/buy", async (
            HttpContext context,
            Guid listingId,
            PairingService pairing,
            MarketRepository market,
            MarketNotifier notifier,
            LinkRegistry registry,
            IEventPublisher publisher,
            CancellationToken ct) =>
        {
            var buyer = await pairing.AuthenticateAsync(BearerToken.Read(context), ct);
            if (buyer is null)
            {
                return Results.Unauthorized();
            }

            var listing = await market.GetListingAsync(listingId, ct);
            if (listing is null || listing.SoldAt is not null)
            {
                return Results.Conflict(new { error = "That listing is no longer available." });
            }

            if (listing.SellerDeviceId == buyer.DeviceId)
            {
                return Results.BadRequest(new { error = "You cannot buy your own listing." });
            }

            // Guards the same race a double-click or two simultaneous buyers would
            // otherwise hit: only the update that actually flips sold_at wins.
            if (!await market.TryMarkSoldAsync(listingId, buyer.DeviceId, ct))
            {
                return Results.Conflict(new { error = "That listing is no longer available." });
            }

            var payout = new MarketPayoutRow
            {
                PayoutId = Guid.NewGuid(),
                SellerDeviceId = listing.SellerDeviceId,
                ListingId = listing.ListingId,
                ItemType = listing.ItemType,
                Price = listing.Price,
                CreatedAt = DateTimeOffset.UtcNow,
            };
            await market.InsertPayoutAsync(payout, ct);

            // A seller who is online right now hears about it immediately; one who
            // is not gets the same event from MarketEventHandler on their next
            // connect (see its handling of KlippyEvents.DeviceConnected).
            if (registry.IsConnected(listing.SellerDeviceId))
            {
                await publisher.PublishAsync(LinkEnvelope.Create(
                    KlippyEvents.MarketPayout,
                    new MarketPayoutPayload
                    {
                        PayoutId = payout.PayoutId.ToString(),
                        ItemType = payout.ItemType,
                        Price = payout.Price,
                    },
                    target: listing.SellerDeviceId.ToString()), ct);
            }

            notifier.NotifyChanged();
            return Results.Ok(new { itemType = listing.ItemType, price = listing.Price });
        });

        return routes;
    }
}

/// <summary>Body of a "list this item" request.</summary>
public sealed record MarketListingCreateRequest
{
    public required string ItemType { get; init; }
    public required int Price { get; init; }
}
