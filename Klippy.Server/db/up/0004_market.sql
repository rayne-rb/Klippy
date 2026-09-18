-- What a Klippy user has put up for sale. The item itself already left their
-- desktop through the sell portal by the time this row exists; this table is
-- the market's whole inventory until someone buys it.
create table if not exists market_listings
(
    listing_id       uuid        not null primary key,
    seller_device_id uuid        not null references devices (device_id),
    item_type        text        not null,
    price            integer     not null check (price > 0),
    listed_at        timestamptz not null default now(),
    sold_at          timestamptz,
    buyer_device_id  uuid references devices (device_id)
);

create index if not exists ix_market_listings_active on market_listings (listed_at desc) where sold_at is null;

-- A sale's proceeds, owed to the seller. Money the seller hasn't collected yet
-- because they were offline when their item sold — see KlippyEvents.MarketPayout.
-- Kept separate from market_listings so "paid out" survives independently of
-- whatever the listing itself later needs to say.
create table if not exists market_payouts
(
    payout_id        uuid        not null primary key,
    seller_device_id uuid        not null references devices (device_id),
    listing_id       uuid        not null references market_listings (listing_id),
    item_type        text        not null,
    price            integer     not null,
    created_at       timestamptz not null default now(),
    delivered_at     timestamptz
);

create index if not exists ix_market_payouts_pending on market_payouts (seller_device_id) where delivered_at is null;
