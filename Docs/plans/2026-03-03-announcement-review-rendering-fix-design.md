# Announcement & Review Town Hall Rendering Fix

**Date:** 2026-03-03

## Problem

Announcement posts in town hall look like regular posts — no megaphone badge, no highlighted border, pin icon doesn't float to top. Review posts don't show star ratings, review subtitle, or "Review" badge.

**Root cause:** The database isn't setting `type` correctly on town hall posts. The iOS UI already handles both types with proper badges, stars, borders — but only when `post.type` is set. With `type = null`, the Swift model defaults to `.userPost` and renders as a plain post.

## Design

### 1. Database: Fix `handle_new_review` Trigger

Update the INSERT to include `type = 'review'`, a generic title, and star emojis in content:

```sql
INSERT INTO public.town_hall_posts (user_id, title, content, review_id, type)
VALUES (
    NEW.reviewer_id,
    'New Review',
    format('%s %s', repeat('⭐', NEW.rating), COALESCE(NEW.comment, '')),
    NEW.id,
    'review'
);
```

- **Title**: Generic "New Review" — the card subtitle handles the "who reviewed whom" context
- **Content**: Star emojis followed by the reviewer's comment
- **Type**: Explicitly set to `'review'`

### 2. Database: Backfill Existing Posts

Single migration to fix stale data:

- `UPDATE town_hall_posts SET type = 'review' WHERE review_id IS NOT NULL AND type IS NULL`
- `UPDATE town_hall_posts SET type = 'announcement' WHERE pinned = true AND type IS NULL AND review_id IS NULL`

The `send_broadcast_notifications` RPC already sets `type = 'announcement'` — no changes needed there.

### 3. Client: Pin-to-Top Sorting (7-Day Window)

In `TownHallFeedViewModel`, after fetching posts, sort so pinned posts < 7 days old float to the top:

```swift
posts.sort { a, b in
    let aIsPinned = a.pinned == true && a.createdAt > Date().addingTimeInterval(-7 * 24 * 3600)
    let bIsPinned = b.pinned == true && b.createdAt > Date().addingTimeInterval(-7 * 24 * 3600)
    if aIsPinned != bIsPinned { return aIsPinned }
    return a.createdAt > b.createdAt
}
```

After 7 days, pinned posts sort normally by date. Client-side sorting is sufficient for this small community feed.

### 4. Client: Review Subtitle Update

Update `TownHallPostCard.reviewSubtitle` to include the reviewer's name (from `post.author`) since the title is now generic:

```swift
var text = ""
if let author = post.author { text += "\(author.name) reviewed " }
if let name = review.fulfillerName { text += name }
if review.rideId != nil { text += " for a ride" }
else if review.favorId != nil { text += " for a favor" }
```

## Files to Change

| File | Change |
|------|--------|
| Database migration (new) | Update `handle_new_review` trigger + backfill existing posts |
| `TownHallFeedViewModel.swift` | Add pin-to-top sorting after fetch |
| `TownHallPostCard.swift` | Update `reviewSubtitle` to include author name |

## What Already Works (No Changes Needed)

- Megaphone badge + "Announcement" pill for `type == .announcement`
- "Review" pill badge for `type == .review`
- Visual 5-star rating display from `post.review.rating`
- Highlighted blue border for announcements
- Pin icon next to timestamp for `pinned == true`
- Review data enrichment in `TownHallService.fetchReviews()`
- `send_broadcast_notifications` RPC (already sets `type = 'announcement'`)
