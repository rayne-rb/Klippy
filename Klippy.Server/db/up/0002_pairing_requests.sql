-- A device asking to be let in. Short-lived: the human either approves it in the
-- server's Devices page before it expires, or it lapses and the device asks again.
create table if not exists pairing_requests
(
    request_id  uuid        not null primary key,
    code        text        not null,
    device_kind text        not null check (device_kind in ('companion', 'mobile')),
    device_name text        not null,
    platform    text        not null,
    status      text        not null default 'pending'
        check (status in ('pending', 'approved', 'denied', 'expired')),
    device_id   uuid references devices (device_id),
    created_at  timestamptz not null default now(),
    expires_at  timestamptz not null,
    decided_at  timestamptz
);

create index if not exists ix_pairing_requests_pending
    on pairing_requests (created_at desc) where status = 'pending';
