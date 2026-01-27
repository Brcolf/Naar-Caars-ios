alter table public.notification_queue enable row level security;

do $$
begin
    if not exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'notification_queue'
          and policyname = 'notification_queue_insert_authenticated'
    ) then
        create policy "notification_queue_insert_authenticated"
            on public.notification_queue
            for insert
            with check (true);
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'notification_queue'
          and policyname = 'notification_queue_select_service'
    ) then
        create policy "notification_queue_select_service"
            on public.notification_queue
            for select
            using (true);
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'notification_queue'
          and policyname = 'notification_queue_update_service'
    ) then
        create policy "notification_queue_update_service"
            on public.notification_queue
            for update
            using (true)
            with check (true);
    end if;
end $$;

create or replace function process_immediate_notification()
returns trigger as $$
begin
    if new.batch_key is null then
        new.processed_at := now();
    end if;

    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_notification_queue_insert on notification_queue;
create trigger on_notification_queue_insert
before insert on notification_queue
for each row
execute function process_immediate_notification();

create or replace function send_push_notification_direct(
    p_user_id uuid,
    p_notification_type text,
    p_title text,
    p_body text,
    p_data jsonb default '{}'::jsonb
) returns void as $$
declare
    v_payload jsonb;
begin
    if not should_notify_user(p_user_id, p_notification_type) then
        return;
    end if;

    v_payload := jsonb_build_object(
        'recipient_user_id', p_user_id::text,
        'notification_type', p_notification_type,
        'title', p_title,
        'body', p_body,
        'data', p_data
    );

    insert into notification_queue (
        notification_type,
        recipient_user_id,
        payload,
        batch_key,
        processed_at
    ) values (
        p_notification_type,
        p_user_id,
        jsonb_build_object(
            'title', p_title,
            'body', p_body,
            'type', p_notification_type,
            'data', p_data
        ),
        null,
        now()
    );

    perform pg_notify(
        'push_notification',
        v_payload::text
    );
end;
$$ language plpgsql security definer;

grant execute on function send_push_notification_direct to authenticated;

do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and tablename = 'notification_queue'
    ) then
        alter publication supabase_realtime add table public.notification_queue;
    end if;
exception
    when undefined_object then
        null;
end $$;

alter table public.notification_queue replica identity full;
