-- 20261005_0024_moderation_events_allow_fk_set_null.sql
--
-- APPLIED 2026-10-05 (Supabase MCP) and verified with a rolled-back probe.
--
-- content_moderation_events is append-only: a BEFORE UPDATE OR DELETE row trigger raised
-- unconditionally. Its two foreign keys are ON DELETE SET NULL (report_id -> reports,
-- acted_by -> profiles), and a referential SET NULL is an UPDATE that fires the trigger. So
-- deleting an account failed for any admin who had ever moderated (acted_by), and for any user
-- whose report or reported message/profile had been actioned (their reports cascade away and the
-- event's report_id must be nulled). This was a second, independent blocker for account deletion
-- next to the storage one fixed in 20261005_0008.
--
-- The trigger now lets through exactly one thing: an UPDATE issued from inside another trigger
-- (the RI trigger; pg_trigger_depth() > 1, a direct UPDATE has depth 1) that changes nothing
-- except nulling report_id and/or acted_by. Every other UPDATE and every DELETE still raises.
--
-- Probe (begin/rollback, using a temporary driver trigger to reach depth 2): direct UPDATE ->
-- rejected; nested null of acted_by and of report_id -> allowed; nested change of another
-- column and nested repoint of acted_by -> rejected.

CREATE OR REPLACE FUNCTION public.prevent_content_moderation_events_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    -- The log stays append-only, with one exception: the ON DELETE SET NULL foreign keys
    -- (report_id -> reports, acted_by -> profiles). Their referential action is an UPDATE issued
    -- from inside the RI trigger (pg_trigger_depth() > 1; a direct UPDATE has depth 1). Without
    -- this exception, deleting an account failed for any admin who had moderated and for any user
    -- whose report or reported content had been actioned.
    IF TG_OP = 'UPDATE'
       AND pg_trigger_depth() > 1
       AND (to_jsonb(NEW) - 'report_id' - 'acted_by') = (to_jsonb(OLD) - 'report_id' - 'acted_by')
       AND (NEW.report_id IS NULL OR NEW.report_id = OLD.report_id)
       AND (NEW.acted_by  IS NULL OR NEW.acted_by  = OLD.acted_by)
    THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'content_moderation_events is append-only';
END;
$function$;
