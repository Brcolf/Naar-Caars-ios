alter table public.messages replica identity full;
alter table public.conversations replica identity full;
alter table public.notifications replica identity full;

do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and tablename = 'messages'
    ) then
        alter publication supabase_realtime add table public.messages;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and tablename = 'conversations'
    ) then
        alter publication supabase_realtime add table public.conversations;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and tablename = 'notifications'
    ) then
        alter publication supabase_realtime add table public.notifications;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and tablename = 'notification_queue'
    ) then
        alter publication supabase_realtime add table public.notification_queue;
    end if;
exception
    when undefined_object then
        create publication supabase_realtime for table
            public.messages,
            public.conversations,
            public.notifications,
            public.notification_queue;
end $$;

drop policy if exists "messages_select_creator" on public.messages;
drop policy if exists "messages_select_participant" on public.messages;

create policy "messages_select_for_participants" on public.messages
    for select
    using (
        exists (
            select 1 from public.conversations c
            where c.id = messages.conversation_id
              and c.created_by = auth.uid()
        )
        or
        exists (
            select 1 from public.conversation_participants cp
            where cp.conversation_id = messages.conversation_id
              and cp.user_id = auth.uid()
        )
    );

drop policy if exists "messages_insert_creator" on public.messages;
drop policy if exists "messages_insert_participant" on public.messages;

create policy "messages_insert_for_participants" on public.messages
    for insert
    with check (
        auth.uid() = from_id
        and (
            exists (
                select 1 from public.conversations c
                where c.id = conversation_id
                  and c.created_by = auth.uid()
            )
            or
            exists (
                select 1 from public.conversation_participants cp
                where cp.conversation_id = conversation_id
                  and cp.user_id = auth.uid()
            )
        )
    );

drop policy if exists "messages_update_own" on public.messages;
drop policy if exists "messages_update_read_by" on public.messages;

create policy "messages_update_for_participants" on public.messages
    for update
    using (
        exists (
            select 1 from public.conversations c
            where c.id = messages.conversation_id
              and c.created_by = auth.uid()
        )
        or
        exists (
            select 1 from public.conversation_participants cp
            where cp.conversation_id = messages.conversation_id
              and cp.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.conversations c
            where c.id = conversation_id
              and c.created_by = auth.uid()
        )
        or
        exists (
            select 1 from public.conversation_participants cp
            where cp.conversation_id = conversation_id
              and cp.user_id = auth.uid()
        )
    );

drop policy if exists "notifications_select_own" on public.notifications;
drop policy if exists "Users can view own notifications" on public.notifications;

create policy "notifications_select_own" on public.notifications
    for select
    using (user_id = auth.uid());

drop policy if exists "notifications_insert_system" on public.notifications;

create policy "notifications_insert_authenticated" on public.notifications
    for insert
    with check (true);

drop policy if exists "notifications_update_own" on public.notifications;

create policy "notifications_update_own" on public.notifications
    for update
    using (user_id = auth.uid())
    with check (user_id = auth.uid());
