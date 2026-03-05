# Content Moderation System Design

**Date:** 2026-03-04
**Status:** Approved

## Problem

Apple App Store Guideline 1.2 (User-Generated Content) requires apps with UGC to have:
1. A mechanism for users to report objectionable content
2. A mechanism to block abusive users
3. The ability for the developer to act on reports (remove content)

The app has report submission UI and user blocking, but reports don't link to posts/comments, there's no admin moderation queue, no auto-hide safety net, and no way to remove content.

## Approach

Database-driven moderation: add `hidden_at`/`hidden_by` columns to content tables, a DB trigger for auto-hide at 3+ reports, admin notifications on every report, and an admin reports queue in the existing admin panel.

## Design

### 1. Database Changes

**`reports` table — extend for posts/comments:**
- Add `reported_post_id UUID REFERENCES town_hall_posts(id)`
- Add `reported_comment_id UUID REFERENCES town_hall_comments(id)`
- Update constraint: at least one of `reported_user_id`, `reported_message_id`, `reported_post_id`, or `reported_comment_id` must be set
- Add RLS policy: admins can read all reports
- Update `submit_report()` RPC to accept `p_reported_post_id` and `p_reported_comment_id`

**`town_hall_posts` — add moderation columns:**
- `hidden_at TIMESTAMPTZ DEFAULT NULL` — null = visible, non-null = hidden
- `hidden_by UUID REFERENCES profiles(id)` — admin who hid it, null = auto-hidden by system

**`town_hall_comments` — same columns:**
- `hidden_at TIMESTAMPTZ DEFAULT NULL`
- `hidden_by UUID REFERENCES profiles(id)`

**Auto-hide trigger (`check_report_threshold`):**
- Fires after INSERT on `reports`
- Counts distinct reporters for the reported post/comment
- If count >= 3 and content not already hidden, sets `hidden_at = NOW()`, `hidden_by = NULL`

**Admin notification trigger:**
- On every report INSERT, create a notification for all admin users
- Type: `content_reported`
- Title: "Content Reported"
- Body: includes report type and content preview (truncated)

### 2. Feed Filtering

- Town Hall post queries add `WHERE hidden_at IS NULL` for regular users
- Comment queries add same filter
- The author of hidden content sees their post with a "This content has been removed by moderators" message replacing the content
- Admins see all content in the admin reports queue (not in the regular feed)

### 3. Admin Reports Queue (AdminPanelView)

New "Reports" section in the admin panel:

- **Report list** showing: content preview, reporter name, report type badge (spam/harassment/inappropriate/scam/other), timestamp, report count if multiple reports on same content
- **Filter tabs**: All | Pending | Resolved
- **Auto-hidden badge** on content the system auto-hid at threshold
- **Actions per item:**
  - **Hide** — sets `hidden_at` on the post/comment, marks report `action_taken`
  - **Restore** — clears `hidden_at` (for false positives), marks report `dismissed`
  - **Dismiss** — marks report `dismissed`, content stays visible (report was unfounded)

Admin actions call server-side RPC functions that verify admin status before executing.

### 4. Reporter UX

- After submitting a report: brief "Report submitted" confirmation toast
- Flag button changes to "Reported" (grayed out, disabled) for content the user already reported
- Track reported content IDs in-session to avoid re-querying

### 5. Notification Flow

```
User reports content
    → Report inserted in DB
    → Trigger: notify all admins (content_reported notification)
    → Admin sees notification, can act immediately
    → If admin doesn't act and 3+ unique reporters accumulate:
        → Auto-hide trigger fires
        → Content hidden from feed
        → Admin notification: "Content auto-hidden"
```

## Files Affected

### Database (Supabase migrations)
- New migration: extend reports table, add hidden columns, create triggers, update RPC

### Swift (client)
- `AdminPanelView.swift` — add Reports section
- New: `AdminReportsView.swift` — reports queue list
- New: `AdminReportDetailView.swift` — report detail with actions
- New: `AdminModerationService.swift` — RPC calls for admin actions
- `TownHallService.swift` — update queries to filter hidden content
- `TownHallPostCard.swift` — show "Reported" state on flag button, show hidden message for authors
- `PostCommentsView.swift` — same for comments
- `ReportContentSheet.swift` — add success toast on dismiss
- `MessageService.swift` — ensure reportPost/reportComment pass correct params
- `NotificationType.swift` — add `content_reported` type
