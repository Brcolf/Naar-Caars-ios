-- 20261005_0004_function_caller_guards.sql
--
-- STATUS: APPLIED TO PRODUCTION on 2026-10-05 from the Supabase SQL editor (recorded as
-- version 20261005000400 by the insert at the bottom of this file). The MCP
-- apply_migration tool declines CREATE OR REPLACE in Code-tab sessions, which is why it
-- was run by hand.
--
-- What it does:
--   * send_approval_notification(): only admins may call it (the iOS admin flow does).
--   * set_typing_status() / clear_typing_status(): a caller may only act as themselves.
-- anon EXECUTE on all three was already revoked in 20261005_0001.

-- ---------------------------------------------------------------------------
-- 2. send_approval_notification: admin-only. The iOS admin flow calls this RPC.
-- ---------------------------------------------------------------------------
create or replace function public.send_approval_notification(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    v_notification_id uuid;
begin
    if auth.uid() is null or not public.is_admin_user(auth.uid()) then
        raise exception 'Only admins can send approval notifications'
            using errcode = '42501';
    end if;

    insert into notifications (user_id, type, title, body, read, pinned, created_at)
    values (
        p_user_id,
        'user_approved',
        'Welcome to Naar''s Cars!',
        'Your account has been approved. You can now access all features of the app.',
        false,
        true,
        now()
    )
    returning id into v_notification_id;

    return v_notification_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Typing-status RPCs: a caller may only set or clear their own indicator.
-- ---------------------------------------------------------------------------
create or replace function public.set_typing_status(p_conversation_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    v_is_participant boolean;
begin
    if auth.uid() is null or p_user_id <> auth.uid() then
        return false;
    end if;

    select exists (
        select 1 from conversation_participants
        where conversation_id = p_conversation_id
          and user_id = p_user_id
          and left_at is null
    ) into v_is_participant;

    if not v_is_participant then
        return false;
    end if;

    insert into typing_indicators (conversation_id, user_id, started_at)
    values (p_conversation_id, p_user_id, now())
    on conflict (conversation_id, user_id)
    do update set started_at = now();

    return true;
end;
$$;

create or replace function public.clear_typing_status(p_conversation_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
    if auth.uid() is null or p_user_id <> auth.uid() then
        return false;
    end if;

    delete from typing_indicators
    where conversation_id = p_conversation_id
      and user_id = p_user_id;

    return true;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261005000400', '20261005_0004_function_caller_guards', array['-- Applied manually from the SQL editor; see repo file.'])
on conflict do nothing;
