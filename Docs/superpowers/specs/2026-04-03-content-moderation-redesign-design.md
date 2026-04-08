# Content Moderation Redesign

**Date:** 2026-04-03
**Status:** Approved

---

## Overview

This redesign fixes the current gap between the admin moderation UI and actual app behavior.

Today, admins can report, hide, restore, and dismiss content in the UI, but the live backend does not consistently apply those actions to the underlying content. In particular:

- `admin_moderate_content` updates `reports.content_hidden` but does not hide the actual post, comment, message, ride, or favor record.
- Town Hall has partial auto-hide support, but manual hide is not reliably reflected in user-visible content.
- Messages, rides, and favors can be reported but do not have a real hide model.
- Authors are not notified when their content is hidden.
- The current admin queue is effectively one-way: once a report is acted on, the UI does not support good reversal or escalation workflows.

The approved direction is:

1. Hide must actually affect the underlying content.
2. Hidden content must be invisible to other users.
3. The author must still be able to see a moderator-hidden placeholder for their own content.
4. The author must receive a notification with the moderator-provided reason when content is hidden.
5. Admin moderation actions must be reversible.
6. The audit trail must be append-only even when content state changes later.

This design applies that model consistently across messages, Town Hall posts/comments, and ride/favor requests.

---

## Product Rules

### Hide

`Hide` means:

- The content is no longer visible to other regular users.
- The author still sees the content location represented by a placeholder state.
- The author receives an in-app and push notification explaining that the content was hidden and why.
- The action is reversible later with `Restore`.

### Dismiss

`Dismiss` means:

- The selected report is resolved with no change to content visibility.
- The content stays visible.
- The report can still be escalated later to `Hide` if new evidence appears.

### Restore

`Restore` means:

- Previously hidden content becomes visible again.
- The audit log remains intact.
- The content may still be hidden again later if moderation changes.

### Automatic threshold hide

In v1, automatic threshold hide remains limited to:

- Town Hall posts
- Town Hall comments

Messages, rides, and favors do not auto-hide based on report count in v1. They require explicit admin review before hide. This keeps the first rollout conservative on higher-risk surfaces, especially messaging.

### Moderation Audit

Moderation outcomes are reversible. Moderation history is not.

The system must preserve:

- who acted
- when they acted
- what action they took
- which target they acted on
- which moderator reason they provided

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Visibility enforcement | Server-side visibility rules plus client placeholder rendering | Prevents hidden content from remaining fetchable to other users while still allowing author placeholders |
| Moderation state model | Separate report status from content visibility | A report decision and a content state are not the same thing |
| Hide reason | Required for `Hide` | Authors need an explanation; admin intent should be explicit |
| Dismiss note | Optional | Useful for internal context without blocking quick moderation |
| Restore note | Optional | Helpful for audit context but not required |
| Audit model | Append-only moderation events | Allows reversibility without destroying history |
| Author UX | Placeholder only for the author | Matches approved behavior from product discussion |
| Queue reversibility | `Hide`, `Dismiss`, and `Restore` remain available based on current content state, not just initial report status | Avoids one-way moderation mistakes |

---

## Current Broken Behavior

### Verified from live backend

- The live `admin_moderate_content` RPC updates report metadata but does not update the underlying content rows.
- The live `handle_new_report` trigger auto-hides only Town Hall posts/comments after 3 distinct reports.
- `content_reported` notifications go only to admins.
- No author-facing moderation notification exists.

### Verified from app code

- `AdminReportsView` has no confirmation flow or reason entry for `Hide`.
- `AdminReportsView` does not surface backend errors.
- `AdminReport` does not model rides, favors, or messages explicitly enough for strong admin UX.
- `MessageThreadViewController` ignores `.report`, so thread reporting is broken in one path.
- Town Hall feed code still hard-filters `hidden_at IS NULL`, which prevents an author placeholder model.
- `NotificationTypeRegistry.swift` is missing `content_reported` even though the enum and TypeScript registry include it.

---

## Moderation Data Model

### 1. Keep `reports` as the report-submission record

`reports` continues to represent user submissions. It should not be the sole source of truth for content visibility.

It may keep workflow fields like:

- `status`
- `reviewed_at`
- `reviewed_by`
- `admin_notes`
- `content_hidden`

But actual visibility must be derived from the content row itself.

### 2. Add explicit moderation fields to all user-generated content tables

Normalize the same moderation fields across:

- `messages`
- `town_hall_posts`
- `town_hall_comments`
- `rides`
- `favors`

Required fields:

- `hidden_at TIMESTAMPTZ NULL`
- `hidden_by UUID NULL REFERENCES profiles(id)`
- `hidden_reason TEXT NULL`

Meaning:

- `hidden_at IS NULL` means visible
- `hidden_at IS NOT NULL` means hidden
- `hidden_by IS NULL` means system/automatic hide
- `hidden_by IS NOT NULL` means manual admin hide
- `hidden_reason` stores the most recent moderator-visible reason for the current hidden state

### 3. Add moderation event history

Create a new append-only table:

`content_moderation_events`

Columns:

- `id`
- `target_type` (`message`, `town_hall_post`, `town_hall_comment`, `ride`, `favor`)
- `target_id`
- `report_id` nullable
- `action` (`hide`, `dismiss`, `restore`, `auto_hide`)
- `acted_by` nullable for system actions
- `reason` nullable
- `created_at`

This table is the permanent audit log and is never rewritten.

---

## Server-Side Visibility Rules

### Core rule

Hidden content is visible only to:

- the content author
- admins

Hidden content is not visible to:

- other regular authenticated users
- guests
- other conversation participants if the content is a hidden message and they are not the sender

### Why server-side enforcement is required

The current Town Hall model relies partly on client filtering. That is not enough for moderation because hidden content remains fetchable unless the server restricts it.

The redesign therefore moves visibility rules to the database layer.

### Implementation approach

Apply viewer-aware select rules to each moderated content table so that reads return:

- visible content to everyone who is otherwise allowed to see the row
- hidden content only to the author and admins

This can be done either with updated RLS policies or narrowly scoped RPC/view-backed fetches where RLS is too risky to alter directly. The preferred path is RLS if it can be changed safely without breaking existing auth behavior.

### Table-specific rule summary

#### `messages`

- Existing participant visibility rules remain intact.
- Add hidden-content visibility exception:
  - sender sees hidden messages
  - admins see hidden messages
  - other participants do not

#### `town_hall_posts`

- Visible posts remain public according to existing app behavior.
- Hidden posts are returned only for the post author and admins.

#### `town_hall_comments`

- Visible comments remain visible as today.
- Hidden comments are returned only for the comment author and admins.

#### `rides`

- Hidden rides are visible only to the request author and admins.
- They must disappear from dashboard feeds for everyone else.

#### `favors`

- Hidden favors are visible only to the request author and admins.
- They must disappear from dashboard feeds for everyone else.

---

## Client Rendering Rules

The client must stop treating moderation as equivalent to deletion.

Instead, hidden content should render according to viewer role.

### Shared placeholder contract

If a row has `hiddenAt != nil`:

- author view: show placeholder
- admin moderation view: show actual content preview plus moderation context
- all other users: row is absent because the server does not return it

### Placeholder copy

Use product copy that clearly distinguishes moderator action from user unsend/delete behavior.

Example:

- title: "Content hidden by moderators"
- body: "Only you can still see that something was here."

The exact localized strings will be defined during implementation, but they must not reuse the existing unsent-message strings.

### Messages

Messages are the highest-risk surface because conversation continuity matters.

Behavior:

- For non-authors, a hidden message disappears from the conversation stream.
- For the sender only, the message remains in the stream as a moderator-hidden placeholder.
- The placeholder is distinct from the existing unsent placeholder.
- Reactions, reply affordances, copy, edit, and report actions are disabled on hidden-message placeholders.

### Town Hall posts

Behavior:

- Hidden posts disappear for everyone except the author and admins.
- The author sees the post shell with a moderator-hidden placeholder instead of the original body/media.
- Vote and comment actions are disabled on the placeholder.
- If the hidden post is opened directly by a non-author, the user should land on not-found/unavailable rather than seeing hidden content.

### Town Hall comments

Behavior:

- Hidden comments disappear for everyone except the author and admins.
- The author sees a placeholder row in the comment thread so conversation structure remains understandable.
- Reply and vote actions are disabled for the placeholder.

### Rides and favors

Behavior:

- Hidden requests disappear from public dashboard and request discovery surfaces.
- The author still sees their own hidden request as a placeholder card/detail state.
- Claiming, Q&A, edit, and share actions are disabled while hidden.
- Existing participants who are not the author do not continue to see the hidden request content.

---

## Admin Queue UX

### Core correction

The current UX is not ideal because it collapses report workflow and content state into one irreversible decision.

The redesign separates them:

- report workflow: `pending`, `dismissed`, `action_taken`
- content state: `visible`, `hidden`

### Action availability

Admin actions depend on current content state, not only on the current report status.

| Content state | Report status | Show actions |
|---|---|---|
| Visible | Pending | `Hide`, `Dismiss` |
| Hidden | Pending (auto-hidden) | `Hide`, `Restore` |
| Visible | Dismissed | `Hide` |
| Hidden | Action taken | `Restore` |
| Visible | Action taken after restore | `Hide` |

`Dismissed` means "no action at this time," not "locked forever."

For auto-hidden content, `Hide` means "confirm and keep hidden with moderator reason." `Dismiss` is not offered in that state because dismissing while leaving content hidden is internally inconsistent.

### Confirmation flows

#### Hide

Require a confirmation sheet with:

- concise explanation of impact
- required moderator reason

Confirmation copy:

"This will hide the content from other users. The author will still see a moderator-hidden placeholder and will receive your reason."

#### Restore

Require confirmation, optional note.

Confirmation copy:

"This will make the content visible again to other users."

#### Dismiss

No reason required. Optional note allowed.

Confirmation copy:

"This resolves the report without changing content visibility."

### Queue presentation

The admin queue should continue to expose:

- content preview
- reporter
- report count
- current hidden state
- latest moderation state

But it should also expose content target type clearly for:

- message
- Town Hall post
- Town Hall comment
- ride
- favor
- user report

If the current RPC shape is too weak for that, it must be extended.

### Error handling

Admin moderation failures must be visible in the UI, not only stored in local state.

Required:

- alert or banner on RPC failure
- disabled action buttons while request is in flight
- refresh after successful action

---

## Report Resolution Semantics

### Hide

When an admin hides a reported target:

1. Update the content row's moderation fields.
2. Mark the selected report as reviewed with `status = 'action_taken'`.
3. Update `content_hidden = true` on sibling reports for the same target.
4. Resolve all still-pending sibling reports for the same target as `action_taken` so the queue does not remain artificially open.
5. Append a `content_moderation_events` row.
6. Notify the author.

For content that is already auto-hidden, `Hide` converts system hide into reviewed moderator hide:

1. keep the content hidden
2. set `hidden_by` to the acting admin
3. write `hidden_reason`
4. mark the report set as reviewed
5. notify the author with the moderator reason

### Dismiss

When an admin dismisses a report:

1. Leave the content row unchanged.
2. Mark only the selected report as `dismissed`.
3. Append a `content_moderation_events` row with action `dismiss`.

Sibling reports remain independent.

### Restore

When an admin restores content:

1. Clear the content row's hidden fields.
2. Append a `content_moderation_events` row with action `restore`.
3. Do not erase prior report decisions or prior hide events.

Restore does not reopen old dismissed/action-taken reports automatically.

---

## Notification Design

### Admin notifications

Keep the existing admin-facing `content_reported` flow.

Fixes required:

- keep the live SQL and repo migration files in sync
- ensure `NotificationTypeRegistry.swift` includes `content_reported`

### Author notifications

Add a new user-facing notification type:

- `content_hidden`

This notification is sent to the content author when an admin manually hides content.

Payload requirements:

- notification type
- target type
- target id
- moderator reason

Copy:

- title: "Your content was hidden"
- body: concise explanation plus moderator reason

### Auto-hide notifications

Auto-hide at threshold should remain admin-visible.

Do not notify the author on auto-hide in v1 unless a moderator later confirms the hide with a reason. Author notification requires an understandable reason; a threshold-only automated action does not provide that yet.

### Restore notifications

No author notification is required for restore in v1.

---

## Routing and Deep Links

### Admin

Existing `content_reported` routing to admin reports remains valid.

### Author

`content_hidden` should deep link to the affected surface where practical:

- message -> conversation
- Town Hall post/comment -> Town Hall surface
- ride -> ride detail or author request detail
- favor -> favor detail or author request detail

If the content is hidden, the destination shows the author placeholder, not the original content body.

---

## Surface-Specific Implementation Notes

### Messaging

Preserve messaging invariants:

- do not bypass repository/update pipeline
- do not conflate moderated hidden with unsent/deleted
- keep active conversation subscription behavior unchanged

Implementation note:

- extend `Message` and `SDMessage` with hidden moderation fields
- create a dedicated UIKit hidden-message placeholder view rather than reusing `UnsentMessageView`
- ensure realtime payload parsing and repository updates carry moderation fields

### Town Hall

The current `hidden_at IS NULL` client filters conflict with author-placeholder behavior.

Implementation note:

- remove hard client exclusion once server-side visibility rules are in place
- update post/comment cards to render placeholders when `hiddenAt != nil` and `userId == currentUserId`
- fix targeted post fetch so hidden posts do not bypass the moderation model

### Rides and favors

Implementation note:

- extend domain models and decoders with hidden moderation fields
- update list cards and detail views to render author placeholders
- disable actions on hidden requests

### Admin Reports

Implementation note:

- extend `AdminReport` and `admin_get_reports` to include message/ride/favor target identity
- add hide confirmation sheet with required reason
- allow reverse actions after dismissal or prior action

---

## Files Likely Affected

### Database / Supabase

- `supabase/migrations/` new migration for moderation fields, event history, RPC updates, and notification types
- live alignment for existing moderation SQL that currently exists in DB but not fully in repo
- `supabase/functions/_shared/notificationTypes.ts`

### Swift services / models

- `NaarsCars/Core/Services/AdminModerationService.swift`
- `NaarsCars/Core/Services/MessageService.swift`
- `NaarsCars/Core/Services/TownHallService.swift`
- `NaarsCars/Core/Services/TownHallCommentService.swift`
- `NaarsCars/Core/Services/RideService.swift`
- `NaarsCars/Core/Services/FavorService.swift`
- `NaarsCars/Core/Models/Message.swift`
- `NaarsCars/Core/Models/AppNotification.swift`
- `NaarsCars/Core/Models/NotificationTypeRegistry.swift`
- `NaarsCars/Core/Storage/SDModels.swift`
- messaging mappers / repository files that carry message fields through SwiftData

### Swift UI

- `NaarsCars/Features/Admin/Views/AdminReportsView.swift`
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`
- messaging cell/placeholder views
- `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`
- `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`
- ride/favor card and detail views that should render author placeholders

---

## Safety / Invariants

| System | Invariant |
|---|---|
| Moderation source of truth | Content visibility comes from content rows, not only from `reports` |
| Audit trail | Moderation events are append-only |
| Reversibility | Content state can change from visible -> hidden -> visible without losing history |
| Author UX | Only the author sees a hidden placeholder |
| Messaging continuity | Hidden messages use a distinct placeholder and do not break conversation rendering |
| Notification correctness | Admin report notifications and author hidden notifications use distinct types |
| App Store compliance | Reporting, moderation, and abuse-handling remain available and understandable |

---

## Out of Scope

- Full user-account restriction flow (already covered by the admin ban design)
- Moderator tooling beyond hide/dismiss/restore
- Bulk moderation actions
- Appeals workflow
- Author notification on restore

---

## Recommended Verification

Manual verification must cover:

1. Report each target type: message, Town Hall post, Town Hall comment, ride, favor.
2. Admin hides content with a reason.
3. Other users no longer see the content.
4. The author sees the placeholder instead of the original content.
5. The author receives the `content_hidden` notification with the moderator reason.
6. Admin dismisses a visible report and can still later hide the same content.
7. Admin restores hidden content and can later hide it again.
8. Messaging thread reporting works both from the main conversation and thread view.
9. Notification registries validate cleanly across Swift and TypeScript.
10. Existing App Store-sensitive abuse/reporting flows still work.
