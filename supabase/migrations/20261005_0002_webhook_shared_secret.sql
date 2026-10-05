-- 20261005_0002_webhook_shared_secret.sql
--
-- Root cause (2026-10-05): the database webhooks that call the send-notification and
-- send-message-push edge functions embed a legacy service_role JWT in the trigger
-- definition, while the deployed functions compare the Authorization header against
-- SUPABASE_SERVICE_ROLE_KEY from their environment. Since the project moved to the
-- new API-key format those values no longer match, every webhook call has been
-- rejected with 401, and ~330 queued notifications were never delivered.
--
-- Fix: authenticate webhooks with a dedicated shared secret stored in Vault and sent
-- as an x-webhook-secret header. The edge functions verify it through the
-- service_role-only RPC verify_webhook_secret(). No API key appears in any trigger.


-- 1. Shared secret (random, never leaves the database except over TLS to the function).
select vault.create_secret(
    encode(extensions.gen_random_bytes(32), 'hex'),
    'edge_webhook_secret',
    'Shared secret sent by database webhooks to edge functions (x-webhook-secret header)'
)
where not exists (select 1 from vault.secrets where name = 'edge_webhook_secret');

-- 2. Verification RPC used by the edge functions (service_role only).
create function public.verify_webhook_secret(p_secret text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from vault.decrypted_secrets
        where name = 'edge_webhook_secret'
          and decrypted_secret = p_secret
    );
$$;
revoke execute on function public.verify_webhook_secret(text) from public, anon, authenticated;
grant  execute on function public.verify_webhook_secret(text) to service_role;

-- 3. Generic webhook trigger function. TG_ARGV[0] is the edge function slug.
--    Payload shape matches supabase_functions.http_request so the functions'
--    existing resolveEventType / resolveTableName / record parsing keeps working.
create function public.invoke_edge_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_function_slug text := tg_argv[0];
    v_secret        text;
    v_payload       jsonb;
begin
    select decrypted_secret
      into v_secret
      from vault.decrypted_secrets
     where name = 'edge_webhook_secret';

    if v_secret is null then
        raise warning 'invoke_edge_webhook: edge_webhook_secret missing from vault; skipping %', v_function_slug;
        return coalesce(new, old);
    end if;

    v_payload := jsonb_build_object(
        'type',       tg_op,
        'table',      tg_table_name,
        'schema',     tg_table_schema,
        'record',     case when tg_op = 'DELETE' then null else to_jsonb(new) end,
        'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
    );

    perform net.http_post(
        url                  := 'https://easlpsksbylyceqiqecq.supabase.co/functions/v1/' || v_function_slug,
        body                 := v_payload,
        headers              := jsonb_build_object(
                                    'Content-Type',     'application/json',
                                    'x-webhook-secret', v_secret
                                ),
        timeout_milliseconds := 5000
    );

    return coalesce(new, old);
end;
$$;
revoke execute on function public.invoke_edge_webhook() from public, anon, authenticated;

-- 4. Retire the key-embedding webhooks. They are DISABLED rather than dropped so the
--    change is reversible from the dashboard; drop them once delivery is confirmed:
--      drop trigger "notifcation-queue-processor" on public.notification_queue;
--      drop trigger message_push_webhook on public.messages;
alter table public.notification_queue disable trigger "notifcation-queue-processor";
alter table public.messages disable trigger message_push_webhook;

-- 5. Suppress the backlog that accumulated while delivery was broken (Apr 30 - Oct 5):
--    ~330 stale ride / reminder / approval alerts must not be blasted out once the
--    webhook works again. The sentinel timestamp makes the rows identifiable
--    (and reversible) later.
update public.notification_queue
   set sent_at = '2026-10-05 00:00:00+00'::timestamptz
 where sent_at is null
   and batch_key is null
   and processed_at is not null
   and created_at < '2026-10-05 00:00:00+00'::timestamptz;

-- 6. New webhooks authenticated with the Vault secret.
create trigger notification_queue_webhook
    after insert or update on public.notification_queue
    for each row
    execute function public.invoke_edge_webhook('send-notification');

create trigger message_push_webhook_secret
    after insert on public.messages
    for each row
    execute function public.invoke_edge_webhook('send-message-push');

