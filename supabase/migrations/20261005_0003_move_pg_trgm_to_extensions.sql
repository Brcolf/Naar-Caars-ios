-- 20261005_0003_move_pg_trgm_to_extensions.sql
--
-- Move pg_trgm out of the public schema (Supabase advisor: extension_in_public).
-- The only dependent object is idx_messages_text_trgm, which references the
-- operator class by OID and is unaffected. Applied separately from the function
-- lockdown because ALTER EXTENSION can take noticeably longer.

alter extension pg_trgm set schema extensions;
