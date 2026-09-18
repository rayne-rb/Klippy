-- What has been copied, and who may see it.
--
-- One row per copy. An entry belongs to the account whose device made it, and its
-- visibility decides whether it stops there ('group') or is offered to everyone on
-- the server ('server'). The device that copied it chose which, before sending it.
create table if not exists clipboard_entries
(
    entry_id         uuid        not null primary key,
    owner_user_id    uuid        not null references users (user_id) on delete cascade,
    source_device_id uuid        not null references devices (device_id) on delete cascade,
    visibility       text        not null check (visibility in ('group', 'server')),
    content_type     text        not null check (content_type in ('text', 'image/png')),

    -- Exactly one of these is set, which the check below insists on rather than
    -- trusting every writer to remember.
    content_text     text,
    content_blob     bytea,

    byte_size        integer     not null check (byte_size >= 0),
    -- SHA-256 of the content. Copying is noticed by polling a clipboard that keeps
    -- answering with the same thing, so "is this the one I already have" is the most
    -- frequent question asked of this table.
    digest           text        not null,
    copied_at        timestamptz not null default now(),

    constraint clipboard_entries_content_present check (
        (content_type = 'text' and content_text is not null and content_blob is null)
        or (content_type <> 'text' and content_blob is not null and content_text is null)
    )
);

-- The board, per account, newest first.
create index if not exists ix_clipboard_owner on clipboard_entries (owner_user_id, copied_at desc);

-- The shared board, which every account can read whoever owns the entries.
create index if not exists ix_clipboard_shared on clipboard_entries (copied_at desc)
    where visibility = 'server';

-- The dedupe lookup: has this account already got this exact content?
create index if not exists ix_clipboard_digest on clipboard_entries (owner_user_id, digest);
