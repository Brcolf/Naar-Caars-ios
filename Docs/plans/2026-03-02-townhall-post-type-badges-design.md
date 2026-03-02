# Town Hall Post Type Visual Treatment Design

**Date:** 2026-03-02

## Summary

Enrich town hall post cards with visual indicators for announcements and reviews so they're distinguishable from regular user posts.

## Announcement Posts

- Add `announcement` case to `PostType` enum
- Update `send_broadcast_notifications` RPC to set `type = 'announcement'` on the town hall post
- Card rendering:
  - Pill badge: megaphone icon + "Announcement" in naarsPrimary, below the title
  - Accent-colored border on the card (naarsPrimary)
  - Pin icon next to timestamp if `post.pinned == true`

## Review Posts

- Replace number-in-pill with visual filled/empty star icons (5 stars, filled to rating)
- Add "Review" pill badge (star icon + text) below title
- Add "Reviewed **Name**" subtitle below author row with fulfiller's profile name
- Append "for a ride" or "for a favor" based on review's rideId/favorId
- Join fulfiller profile name during TownHallService enrichment

## Files to Change

- `TownHallPost.swift` — add `.announcement` PostType case
- `Review.swift` — add optional `fulfillerName: String?` joined field
- `TownHallPostCard.swift` — type badges, visual stars, fulfiller subtitle, announcement styling
- `TownHallService.swift` — enrich reviews with fulfiller profile name
- `send_broadcast_notifications` RPC (database/041) — set type on town hall post
