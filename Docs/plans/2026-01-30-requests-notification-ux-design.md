# Requests Notification UX Design
Date: 2026-01-30  
Status: Draft  
Owner: Requests/Notifications

## Goals
- Make request notifications discoverable from the Requests tab.
- Add numeric badges on filter tiles and request cards for unseen activity.
- Auto-scroll and highlight the relevant detail anchor when opening a request with unseen notifications.
- Keep existing request badge semantics on the main tab (Model A).

## Non-Goals
- No backend/RPC changes for badge counts or notification payloads.
- No changes to notification clearing rules (review requests still clear only on submit/skip).
- No redesign of the bell feed or notification grouping model.

## UX Summary
The Requests tab shows numeric badges on the filter tiles (Open/Mine/Claimed) that reflect the total number of unseen notifications within that filter. Each request card displays a numeric badge for unseen notifications on that specific request. When a user opens a request with unseen notifications, the detail view auto-scrolls and highlights the anchor associated with the most recent unread notification type.

## Interaction Details
- Filter tile badges appear only when count > 0 and are capped for readability.
- Request card badges display the total unseen notification count for that request.
- Card tap with unseen notifications sets a request navigation target before navigation.
- Anchor selection uses the most recent unread notification type for the request.
- List auto-scroll occurs only when arriving via a notification deep link.

## Data Flow
1) `NotificationService.fetchNotifications()` returns bell notifications for the user.
2) The Requests dashboard aggregates unread notifications by request key:
   - `requestKey = ride:{id}` or `favor:{id}`
   - `unreadCount`, `latestUnreadType`, `latestUnreadAt`
3) Filter tile badges sum unread counts for requests matching the active filter.
4) Card badges read from the per-request summary map.
5) On card tap, if summary exists, build `RequestNotificationTarget` using
   `RequestNotificationMapping.target(for:latestType, rideId, favorId)`.

## UI Components
- **FilterTile**: add a badge capsule for unseen counts.
- **RideCard/FavorCard**: replace dot indicator with numeric badge.
- **RequestsDashboardView**: wrap list in `ScrollViewReader` for optional
  deep-link auto-scroll and apply temporary highlight when applicable.

## Error Handling
- If notification fetch fails, badges hide and list remains functional.
- Notifications missing request IDs are ignored for badges/anchors.
- If a notification type has no anchor mapping, fall back to `.mainTop`.

## Testing
- Manual QA only (unit tests skipped per user request).
- Verify filter badges reflect unseen counts for each filter.
- Verify card badges reflect per-request unseen counts.
- Verify anchor auto-scroll/highlight on card open with unseen notifications.
- Verify review notifications do not auto-clear on navigation.

## Accessibility
- Badge views include accessibility labels describing the count.
