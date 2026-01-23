# Request-Scoped Clearing & Badges (Model A) (Epic)
- PRD: Request Badge §§7–9; AC-REQ-1..8
- Scope: badge model A, per-card dot, recipient-scoped mark-read, section anchors, review exception

## Tasks
1) Badge = number of requests with unseen activity; per-card dot indicator  
   - Why: §§7.1/7.2 (Model A), AC-REQ-1/4  
   - Files: `BadgeCountManager.calculateRequestsBadgeCount`; Requests dashboard/list views  
   - DB: counts query updated to distinct request IDs  
   - Realtime: optional request-notification insert subscription for fast-path updates  
   - Anchors: badge display (per-card indicators rely on same state)  
   - ACs: AC-REQ-1, AC-REQ-4  
   - QA: Two requests unseen → badge=2 even if multiple events on one; dots align with badge.

2) Recipient-scoped mark-read for request notifications (RLS user_id = auth.uid())  
   - Why: R-CLEAR-REQ-1/2/3, RLS guidance, AC-REQ-1/2/5  
   - Files: `NotificationService` new `markRequestScopedRead(ride_id|favor_id)`; `RideDetailView`; `FavorDetailView`  
   - DB: new RPC/SQL to mark read where `user_id = auth.uid()` and `ride_id`/`favor_id` matches; RLS: SELECT/UPDATE only for `user_id = auth.uid()`; inserts via definer/service role  
   - Realtime: optional notification update push  
   - Anchors: `requests.rideDetail.mainTop`, `requests.favorDetail.mainTop`  
   - ACs: AC-REQ-1, AC-REQ-2, AC-REQ-5  
   - QA: Opening detail clears only current user’s notifications for that request; safe to repeat; other users unaffected.

3) Section-specific deep links and highlight (Q&A, unclaim, completion, etc.)  
   - Why: R-SEEN-REQ-1..3, R-HIGHLIGHT-1..3, table §9.2, AC-REQ-6/7  
   - Files: deep-link router; `RideDetailView`/`FavorDetailView` scroll/anchor + highlight logic  
   - DB: ensure notification rows carry `ride_id`/`favor_id`  
   - Realtime: none  
   - Anchors: `requests.rideDetail.qaSection`, `requests.rideDetail.statusBadge`, `requests.rideDetail.completeSheet`, `requests.favorDetail.qaSection`, `requests.favorDetail.statusBadge`, `requests.favorDetail.completeSheet`, etc.  
   - ACs: AC-REQ-6, AC-REQ-7  
   - QA: Q&A notification lands on Q&A section and marks read after section reached; unclaim lands on status/claim action; highlight persists ~10s.

4) Review notification exception (no auto-clear on navigation)  
   - Why: R-READ-5, §7.6, AC-REQ-8  
   - Files: `NotificationService.markReviewRequestAsRead` generalization; review flow screens  
   - DB: ensure review notifications excluded from auto-clear RPC; read only on submit/skip  
   - Realtime: none  
   - Anchors: `requests.rideDetail.reviewSheet`, `requests.favorDetail.reviewSheet`  
   - ACs: AC-REQ-8  
   - QA: Navigating to review UI keeps notification unread; submit/skip clears.


