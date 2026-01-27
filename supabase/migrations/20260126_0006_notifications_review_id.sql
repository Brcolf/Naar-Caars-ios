do $$
begin
    if not exists (
        select 1
        from information_schema.columns
        where table_name = 'notifications'
          and column_name = 'review_id'
    ) then
        alter table notifications
        add column review_id uuid references reviews(id) on delete set null;
    end if;

    create index if not exists idx_notifications_review_id
        on notifications(review_id);

    comment on column notifications.review_id is 'Links notification to a review for review-related notifications';
end $$;
