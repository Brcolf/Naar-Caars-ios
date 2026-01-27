create or replace function notify_town_hall_vote()
returns trigger as $$
declare
    v_voter_name text;
    v_post record;
    v_vote_type text;
begin
    select name into v_voter_name from profiles where id = new.user_id;
    v_voter_name := coalesce(v_voter_name, 'Someone');

    select * into v_post from town_hall_posts where id = new.post_id;

    v_vote_type := case when new.vote_type = 'upvote' then 'upvote' else 'downvote' end;

    insert into town_hall_post_interactions (post_id, user_id, interaction_type)
    values (new.post_id, new.user_id, v_vote_type)
    on conflict (post_id, user_id, interaction_type) do nothing;

    if new.vote_type = 'upvote' then
        if v_post.user_id != new.user_id then
            perform create_notification(
                v_post.user_id,
                'town_hall_reaction',
                'Post Upvoted',
                v_voter_name || ' upvoted your post',
                null,
                null,
                null,
                null,
                new.post_id,
                new.user_id
            );
        end if;
    end if;

    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_town_hall_vote_notify on town_hall_votes;
create trigger on_town_hall_vote_notify
after insert on town_hall_votes
for each row
execute function notify_town_hall_vote();
