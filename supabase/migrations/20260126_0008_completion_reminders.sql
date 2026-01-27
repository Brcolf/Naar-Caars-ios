create or replace function process_batched_notifications()
returns integer as $$
declare
    v_batch record;
    v_count integer := 0;
    v_notifications_in_batch integer;
begin
    for v_batch in
        select batch_key, recipient_user_id, count(*) as notification_count
        from notification_queue
        where batch_key is not null
          and processed_at is null
          and created_at <= now() - interval '3 minutes'
        group by batch_key, recipient_user_id
    loop
        v_notifications_in_batch := v_batch.notification_count;

        if v_notifications_in_batch = 1 then
            update notification_queue nq
            set processed_at = now()
            where nq.batch_key = v_batch.batch_key
              and nq.recipient_user_id = v_batch.recipient_user_id
              and nq.processed_at is null;
        else
            update notification_queue
            set
                processed_at = now(),
                payload = jsonb_set(
                    payload,
                    '{body}',
                    to_jsonb(v_notifications_in_batch || ' new posts in Town Hall')
                ),
                sent_at = case
                    when id = (
                        select id from notification_queue nq2
                        where nq2.batch_key = v_batch.batch_key
                          and nq2.recipient_user_id = v_batch.recipient_user_id
                        order by created_at asc
                        limit 1
                    ) then null
                    else now()
                end
            where batch_key = v_batch.batch_key
              and recipient_user_id = v_batch.recipient_user_id
              and processed_at is null;
        end if;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$ language plpgsql security definer;

comment on function process_batched_notifications is
    'Processes batched notifications (like Town Hall) that have been waiting for 3+ minutes';
