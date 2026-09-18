using Klippy.Server.Data;
using RepoDb;

namespace Klippy.Server.Features.Market;

/// <summary>All database access for the market: listings and the payouts they generate.</summary>
public sealed class MarketRepository(IDbConnectionFactory connections)
{
    public async Task InsertListingAsync(MarketListingRow row, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.InsertAsync(row, cancellationToken: ct);
    }

    public async Task<MarketListingRow?> GetListingAsync(Guid listingId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.QueryAsync<MarketListingRow>(
            r => r.ListingId == listingId, cancellationToken: ct);
        return rows.FirstOrDefault();
    }

    /// <summary>Everything still for sale, newest first, with the seller's current device name.</summary>
    public async Task<IReadOnlyList<MarketListingView>> GetActiveListingsAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<MarketListingView>(
            """
            select ml.listing_id, ml.seller_device_id, d.device_name as seller_device_name,
                   ml.item_type, ml.price, ml.listed_at
            from market_listings ml
            join devices d on d.device_id = ml.seller_device_id
            where ml.sold_at is null
            order by ml.listed_at desc
            """,
            cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>
    /// Sells the listing to <paramref name="buyerDeviceId"/>, but only if nobody beat them
    /// to it. Returns false when the listing is already sold or does not exist, so the
    /// endpoint can tell the buyer their click was too late rather than double-selling it.
    /// </summary>
    public async Task<bool> TryMarkSoldAsync(Guid listingId, Guid buyerDeviceId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var affected = await connection.ExecuteNonQueryAsync(
            """
            update market_listings
            set sold_at = now(), buyer_device_id = @buyerDeviceId
            where listing_id = @listingId and sold_at is null
            """,
            new { listingId, buyerDeviceId },
            cancellationToken: ct);
        return affected > 0;
    }

    public async Task InsertPayoutAsync(MarketPayoutRow row, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.InsertAsync(row, cancellationToken: ct);
    }

    /// <summary>Payouts a device has not yet acknowledged applying, oldest first.</summary>
    public async Task<IReadOnlyList<MarketPayoutRow>> GetPendingPayoutsAsync(Guid sellerDeviceId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        var rows = await connection.ExecuteQueryAsync<MarketPayoutRow>(
            "select * from market_payouts where seller_device_id = @sellerDeviceId and delivered_at is null " +
            "order by created_at asc",
            new { sellerDeviceId },
            cancellationToken: ct);
        return rows.ToList();
    }

    /// <summary>Idempotent: acknowledging a payout twice is a no-op the second time.</summary>
    public async Task MarkPayoutDeliveredAsync(Guid payoutId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(ct);
        await connection.ExecuteNonQueryAsync(
            "update market_payouts set delivered_at = now() where payout_id = @payoutId and delivered_at is null",
            new { payoutId },
            cancellationToken: ct);
    }
}
