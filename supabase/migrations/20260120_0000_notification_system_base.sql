-- Base notification schema + helpers (runs before 20260121101500)

-- Profiles: town hall preference
alter table profiles
add column if not exists notify_town_hall boolean default true;

update profiles
set notify_town_hall = true
where notify_town_hall is null;

-- Notifications table (create if missing, then ensure columns exist)
create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references profiles(id) on delete cascade,
    type text not null,
    title text not null,
    body text,
    read boolean not null default false,
    pinned boolean not null default false,
    created_at timestamptz not null default now(),
    ride_id uuid references rides(id) on delete set null,
    favor_id uuid references favors(id) on delete set null,
    conversation_id uuid references conversations(id) on delete set null,
    review_id uuid references reviews(id) on delete set null,
    town_hall_post_id uuid references town_hall_posts(id) on delete set null,
    source_user_id uuid references profiles(id) on delete set null
);

alter table public.notifications
    add column if not exists ride_id uuid references rides(id) on delete set null,
    add column if not exists favor_id uuid references favors(id) on delete set null,
    add column if not exists conversation_id uuid references conversations(id) on delete set null,
    add column if not exists review_id uuid references reviews(id) on delete set null,
    add column if not exists town_hall_post_id uuid references town_hall_posts(id) on delete set null,
    add column if not exists source_user_id uuid references profiles(id) on delete set null,
    add column if not exists pinned boolean not null default false;

create index if not exists idx_notifications_town_hall_post_id on public.notifications(town_hall_post_id);
create index if not exists idx_notifications_source_user_id on public.notifications(source_user_id);
create index if not exists idx_notifications_type on public.notifications(type);
create index if not exists idx_notifications_user_read on public.notifications(user_id, read);

-- Notification queue table
create table if not exists public.notification_queue (
    id uuid primary key default gen_random_uuid(),
    notification_type text not null,
    recipient_user_id uuid references profiles(id) on delete cascade,
    payload jsonb not null,
    batch_key text,
    created_at timestamptz default now(),
    processed_at timestamptz,
    sent_at timestamptz
);

create index if not exists idx_notification_queue_pending
    on public.notification_queue(created_at)
    where processed_at is null;

create index if not exists idx_notification_queue_batch_key
    on public.notification_queue(batch_key, created_at)
    where processed_at is null;

-- Completion reminders table
create table if not exists public.completion_reminders (
    id uuid primary key default gen_random_uuid(),
    ride_id uuid references rides(id) on delete cascade,
    favor_id uuid references favors(id) on delete cascade,
    claimer_user_id uuid not null references profiles(id) on delete cascade,
    scheduled_for timestamptz not null,
    reminder_count int default 0,
    last_reminded_at timestamptz,
    completed boolean default false,
    created_at timestamptz default now(),
    constraint completion_reminder_request_check
        check ((ride_id is not null and favor_id is null) or (ride_id is null and favor_id is not null))
);

create index if not exists idx_completion_reminders_due
    on public.completion_reminders(scheduled_for)
    where completed = false;

create index if not exists idx_completion_reminders_ride on public.completion_reminders(ride_id);
create index if not exists idx_completion_reminders_favor on public.completion_reminders(favor_id);

-- Town Hall interactions table
create table if not exists public.town_hall_post_interactions (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references town_hall_posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    interaction_type text not null,
    created_at timestamptz default now(),
    unique (post_id, user_id, interaction_type)
);

create index if not exists idx_town_hall_interactions_post on public.town_hall_post_interactions(post_id);
create index if not exists idx_town_hall_interactions_user on public.town_hall_post_interactions(user_id);

-- Helper: user preference check
create or replace function should_notify_user(
    p_user_id uuid,
    p_notification_type text
) returns boolean as $$
declare
    v_profile record;
begin
    select * into v_profile from profiles where id = p_user_id;

    if not found then
        return false;
    end if;

    case p_notification_type
        when 'new_ride', 'new_favor' then
            return true;
        when 'announcement', 'admin_announcement', 'broadcast' then
            return true;
        when 'user_approved', 'user_rejected' then
            return true;
        when 'pending_approval' then
            return v_profile.is_admin;
        when 'message', 'added_to_conversation' then
            return v_profile.notify_messages;
        when 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed' then
            return v_profile.notify_ride_updates;
        when 'qa_activity', 'qa_question', 'qa_answer' then
            return v_profile.notify_qa_activity;
        when 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder' then
            return v_profile.notify_review_reminders;
        when 'town_hall_post', 'town_hall_comment', 'town_hall_reaction' then
            return v_profile.notify_town_hall;
        else
            return true;
    end case;
end;
$$ language plpgsql security definer;

-- Helper: create notification
create or replace function create_notification(
    p_user_id uuid,
    p_type text,
    p_title text,
    p_body text default null,
    p_ride_id uuid default null,
    p_favor_id uuid default null,
    p_conversation_id uuid default null,
    p_review_id uuid default null,
    p_town_hall_post_id uuid default null,
    p_source_user_id uuid default null,
    p_pinned boolean default false
) returns uuid as $$
declare
    v_notification_id uuid;
begin
    if not should_notify_user(p_user_id, p_type) then
        return null;
    end if;

    if p_source_user_id is not null and p_source_user_id = p_user_id then
        return null;
    end if;

    insert into notifications (
        user_id, type, title, body, read, pinned,
        ride_id, favor_id, conversation_id, review_id,
        town_hall_post_id, source_user_id
    ) values (
        p_user_id, p_type, p_title, p_body, false, p_pinned,
        p_ride_id, p_favor_id, p_conversation_id, p_review_id,
        p_town_hall_post_id, p_source_user_id
    )
    returning id into v_notification_id;

    return v_notification_id;
end;
$$ language plpgsql security definer;

grant execute on function create_notification to authenticated;
grant execute on function should_notify_user to authenticated;
