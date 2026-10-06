-- 20261005_0014_profile_insert_guard.sql
--
-- SECURITY (critical): a new sign-up could make itself an approved admin.
--
-- Signup is open. The INSERT policy on profiles only requires `auth.uid() = id`, and the
-- existing guard (protect_admin_fields) is a BEFORE UPDATE trigger, so a freshly registered
-- account that had no profile row yet could POST /rest/v1/profiles with
-- {"id": <own uid>, "is_admin": true, "approved": true} and become an approved admin.
-- (create_signup_profile forces both to false, but nothing forced the direct insert the
-- Apple sign-in path also uses.)
--
-- A BEFORE INSERT trigger now clears the privileged columns whenever the row is inserted by a
-- signed-in caller who is not already an admin. Inserts without a JWT (service role, SQL
-- editor, cron) are left as given.

create or replace function public.protect_admin_fields_on_insert()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
    if auth.uid() is not null and not coalesce(public.is_admin_user(auth.uid()), false) then
        new.is_admin := false;
        new.approved := false;
        new.is_banned := false;
        new.ban_reason := null;
        new.banned_at := null;
        new.banned_by := null;
    end if;
    return new;
end;
$function$;

create or replace trigger protect_admin_fields_insert
    before insert on public.profiles
    for each row execute function public.protect_admin_fields_on_insert();
