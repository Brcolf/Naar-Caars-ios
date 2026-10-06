# Functional and design QA pass, 2026-10-06

Branch `claude/quirky-gates-4bkmv4`, nothing committed. Built headless with Xcode 26.6 for iPhone 16 / iOS 26.5; the app builds with 0 errors and the unit test target compiles. The unit suite was **not run** (the simulator is signed in, and a signed-in run posts to the live Town Hall).

Every audit finding and its status is in [2026-10-06-audit-findings.md](2026-10-06-audit-findings.md).

## 1. Result

The core loop works end to end with two accounts: post a ride or favor, ask a question, claim, unclaim, message, complete, review, and see the review in Town Hall, with the right notifications, reminders and XP on the server at each step.

Three kinds of problems came out of the pass:

1. **Things that were broken when used.** Adding participants to a ride or favor saved nothing. A push tapped while the app was closed opened the Requests list and stopped. A favor posted for "today" with no time vanished from every list at noon. All fixed and re-tested; the full list is in section 3.
2. **Server rules that let one member act on another's data.** Any signed-in member could rewrite, take over, hide or self-complete someone else's open request, and could post a review of a helper on a request they had nothing to do with. Both are closed with database changes that are applied and recorded as migrations (section 4).
3. **A code audit of 196 findings**, 193 confirmed by two independent reviewers. 145 are fixed, 25 fixed in part, 26 open (section 5). The open ones are mostly in sign-in, sign-out and push handling, where a wrong fix is worse than the defect and a real device is needed to verify.

About 200 Swift files changed, plus the string catalog and four migrations.

## 2. How it was tested

- **Simulator, signed in as the admin account.** Every tab and most sheets, in dark mode, with a light-mode recheck of the screens that changed. Posts, comments, questions, rides, favors, claims, completions and reviews were created through the app.
- **A second account (Alice) driven on the server**, through the same table writes and RPCs the app sends, run as that user so row-level security and triggers applied exactly as they would for her phone. This is what made claim, unclaim, messaging and review testable from both sides. Nobody's password was typed anywhere.
- **Simulated pushes** (`xcrun simctl push`) for push-tap routing: app closed, app in the background, app open on another tab.
- **Rolled-back probes** for server rules: each attempted write ran inside a transaction that was then discarded, so nothing was changed while checking what a member is allowed to do.
- **A read-only code audit** by area (design system, accessibility, forms, requests, Town Hall, profile and admin, sign-in, messaging, localization, platform conventions, then notifications, the message thread, session handling and maps/calendar in a second round), with every finding re-checked by two reviewers working from the code.
- **Two fix rounds**, one engineer per area with no shared files, each followed by an independent review of the diff and a repair pass. Then one build, and a simulator check of what a simulator can show.

## 3. Flows exercised and what was found

| Flow | Result |
|---|---|
| Post a ride, edit it, ask a question, delete it | Works. Deleting now refreshes the list on its own. |
| Add a participant to a ride or favor | **Was broken: nothing was saved and no error shown.** Fixed; verified in the app and in the database. |
| Post a favor (no time) | Works. **Was hidden from every list from noon of its day and expired by the server that evening.** Fixed in the app and in the expiry job. |
| Second account claims the admin's ride | Works. Poster's list, badge and inbox update; one "claimed" notification; completion reminder scheduled. |
| Second account unclaims | Works. Ride reopens, reminder removed, poster notified. |
| Admin claims the second account's ride from the app | Works, including the new "someone else already claimed this" check. |
| Helper marks a ride complete | Works. Poster gets the completion and review-request notifications; XP awarded to both. |
| Poster marks a favor complete and leaves a review | Works. Review row, Town Hall post and notifications created. |
| Town Hall: post, comment, reply, vote, delete comment, delete post | Works. A new comment said "in 0 seconds"; fixed. |
| Messages: receive, reply, read receipt, live reply while the thread is open | Works live. **"Read" fell back to "Delivered" after reopening the thread**; fixed. |
| Push tap with the app closed | **Was broken: opened the Requests list only.** Fixed for rides, favors, conversations and Town Hall posts; verified for a ride. |
| Push tap for a message before Messages was opened | **Stopped at the conversation list.** Fixed; verified. |
| Push tap with the app open on another tab | Works; switches tab and opens the ride. |
| Notifications inbox | Works. A failed refresh no longer replaces the list with an error screen. |
| Profile, edit profile, settings, admin panel | Works. Three Messaging switches did nothing and were removed; clearing phone or car now saves; a photo chosen on Profile is now saved. |
| Leaderboard | Works. One spotlight row drew no icon (an invalid symbol name); fixed. Every symbol name in the app was then checked against the system catalog. |
| Welcome screen, logged out | Renders correctly in light, dark and at the largest text size. Deeper logged-out screens could not be driven (section 6). |

Other defects fixed from using the app: text typed while a comment was being sent got mixed into it and then wiped; the unseen-count badge sat on top of the filter tile's label; today's favors sorted below tomorrow's requests; review posts showed the rating twice; the public profile's Badges card was narrower than the other cards; the conversations skeleton never showed on first load; the app's own (always rejected) attempt to write the poster's claim notification could make a successful claim look failed.

## 4. Server findings and the database changes

Applied through the Supabase MCP and recorded under `supabase/migrations/`. Each was tried first inside a rolled-back transaction, then re-probed live.

| Migration | What it closes | Still allowed |
|---|---|---|
| `20261006_0001_guard_request_client_update` | The update policies on `rides` and `favors` are all permissive, so their checks combine with OR. A member who was neither poster nor helper could change any column of an open request, make themselves its owner, hide it, or mark it completed with themselves as helper (which awards XP). A trigger now limits direct client updates. | Poster: edit own request. Others: claim, unclaim, and the helper marking it complete. Server functions (`complete_request`, moderation, expiry) are unaffected. |
| `20261006_0002_reviews_insert_requires_own_completed_request` | Any member could review any helper on any completed request, creating a public Town Hall post, a rating change and XP. | The poster reviewing their own helper on a completed request, which is the only thing the app offers. |
| `20261006_0003_guard_invite_code_client_update` | Marking an invite code as used could also rewrite the code text, its inviter and its expiry. | Marking an unused code as used by yourself during sign-up. |
| `20261006_0004_expire_dateonly_favors_after_their_day` | A favor with no time was expired at noon of its day. | Timed favors and rides are unchanged. |

To undo the first or third: drop the trigger named in the file. The second and fourth replace an existing policy check and function; the previous definitions are in `20260320211355_fix_rls_policy_bypasses_and_messages_tautology.sql` and `20261005_0010_expire_favors_without_time_parity.sql`.

Found and **not** changed (need your decision, or a statement the MCP declines):

- **Guests can read every ride's pickup, destination, notes and flight** through the public API key. The app hides addresses from guests, but only on screen. Fix: serve guests from a view that leaves those columns out, as was done for profiles.
- **A signed-in account can mark every unused invite code as used by itself**, one code per request. Fix: mark codes only through the existing `mark_invite_code_used` function with a caller check, then retire the update policy.
- Request questions have no report target of their own (a question is reported against its asker), and reviews cannot be hidden by moderators.
- The poster is notified about their own completion ("Your favor has been marked as completed"), the unclaim notification says "The helper" instead of the name, and a helper who receives a review only gets the generic "New in Town Hall" notification.
- Deleting a claimed request does not tell the helper.
- Still waiting from the previous pass (SQL editor only): `20261005_0008`, `0022`, `0025`, `0026`. Account deletion still fails on the server until `0008` is applied.

## 5. The code audit

| Area | Findings | Fixed | In part | Open |
|---|---|---|---|---|
| Design system regressions | 14 | 13 | 1 | 0 |
| Accessibility | 14 | 14 | 0 | 0 |
| Forms and validation | 14 | 13 | 1 | 0 |
| Requests | 14 | 10 | 4 | 0 |
| Town Hall, reviews, leaderboard | 14 | 13 | 1 | 0 |
| Profile, settings, admin | 14 | 12 | 2 | 0 |
| Sign-in and onboarding | 14 | 10 | 2 | 2 |
| Messaging screens | 14 | 13 | 0 | 1 |
| Localization and copy | 14 | 7 | 4 | 3 |
| Platform conventions | 14 | 13 | 1 | 0 |
| Notifications and push routing | 14 | 7 | 2 | 5 |
| Message thread | 14 | 5 | 6 | 3 |
| Sign-out, session, local state | 14 | 6 | 1 | 7 |
| Maps, flights, cost, calendar | 14 | 9 | 0 | 5 |
| **Total** | **196** | **145** | **25** | **26** |

What changed, in plain terms:

- **Failures are visible and nothing typed is lost.** Lists keep their content when a refresh fails and show a banner; forms ask before discarding; comment, question and message text survives a failed send; admin actions and loads report errors instead of looking empty.
- **Screens that trapped people no longer do.** The completion and review prompts can be closed; the guidelines sheet reports a failed save and can be retried.
- **App Store relevant.** Account deletion is offered on the pending-approval and application screens. Post and comment authors can be blocked from Town Hall. The photo-save crash is gone (a purpose string was missing). Permission purpose strings now say what the code does. Community Guidelines acceptance is no longer skipped on a cold launch.
- **Accessibility.** Labels, values and 44-pt targets on the icon-only controls; star rating, time picker and vote state usable with VoiceOver; toasts and banners announced; Reduce Motion honoured; layouts that reflow at accessibility text sizes; message bubbles read with sender and time.
- **Navigation.** One navigation bar per screen (Leaderboard, admin lists, Past Requests, Announcements); push and inbox taps open their target.
- **Sign-out.** Recent addresses, pinned threads, pending attachments, delivered notifications and badge counts no longer survive into the next account or guest session.
- **Copy and strings.** Raw keys no longer appear in Spanish, Korean, Vietnamese or Chinese (English is shown until a translation exists); hardcoded English moved to the catalog; "Sign In" is used consistently; seat counts and status chips are whole localized strings.

## 6. What is still open

**Needs you**

1. **Translations.** 367 catalog keys now have English only (215 before this pass; the rest are strings that used to be hardcoded or are new). They display in English in every language.
2. **Brand artwork and the leftover Town Hall test posts**, as before.
3. **SQL editor:** the four migrations from 2026-10-05 listed above.
4. **Decisions:** what guests may see of a request (the address exposure above); whether the poster should ever see the helper's phone number (claiming requires one "so the poster can coordinate", but nothing shows it); which calendar permission model to use; what "My Savings" should count; whether received links should load previews automatically.
5. **Privacy manifest and App Store Connect labels** (account id and street addresses are not declared). Left alone because editing it carries submission risk and needs an archive to verify.

**Deliberately not changed** (sign-in, sign-out and push internals; each has a specific recommended fix in the findings file)

- Sign Out ends the session on every device, and a session ended by the server is not handled.
- A push token can stay attached to an account after sign-out on some paths.
- Account deletion decides whether to revoke Sign in with Apple from a device-wide flag.
- Approval detected on the waiting screen enters the app without the normal session setup.
- Offline at launch can show the application form or Welcome instead of a retry.
- Quick reply and Mark as Read from a notification are dropped when the app was not running.
- No banner for a message in another conversation while a thread is open.
- A second Apple authorization can create a profile named "Apple User".
- Town Hall pushes mark the feed stale instead of refreshing it (wrong payload key; one-line fix that switches on a sync path that has never run in production).

**Known, small**

- A member re-added to a group cannot leave it (service and RPC change).
- Voice notes: no length limit, no interruption handling, retry of a failed voice note is unreliable.
- An unread divider can appear late in an open thread.
- After submitting a review the app jumps to the review post's (empty) comments sheet with no context.
- Small avatars get crowded with two badges.

## 7. What could not be tested

- **Creating, approving and deleting a new user.** I do not create accounts or type passwords on a remote service, and there were no pending applicants to approve. The approval screens were checked with an empty queue only. This needs a throwaway sign-up from you; the approve / reject / restrict paths now report failures, which they did not before.
- **Logged-out screens beyond Welcome.** The second simulator device could not be driven without your permission in the simulator panel. Sign-in, sign-up, guest mode and the pending-approval screen were changed (layout, labels, Return-key flow, account deletion) and reviewed in code, but not seen running.
- **Sending an announcement to all users.** Blocked by the session's safety check; not retried.
- **Real devices:** Sign in with Apple, Face ID lock and the new privacy cover, voice notes (microphone), camera, lock-screen notification actions, and group-thread behaviour with two phones.
- **The unit suite.** Compiles; not run, for the reason at the top. Run it signed out before merging.

## 8. Test data left on the backend

- Completed ride "Fremont Troll → Gas Works Park" (Oct 6) posted as Alice, claimed and completed by the admin, with one question, Alice's 5-star review and its Town Hall post.
- Completed favor "QA test favor, please ignore" (Oct 6) with the admin's 5-star review of Alice. Its Town Hall post was deleted from the app.
- Three messages in the admin–Alice thread, and one unsent message in the "CTO, Green J…" group.
- Notifications sent to all approved members for the test ride, favor and review posts (about 18 each), and the XP those actions awarded.
- Not from this pass: three "Test Pickup → Test Destination" rides and three "Test Favor" favors dated Oct 6 on the admin account. They look like leftovers from signed-in unit test runs.

The admin's test ride (Pike Place Market → Ballard Lock & Key) was deleted from the app at the end, which removed its participant and question with it.
