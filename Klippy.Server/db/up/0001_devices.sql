-- Devices that have completed pairing and may open a link socket.
create table if not exists devices
(
    device_id    uuid        not null primary key,
    device_kind  text        not null check (device_kind in ('companion', 'mobile')),
    device_name  text        not null,
    platform     text        not null,
    -- Only ever the SHA-256 of the bearer token; the plaintext is shown to the
    -- device once, at approval, and never stored.
    token_hash   text        not null,
    paired_at    timestamptz not null default now(),
    last_seen_at timestamptz,
    revoked_at   timestamptz
);

create index if not exists ix_devices_token_hash on devices (token_hash) where revoked_at is null;
create index if not exists ix_devices_kind on devices (device_kind) where revoked_at is null;
