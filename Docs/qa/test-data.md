# Persistent test data

Test data on the live backend that test passes may use instead of real communities. Set up on 2026-10-21 at the owner's request.

**Nothing real goes in these communities.** No real addresses, names, phone numbers or photos, and no real members other than platform admins testing a flow. Do not archive, delete, rename or change the type of any of them; if a pass needs a different setup, create a new test community instead.

## Test owner

| Display name | Id (first 8) | Platform admin | Where it is signed in |
|---|---|---|---|
| NC Test Owner | `eebf5514` | no | the simulator "iPhone 17 (26.5)" |

The account was made through the app's Sign Up. Its sign-in details are kept only on the owner's Mac in `build/test-data/test-accounts.local` (gitignored, mode 600), together with the full community ids. They never go in the repository.

## Test communities

All four are owned by NC Test Owner, who is their only member. Time zone America/Los_Angeles.

| Name | Type | Stored as | Id (first 8) | Purpose |
|---|---|---|---|---|
| Test Public A | public: listed, ask to join | `is_public = true`, `join_policy = 'approve'` | `86916d6c` | ask-to-join and approval flows; created in the app |
| Test Public B | public: listed, ask to join | `is_public = true`, `join_policy = 'approve'` | `b546bf31` | a second public community, for anything that needs two |
| Test Private A | private: hidden, invite only | `is_public = false`, `join_policy = 'invite'` | `9dac5e11` | invite codes and links; a code admits at once |
| Test Private B | private: hidden, invite only | `is_public = false`, `join_policy = 'invite'` | `e84d026f` | a second private community, for anything that needs two |

Open-join communities do not exist yet, so there is no test community of that type.

## How to use them

- **Join a public one as a platform admin.** On your own account, open the onboarding screen or Explore (the search tab) → Join a community, and ask to join Test Public A or B. Then, on the iPhone 17 as NC Test Owner, open Profile → My communities → the community's menu → Requests to join, and approve or decline.
- **Join a private one.** On the iPhone 17 as NC Test Owner, open Explore → the community's page → Invite. Use the code (or link) it shows on the other account. A private community never appears in the public list, so a code is the only way in.
- **Leave afterwards** if the test does not need the membership any more, so the communities stay small.
- Platform admins can read every community row, private ones included (D9), but the "Ask to join a public community" list shows only the public ones.

## How they were made

- **Test Public A** was created in the app on the iPhone 17 (Start your own community, "Approve new members manually" on). That ran `create_community`, which wrote the community, the owner's active membership, the "created the community" membership event, and an `announcement` bell row (no push) for each platform admin. The Invite sheet that opens after creation also made one single-use invite code that expires after 7 days. Listing a community is a platform-admin action (`set_community_public`, D7) and the Create sheet does not offer it to other accounts, so `is_public` was then set to true with the same single update that RPC makes.
- **The other three** were written in SQL because an account can create only one community a day. Each copies the app-made row column for column (only id, name, description, `is_public`, `join_policy` and timestamps differ) and writes the same owner membership and membership event as `create_community`, with the same suppression of the "you've been approved" notice. The bell rows to platform admins were left out on purpose.
- NC Test Owner now owns 4 communities and its limit is 3, so Create is refused with the owned-communities limit. This state is possible in the app as well (taking over ownership does not check the limit), and it is a ready-made case for testing "Request a higher limit".

## Test Community (the default community)

The default community (id first 8 `7a8ed131`, until then "Naar's Cars Seattle") was renamed **Test Community** on 2026-10-21 at the owner's decision. It is the example community that guests and new accounts explore; the design of its example content is in `Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md` (4.10 and 4.11). Unlike the four communities above, it has real members (19 active), so **test passes do not post in it**; use the four test communities.

**What changed on 2026-10-21.** One update set the name and a new description ("This is the example community for exploring Naar's Cars. Nothing posted here is a real request, and real neighborhoods have their own communities."). Nothing else on the row changed: it is still the default community, listed (`is_public = true`), ask to join (`join_policy = 'approve'`), members can invite, time zone America/Los_Angeles, not archived. No trigger on `communities` sends anything for a name or description change.

**The members' earlier content is hidden, not deleted.** Every ride, favor, Town Hall post and Town Hall comment in it that was not already hidden was hidden at 2026-10-21 16:48:50 UTC with the columns the moderation RPCs write (`hidden_at`, `hidden_by` = the platform owner, `hidden_reason` = "Community converted to Test Community (2026-10-21)"):

| Content | In the community | Hidden by this change | Already hidden by moderation |
|---|---|---|---|
| Rides | 107 (100 completed, 6 confirmed, 1 open) | 107 | 0 |
| Favors | 61 (59 completed, 2 confirmed) | 61 | 0 |
| Town Hall posts | 34 (incl. 5 announcements and 11 review posts) | 31 | 3 |
| Town Hall comments | 10 | 10 | 0 |

The Q&A under those requests (37) and their reviews (15) have no hide columns; their read policies follow the request, so they went out of sight with it (a review stays visible to its writer and the person reviewed). All confirmed and open requests were in the past; none was an upcoming arrangement.

- **Who still sees it.** Each author still sees their own hidden rows (the moderation design: SECURITY.md, the `hidden_at IS NULL OR <author>` pattern). Nobody else does through the app, platform admins included: the read policies have no admin exception, so a platform admin sees only their own. Probed on 2026-10-21 in rolled-back transactions: a member with no content of their own, a guest (tables and `guest_rides` / `guest_favors`), a non-member and a platform admin with no content of their own all read 0 rides, favors, posts, comments, Q&A and reviews for the community.
- **Nothing was sent.** On an update that changes only the hide columns, the request triggers return early (status and helper unchanged), so no bell row, push, XP row or completion reminder was created (checked afterwards: none in that window).
- **What hiding did not change.** The XP rows (244 for this community), the XP leaderboard, spotlights, profile figures (rating, fulfilled count, savings) and the admin statistics still count this content: those functions do not read the hide columns. Old bell rows still link to the requests; for anyone but the author the linked request can no longer be read. 11 reports name some of this content; they were left as they were (2 are still pending in the platform queue).
- **Side effect.** The `updated_at` trigger stamped every hidden row with the hide time. For a completed request `updated_at` is the date the admin "fulfilled" chart and the spotlight periods use, so those now place the 159 completed requests in the week of 2026-10-21. 119 of them already carried the nightly job's batch stamp of 2026-10-06 / 2026-10-08; for 39 of the other 40 the original completion time is still in their XP row.

**Permanent deletion is the owner's step**, in the SQL editor: `supabase/scripts/2026-10-21_test_community_cleanup.sql` (NOT APPLIED). It only touches rows created before the hide, so example content added later is safe, and its header lists what deleting removes for the members (request history, all 15 reviews, profile figures; XP stays).

**Follow-up.** `Docs/AppStore/2026-10-multi-community-review-notes.md` still describes the review account as a member of "Naar's Cars Seattle" that lands in the app with content. Until example content exists, the reviewer lands in an empty Test Community; update the notes and the content before the next submission.
