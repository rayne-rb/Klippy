using RepoDb.Attributes;

namespace Klippy.Server.Features.Market;

/// <summary>Row in <c>market_payouts</c>: proceeds a seller is owed, delivered over the link.</summary>
[Map("market_payouts")]
public sealed class MarketPayoutRow
{
    [Primary]
    [Map("payout_id")]
    public Guid PayoutId { get; set; }

    [Map("seller_device_id")]
    public Guid SellerDeviceId { get; set; }

    [Map("listing_id")]
    public Guid ListingId { get; set; }

    [Map("item_type")]
    public string ItemType { get; set; } = string.Empty;

    [Map("price")]
    public int Price { get; set; }

    [Map("created_at")]
    public DateTimeOffset CreatedAt { get; set; }

    [Map("delivered_at")]
    public DateTimeOffset? DeliveredAt { get; set; }
}
