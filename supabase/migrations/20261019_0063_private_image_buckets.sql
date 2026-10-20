-- 20261019_0063_private_image_buckets.sql
--
-- APPLIED 2026-10-20, all four blocks. Block 1, block 3, and block 4's bucket update and create policy through the
-- Supabase MCP apply_migration (the migration-history versions in the paragraph below); the nine DROP POLICY
-- statements (block 2's seven and block 4's two, quoted below) by the owner in the SQL editor the same day, as
-- Step 4 of Docs/qa/2026-10-20-5b-owner-sql-steps.md (not in the migration history). Verified through the MCP
-- afterwards: message-images, group-images, town-hall-images, review-images and audio-messages are private and
-- avatars public. The SELECT policies on storage.objects are "Avatar public read" and the five new ones
-- (message_images_read_participants, group_images_read_participants, town_hall_images_read_visible,
-- review_images_read_visible, audio_messages_read_participants); the nine old ones are gone. Probes after all four
-- owner steps (rolled back, PARAMETERS and HELPERS, probes under savepoints): storage_private OK, the full unedited
-- block through the MCP (its inserts into storage.objects were accepted and rolled back; the five buckets held 34
-- objects before and after); short OK. Final not-applied check: every column false, all_unchanged false. Still to do outside
-- SQL: iOS plan Task 12 Step 4 (the two-simulator check, and the public route answering 400). The paragraphs that
-- follow are the partial-apply record, kept as history.
--
-- PARTIALLY APPLIED 2026-10-20 through the Supabase MCP apply_migration, one call per block, in file order:
-- block 1 (20261020164600 20261019_0063_block_1), block 3 (20261020164642 20261019_0063_block_3), and block 4
-- WITHOUT its two drop policy lines (20261020164719 20261019_0063_block_4: the audio-messages update and the
-- audio_messages_read_participants policy). NOT APPLIED: block 2 and the two drop policy lines of block 4, nine
-- DROP POLICY statements the MCP declines; they are the owner's SQL-editor step (text below and in
-- Docs/qa/2026-10-20-5b-owner-sql-steps.md). Contrary to the plan's expectation the MCP accepted the writes to
-- storage.buckets and the create policy statements on storage.objects. Both gate conditions were confirmed by the
-- owner on 2026-10-20 from App Store Connect (A5 point 2 and D-S9: every build in use contains the Phase 5a
-- client, which reads these buckets through signed URLs).
--   State now: message-images, group-images, town-hall-images, review-images and audio-messages are private
--   (public route 400), avatars public; the five new read policies exist; the nine old read policies (seven image,
--   two audio) still exist, and because permissive policies are OR'ed they still let anyone, anon included, read
--   every object of those buckets through the storage API (sign a URL, download). So until the owner runs the drops
--   the read rule is no stricter than before this file, and nothing a Phase 5a client does stops working. This
--   split replaces the file's one-transaction apply (the orchestrator's instruction of 2026-10-20, after the owner's
--   D-S9 confirmation); the file is not to be run again as a whole (its create policy statements would fail on the
--   existing names and roll the whole transaction back).
--   Outcomes, 2026-10-20. P2 re-read: six public buckets, the ten SELECT policies of the plan's P2 (seven image, two
--   audio, avatar), 34 objects in the five buckets. Subset dry run (blocks 1, 3, 4 without the drops, inside
--   begin; ... rollback; with the probe PARAMETERS and HELPERS, probes under savepoints): short OK; storage_private
--   FAILED as expected at its second check, "no SELECT policy on those buckets is a bare bucket test any more" (its
--   first check, the four buckets private and avatars public, passed); afterwards all buckets were still public and
--   no new policy existed. Apply: short after each of the three calls: OK; then storage_private again: the same
--   expected failure (in that call its block was sent cut after the message-image checks, which does not change
--   the outcome; the unedited block ran in the dry run). The probe was not edited. Not-applied check afterwards:
--   buckets_all_public false, new_storage_read_policies_absent false, old_storage_read_policies_present true.
--
-- Owner's SQL-editor step, the exact text (run it alone in a new tab, in this order, after File C):
--   drop policy if exists "Allow public read access on message-images" on storage.objects;
--   drop policy if exists "Message image read" on storage.objects;
--   drop policy if exists "Allow public read access on group-images" on storage.objects;
--   drop policy if exists "Anyone can view group images" on storage.objects;
--   drop policy if exists "Allow public read access on town-hall-images" on storage.objects;
--   drop policy if exists "Town hall public read" on storage.objects;
--   drop policy if exists "Allow public access to review images" on storage.objects;
--   drop policy if exists "Allow public read access on audio-messages" on storage.objects;
--   drop policy if exists "Anyone can view audio messages" on storage.objects;
-- Then the not-applied check (old_storage_read_policies_present false) and storage_private (OK).
--
-- (Before the gate.) GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2) AND that every build in use contains the Phase 5a client (it downloads these
-- buckets through signed URLs). SQL EDITOR (owner), as ONE transaction: DROP POLICY and the write to
-- storage.buckets are declined by the Supabase MCP. Phase 5b (§4 "Phase 5": private storage buckets with
-- signed URLs for message-images, group-images, town-hall-images, review-images; D16).
--
-- What it does.
--   1. storage.buckets.public = false for the four buckets: the public route
--      /storage/v1/object/public/<bucket>/... stops serving them (400). Avatars stay public.
--   2. Their public SELECT policies on storage.objects are dropped (seven, listed in the plan's P2), and four
--      SELECT policies take their place. They decide who may create a signed URL and download an object:
--        message-images, group-images (path <conversation id>/<file>): the uploader, or a participant of that
--        conversation (any conversation_participants row of the caller, including one who left: they still
--        read the thread within their window);
--        town-hall-images (path <file>): the uploader, or anyone (guests included) who can read a Town Hall post
--        or a review whose image_url names the object (the posts' and reviews' own policies decide, so a guest
--        sees only public communities' photos);
--        review-images (path <UUID>.jpg, a fresh UUID per upload, not the review id: ReviewService.swift:60,
--        :196): the uploader, or anyone who can read a review, or a Town Hall post, whose image_url names the
--        object (no live review carries an image on 2026-10-19; the 5 objects in the bucket are orphans, readable
--        after this file by their uploader only). The post clause covers the shape
--        ReviewService.createTownHallPostForReview builds (:237-257; no caller today, 0 such posts live).
--      The uploader clause also keeps the group and review uploads working: they use upsert, which needs
--      SELECT on the object.
--   3. audio-messages: private, the participant policy (block 4; decisions A6 point 1: voice notes are in Phase 5,
--      so this block runs with the others; iOS Task 8 ships in the same build).
--   INSERT, UPDATE and DELETE policies are unchanged.
--
-- What old clients see. A build without the 5a client (the installed build, Phase 1-4 builds): every
-- message photo, group photo, Town Hall photo and review photo fails to load (its image placeholder or
-- error view); uploads still succeed, and the photos it sends are readable by the 5a client. With block 3,
-- its voice notes fail to play. Avatars are unaffected.
--
-- Verification. Dry run (now, owner, SQL editor): NOT this file. Paste only
-- supabase/dryruns/20261019_0063_private_image_buckets.dryrun.sql, verbatim (blocks 1-3 inside one begin; ...
-- rollback;, the probe helpers without their commit;, storage_private and short as savepoints); then the
-- not-applied check in a new tab, which must show buckets_all_public = true. At the gate: this file as one
-- transaction, storage_private after the commit, then iOS plan Task 12 Step 4 (the two-simulator check and the
-- 400 from the public route). Outcomes: not yet run.
--
-- Rollback. update storage.buckets set public = true where id in (...); drop the four new policies; recreate
-- the seven dropped ones from the plan's P2 (each "for select to public using (bucket_id = '<bucket>')", and
-- "Message image read" with its EXISTS clause).

begin;

-- BLOCK 1: the buckets
update storage.buckets set public = false
 where id in ('message-images', 'group-images', 'town-hall-images', 'review-images');

-- BLOCK 2: the public SELECT policies
drop policy if exists "Allow public read access on message-images" on storage.objects;
drop policy if exists "Message image read" on storage.objects;
drop policy if exists "Allow public read access on group-images" on storage.objects;
drop policy if exists "Anyone can view group images" on storage.objects;
drop policy if exists "Allow public read access on town-hall-images" on storage.objects;
drop policy if exists "Town hall public read" on storage.objects;
drop policy if exists "Allow public access to review images" on storage.objects;

-- BLOCK 3: who may read each object
create policy message_images_read_participants on storage.objects
  for select to authenticated
  using (
    bucket_id = 'message-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.conversation_participants cp
                  where cp.user_id = (select auth.uid())
                    and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
    )
  );

create policy group_images_read_participants on storage.objects
  for select to authenticated
  using (
    bucket_id = 'group-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.conversation_participants cp
                  where cp.user_id = (select auth.uid())
                    and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
    )
  );

create policy town_hall_images_read_visible on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'town-hall-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.town_hall_posts p
                  where p.image_url is not null
                    and position(('/town-hall-images/' || storage.objects.name) in p.image_url) > 0)
      or exists (select 1 from public.reviews r
                  where r.image_url is not null
                    and position(('/town-hall-images/' || storage.objects.name) in r.image_url) > 0)
    )
  );

create policy review_images_read_visible on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'review-images'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.reviews r
                  where r.image_url is not null
                    and position(('/review-images/' || storage.objects.name) in r.image_url) > 0)
      or exists (select 1 from public.town_hall_posts p
                  where p.image_url is not null
                    and position(('/review-images/' || storage.objects.name) in p.image_url) > 0)
    )
  );

-- BLOCK 4 (D-1; runs per decisions A6 point 1, voice notes included; needs iOS Task 8 in every build in use)
update storage.buckets set public = false where id = 'audio-messages';
drop policy if exists "Allow public read access on audio-messages" on storage.objects;
drop policy if exists "Anyone can view audio messages" on storage.objects;
create policy audio_messages_read_participants on storage.objects
  for select to authenticated
  using (
    bucket_id = 'audio-messages'
    and (
      owner_id = (select auth.uid())::text
      or exists (select 1 from public.conversation_participants cp
                  where cp.user_id = (select auth.uid())
                    and cp.conversation_id::text = lower((storage.foldername(storage.objects.name))[1]))
    )
  );

commit;
