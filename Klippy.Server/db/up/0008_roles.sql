-- Accounts get a role rather than a flag.
--
-- 'admin' and 'user' are the two there are today. A named role leaves room for the
-- next one without another boolean beside the first, and reads as what it is at every
-- call site: a role, not a special case of "is this person special".
alter table users
    add column if not exists role text not null default 'user';

-- Whoever was an admin stays one. Done before the check is added, so an existing row
-- cannot fail it on the way through.
update users set role = 'admin' where is_admin;

alter table users
    drop constraint if exists users_role_check;

alter table users
    add constraint users_role_check check (role in ('admin', 'user'));

-- The flag's whole meaning now lives in the column above, and two places to ask the
-- same question is two places to disagree.
alter table users
    drop column if exists is_admin;
