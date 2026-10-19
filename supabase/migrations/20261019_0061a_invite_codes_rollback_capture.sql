-- 20261019_0061a_invite_codes_rollback_capture.sql
--
-- ROLLBACK CAPTURE, never applied. Do not apply, push to the database or paste this file except to undo
-- 20261019_0061_drop_invite_codes.sql after public.invite_codes has been dropped; the guard below refuses to run
-- while the table exists. It is C0 of the Phase 5 SQL plan (Docs/superpowers/plans/2026-10-19-multi-community-phase5-sql.md,
-- File C), read through the Supabase MCP on 2026-10-19 with read-only selects: pg_get_functiondef of the four
-- functions, information_schema.columns, pg_constraint, pg_indexes, pg_trigger, pg_policies,
-- information_schema.role_table_grants, pg_class.relacl and pg_proc.proacl. Captured just before the 5b dry runs;
-- nothing in Phase 5 had touched the table.
--
-- DDL only. The 62 rows (54 never used) are not in the repository: they hold user ids and the repository is
-- public. They were exported the same day, off the repository, to
-- /Users/bcolf/Documents/naars-cars-ios-roadmap-research/2026-10-19-invite_codes-backup.csv (a header row and 62
-- rows ordered by created_at, id; NULL as an empty unquoted field; no field needs quoting; md5 of the file
-- 50dc9c4c7d7751050f9dcd98dae873a8, equal to the server-side md5 of the same text).
--
-- Live md5(prosrc) at capture, equal to the plan's P1 and to the bodies below: validate_invite_code(text)
-- 0e330ecc03e2b00bedd3d0cc4785070f, mark_invite_code_used(text, text, text, text) d129033694581c28234019c05cdcf78a,
-- guard_invite_code_client_update() 530255a0f0968765af6f922074cadbc9, handle_invite_code_used()
-- 255138a67eb745d065cbe9950dcf6bc8. The function definitions are pg_get_functiondef output, unchanged. In the
-- constraints and policies, table names are schema-qualified (pg_constraint / pg_policies print them without
-- public. because public is on the search path); the stored expressions are the same.
--
-- Restore (SQL editor, owner, one transaction), only after 20261019_0061 was applied: this file; then load the CSV
-- into public.invite_codes (Table editor import, or psql: \copy public.invite_codes from '<csv>' with (format csv,
-- header true)); a row whose created_by or used_by profile was deleted after the export fails its foreign key and
-- aborts the load, so drop such rows from the CSV first (or blank their used_by); then delete_user_account from
-- 20261017_0004_communities_account_lifecycle.sql:214-499 (File C removed its invite_codes statement).


-- the guard: never while the table exists
do $guard$
begin
  if to_regclass('public.invite_codes') is not null then
    raise exception 'ROLLBACK CAPTURE: public.invite_codes exists; this file only restores it after 20261019_0061';
  end if;
end
$guard$;

-- the table
create table public.invite_codes (
  id uuid not null default gen_random_uuid(),
  code text not null,
  created_by uuid not null,
  used_by uuid,
  used_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  invite_statement text,
  is_bulk boolean default false,
  expires_at timestamp with time zone,
  bulk_code_id uuid
);

alter table public.invite_codes
  add constraint invite_codes_pkey primary key (id),
  add constraint invite_codes_code_key unique (code),
  add constraint invite_codes_created_by_fkey foreign key (created_by) references public.profiles(id) on delete cascade,
  add constraint invite_codes_used_by_fkey foreign key (used_by) references public.profiles(id) on delete set null,
  add constraint invite_codes_bulk_code_id_fkey foreign key (bulk_code_id) references public.invite_codes(id) on delete set null;

CREATE INDEX idx_invite_codes_created_by ON public.invite_codes USING btree (created_by);
CREATE INDEX idx_invite_codes_used_by ON public.invite_codes USING btree (used_by);
CREATE INDEX idx_invite_codes_code ON public.invite_codes USING btree (code) WHERE (used_at IS NULL);
CREATE INDEX idx_invite_codes_bulk_code_id ON public.invite_codes USING btree (bulk_code_id) WHERE (bulk_code_id IS NOT NULL);
CREATE INDEX idx_invite_codes_expires_at ON public.invite_codes USING btree (expires_at) WHERE (expires_at IS NOT NULL);
CREATE INDEX idx_invite_codes_active ON public.invite_codes USING btree (created_by, created_at DESC) WHERE (used_by IS NULL);

alter table public.invite_codes enable row level security;

-- table grants as captured (relacl: postgres, anon, authenticated, service_role = arwdDxtm)
grant all on table public.invite_codes to anon, authenticated, service_role;


-- the four functions (pg_get_functiondef), each with its captured EXECUTE grants (proacl)
-- validate_invite_code(text)   md5(prosrc) 0e330ecc03e2b00bedd3d0cc4785070f
CREATE OR REPLACE FUNCTION public.validate_invite_code(p_code text)
 RETURNS TABLE(is_valid boolean, code_id uuid, created_by uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        (ic.used_at IS NULL) as is_valid,
        ic.id as code_id,
        ic.created_by
    FROM public.invite_codes ic
    WHERE ic.code = p_code
    LIMIT 1;
END;
$function$;
grant execute on function public.validate_invite_code(text) to public, anon, authenticated, service_role;

-- mark_invite_code_used(text, text, text, text)   md5(prosrc) d129033694581c28234019c05cdcf78a
CREATE OR REPLACE FUNCTION public.mark_invite_code_used(p_invite_code_id text, p_user_id text, p_is_bulk text DEFAULT 'false'::text, p_bulk_code_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_invite_code_id UUID;
    v_user_id UUID;
    v_is_bulk BOOLEAN;
    v_bulk_code_id UUID;
    v_code_exists BOOLEAN;
    v_code_used BOOLEAN;
    v_tracking_code TEXT;
    v_new_record_id UUID;
BEGIN
    -- Parse parameters (accepting TEXT for flexibility from client)
    BEGIN
        v_invite_code_id := p_invite_code_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code ID format');
    END;
    
    BEGIN
        v_user_id := p_user_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid user ID format');
    END;
    
    v_is_bulk := LOWER(p_is_bulk) = 'true';
    
    IF p_bulk_code_id IS NOT NULL AND p_bulk_code_id != '' THEN
        BEGIN
            v_bulk_code_id := p_bulk_code_id::UUID;
        EXCEPTION WHEN OTHERS THEN
            RETURN jsonb_build_object('success', false, 'error', 'Invalid bulk code ID format');
        END;
    END IF;
    
    -- Validate input
    IF v_invite_code_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invite code ID is required'
        );
    END IF;
    
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User ID is required'
        );
    END IF;
    
    -- Check if invite code exists
    SELECT EXISTS (
        SELECT 1 FROM invite_codes WHERE id = v_invite_code_id
    ) INTO v_code_exists;
    
    IF NOT v_code_exists THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invite code not found'
        );
    END IF;
    
    IF v_is_bulk THEN
        -- For bulk codes: Create a tracking record
        -- Generate tracking code
        v_tracking_code := (
            SELECT code || '-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8))
            FROM invite_codes 
            WHERE id = v_invite_code_id
        );
        v_new_record_id := gen_random_uuid();
        
        INSERT INTO invite_codes (
            id,
            code,
            created_by,
            used_by,
            used_at,
            created_at,
            is_bulk,
            bulk_code_id
        )
        SELECT 
            v_new_record_id,
            v_tracking_code,
            created_by,  -- Same creator as bulk code
            v_user_id,
            NOW(),
            NOW(),
            false,  -- Tracking record is not bulk
            v_invite_code_id  -- Reference to the bulk code
        FROM invite_codes
        WHERE id = v_invite_code_id;
        
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Bulk code tracking record created',
            'tracking_id', v_new_record_id
        );
    ELSE
        -- For regular codes: Check if already used
        SELECT used_by IS NOT NULL INTO v_code_used
        FROM invite_codes 
        WHERE id = v_invite_code_id;
        
        IF v_code_used THEN
            -- Already used - this can happen on re-signup after rejection
            -- Just return success, the code was already marked
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Invite code was already used'
            );
        END IF;
        
        -- Mark as used
        UPDATE invite_codes
        SET 
            used_by = v_user_id,
            used_at = NOW()
        WHERE id = v_invite_code_id
        AND used_by IS NULL;
        
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Invite code marked as used'
        );
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$function$;
revoke all on function public.mark_invite_code_used(text, text, text, text) from public, anon, authenticated;
grant execute on function public.mark_invite_code_used(text, text, text, text) to service_role;

-- guard_invite_code_client_update()   md5(prosrc) 530255a0f0968765af6f922074cadbc9
CREATE OR REPLACE FUNCTION public.guard_invite_code_client_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if (to_jsonb(new) - array['used_by', 'used_at']) is distinct from (to_jsonb(old) - array['used_by', 'used_at'])
     or old.used_by is not null
     or new.used_by is distinct from (select auth.uid())
     or new.used_at is null then
    raise exception 'An invite code can only be marked as used by the person signing up with it' using errcode = '42501';
  end if;
  return new;
end
$function$;
revoke all on function public.guard_invite_code_client_update() from public, anon, authenticated;
grant execute on function public.guard_invite_code_client_update() to service_role;

-- handle_invite_code_used()   md5(prosrc) 255138a67eb745d065cbe9950dcf6bc8
CREATE OR REPLACE FUNCTION public.handle_invite_code_used()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    IF NEW.used_at IS NOT NULL AND OLD.used_at IS NULL THEN
        NEW.used_by = auth.uid();
    END IF;
    RETURN NEW;
END;
$function$;
grant execute on function public.handle_invite_code_used() to public, anon, authenticated, service_role;


-- the triggers (both BEFORE UPDATE; they fire in name order, as before)
CREATE TRIGGER guard_invite_code_client_update BEFORE UPDATE ON public.invite_codes FOR EACH ROW EXECUTE FUNCTION public.guard_invite_code_client_update();
CREATE TRIGGER on_invite_code_used BEFORE UPDATE ON public.invite_codes FOR EACH ROW EXECUTE FUNCTION public.handle_invite_code_used();


-- the policies (all PERMISSIVE, role public), as pg_policies printed them
create policy "Approved users can create invite codes" on public.invite_codes
  as permissive for insert to public
  with check ((( SELECT profiles.approved
   FROM public.profiles
  WHERE (profiles.id = ( SELECT auth.uid() AS uid))) = true));

create policy "Users can view own created codes" on public.invite_codes
  as permissive for select to public
  using ((created_by = ( SELECT auth.uid() AS uid)));

create policy invite_codes_insert_allowed on public.invite_codes
  as permissive for insert to public
  with check ((((used_by = ( SELECT auth.uid() AS uid)) AND (bulk_code_id IS NOT NULL) AND (is_bulk = false)) OR ((created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = ( SELECT auth.uid() AS uid)) AND (profiles.approved = true)))))));

create policy invite_codes_update_mark_as_used on public.invite_codes
  as permissive for update to public
  using (((used_by IS NULL) AND (( SELECT auth.uid() AS uid) IS NOT NULL)))
  with check (((used_by = ( SELECT auth.uid() AS uid)) AND (used_at IS NOT NULL)));
