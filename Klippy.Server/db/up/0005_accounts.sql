-- Who a device belongs to.
--
-- Until now every device paired to a server sat in one flat group: the link
-- broadcast to all of them and a targeted envelope could name any of them. An
-- account is the boundary that makes "my devices" mean something — a group is one
-- account's companions and phones, and another person gets their own account and
-- their own group.
create table if not exists users
(
    user_id       uuid        not null primary key,
    -- Compared case-insensitively at sign-in, so it is stored already folded.
    username      text        not null unique,
    -- PasswordHasher<T>'s own format: version byte, salt and subkey in one base64
    -- string. Never the password.
    password_hash text        not null,
    -- An admin sees every account's devices and clipboard. The first account made
    -- is one; see Setup.razor.
    is_admin      boolean     not null default false,
    created_at    timestamptz not null default now()
);

-- Nullable on purpose, and it stays that way: a device that has paired but whose
-- account is gone (revoked, or a database restored from before accounts existed)
-- has to keep working as a group of one rather than become unroutable. Nothing
-- reads a null owner as "belongs to everyone".
alter table devices
    add column if not exists owner_user_id uuid references users (user_id) on delete set null;

create index if not exists ix_devices_owner on devices (owner_user_id) where revoked_at is null;
