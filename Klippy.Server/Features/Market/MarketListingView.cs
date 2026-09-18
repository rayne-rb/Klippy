using RepoDb.Attributes;

namespace Klippy.Server.Features.Market;

/// <summary>
/// An active listing joined with its seller's device name, for the Companion's
/// browse dialog and the server's own /market page. Not a table of its own.
/// </summary>
public sealed class MarketListingView
{
    [Map("listing_id")]
    public Guid ListingId { get; set; }

    [Map("seller_device_id")]
    public Guid SellerDeviceId { get; set; }

    [Map("seller_device_name")]
    public string SellerDeviceName { get; set; } = string.Empty;

    [Map("item_type")]
    public string ItemType { get; set; } = string.Empty;

    [Map("price")]
    public int Price { get; set; }

    [Map("listed_at")]
    public DateTimeOffset ListedAt { get; set; }
}
