create table if not exists public.push_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references profiles(id) on delete cascade,
    device_id text not null,
    token text not null,
    platform text not null default 'ios',
    environment text not null default 'production',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_used_at timestamptz
);

create unique index if not exists push_tokens_user_device_idx
    on public.push_tokens (user_id, device_id);

alter table public.push_tokens enable row level security;

do $$
begin
    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'push_tokens'
          and policyname = 'push_tokens_select_own'
    ) then
        create policy "push_tokens_select_own"
            on public.push_tokens
            for select
            using (auth.uid() = user_id);
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'push_tokens'
          and policyname = 'push_tokens_insert_own'
    ) then
        create policy "push_tokens_insert_own"
            on public.push_tokens
            for insert
            with check (auth.uid() = user_id);
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'push_tokens'
          and policyname = 'push_tokens_update_own'
    ) then
        create policy "push_tokens_update_own"
            on public.push_tokens
            for update
            using (auth.uid() = user_id)
            with check (auth.uid() = user_id);
    end if;
end $$;
