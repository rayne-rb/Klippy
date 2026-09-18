using RepoDb.Attributes;

namespace Klippy.Server.Features.Market;

/// <summary>Row in <c>market_listings</c>.</summary>
[Map("market_listings")]
public sealed class MarketListingRow
{
    [Primary]
    [Map("listing_id")]
    public Guid ListingId { get; set; }

    [Map("seller_device_id")]
    public Guid SellerDeviceId { get; set; }

    [Map("item_type")]
    public string ItemType { get; set; } = string.Empty;

    [Map("price")]
    public int Price { get; set; }

    [Map("listed_at")]
    public DateTimeOffset ListedAt { get; set; }

    [Map("sold_at")]
    public DateTimeOffset? SoldAt { get; set; }

    [Map("buyer_device_id")]
    public Guid? BuyerDeviceId { get; set; }
}
