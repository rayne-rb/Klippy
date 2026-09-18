-- Let a device pair as a 'visitor'.
--
-- A friend's Companion pairs here so its pet can visit this monitor (see the visit
-- slice in Klippy.Companion). DeviceKind gained the kind, but these two checks were
-- written when there were only two, so every visitor pairing was refused by the
-- database before it ever reached a human to approve.
--
-- A new file rather than an edit to 0001 and 0002: grate checksums what it has run.
alter table devices
    drop constraint if exists devices_device_kind_check;

alter table devices
    add constraint devices_device_kind_check
        check (device_kind in ('companion', 'mobile', 'visitor'));

alter table pairing_requests
    drop constraint if exists pairing_requests_device_kind_check;

alter table pairing_requests
    add constraint pairing_requests_device_kind_check
        check (device_kind in ('companion', 'mobile', 'visitor'));
