-- 20260403074134_security_storage_owner_policies.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Restrict storage UPDATE/DELETE to object owner.
-- Live confirmed: group-images UPDATE/DELETE and audio-messages DELETE
-- check only bucket_id with no owner check. owner column is uuid, populated on upload.
-- Audit ref: HIGH-2.

DROP POLICY IF EXISTS "Authenticated users can update group images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete group images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete audio messages" ON storage.objects;

CREATE POLICY "Owner can update group images"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'group-images' AND owner = auth.uid())
WITH CHECK (bucket_id = 'group-images' AND owner = auth.uid());

CREATE POLICY "Owner can delete group images"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'group-images' AND owner = auth.uid());

CREATE POLICY "Owner can delete audio messages"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'audio-messages' AND owner = auth.uid());
