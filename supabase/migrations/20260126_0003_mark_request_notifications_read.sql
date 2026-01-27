create or replace function mark_request_notifications_read(
    p_request_type text,
    p_request_id uuid,
    p_notification_types text[] default null,
    p_include_reviews boolean default false
) returns integer as $$
declare
    v_types text[];
    v_count integer;
begin
    if p_notification_types is null then
        v_types := array[
            'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
            'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
        ];

        if p_include_reviews then
            v_types := v_types || array['review_request', 'review_reminder'];
        end if;
    else
        v_types := p_notification_types;
    end if;

    update notifications
    set read = true
    where user_id = auth.uid()
      and read = false
      and created_at <= now()
      and (
        (p_request_type = 'ride' and ride_id = p_request_id) or
        (p_request_type = 'favor' and favor_id = p_request_id)
      )
      and type = any(v_types);

    get diagnostics v_count = row_count;
    return v_count;
end;
$$ language plpgsql;

grant execute on function mark_request_notifications_read(text, uuid, text[], boolean) to authenticated;
