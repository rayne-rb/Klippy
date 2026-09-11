-- Every envelope that crossed the link. Gives the server something to react to
-- after the fact, and lets a device that was offline catch up on what it missed.
create table if not exists link_events
(
    event_id      uuid        not null primary key,
    event_type    text        not null,
    source_device uuid,
    target_device uuid,
    payload       jsonb,
    occurred_at   timestamptz not null
);

create index if not exists ix_link_events_occurred on link_events (occurred_at desc);
create index if not exists ix_link_events_type on link_events (event_type, occurred_at desc);
