# Announcement & Review Rendering Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix town hall posts so announcements show megaphone badges/pinning and reviews show star ratings/subtitles, by correcting the database `type` field and adding client-side pin sorting.

**Architecture:** The iOS UI already handles both post types correctly — the problem is purely that the DB trigger for reviews doesn't set `type = 'review'` and one existing broadcast has stale `type = null`. We fix the trigger, backfill data, add 7-day pin-to-top sorting client-side, and update the review subtitle to include the reviewer's name.

**Tech Stack:** PostgreSQL (Supabase), Swift/SwiftUI

---

### Task 1: Database Migration — Fix Review Trigger and Backfill Data

**Files:**
- Create: `database/123_fix_review_trigger_and_backfill_types.sql`

**Step 1: Write the migration SQL**

Create `database/123_fix_review_trigger_and_backfill_types.sql` with this content:

```sql
-- Fix handle_new_review trigger to set type = 'review', use generic title,
-- and include star emojis in content. Also backfill existing posts.

-- 1. Update the trigger function
CREATE OR REPLACE FUNCTION public.handle_new_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    reviewer_name TEXT;
    fulfiller_name TEXT;
BEGIN
    SELECT name INTO reviewer_name FROM public.profiles WHERE id = NEW.reviewer_id;
    SELECT name INTO fulfiller_name FROM public.profiles WHERE id = NEW.fulfiller_id;

    INSERT INTO public.town_hall_posts (user_id, title, content, review_id, type)
    VALUES (
        NEW.reviewer_id,
        'New Review',
        format('%s %s', repeat('⭐', NEW.rating), COALESCE(NEW.comment, '')),
        NEW.id,
        'review'
    );

    RETURN NEW;
END;
$function$;

-- 2. Backfill review posts that have review_id but null type
UPDATE public.town_hall_posts
SET type = 'review'
WHERE review_id IS NOT NULL AND type IS NULL;

-- 3. Backfill announcement posts (pinned posts without review_id)
UPDATE public.town_hall_posts
SET type = 'announcement'
WHERE pinned = true AND type IS NULL AND review_id IS NULL;
```

**Step 2: Apply the migration to Supabase**

Use the Supabase MCP `apply_migration` tool with name `fix_review_trigger_and_backfill_types` and the SQL from step 1.

**Step 3: Verify the migration**

Run SQL to confirm all posts now have correct types:

```sql
SELECT id, title, type, pinned, review_id
FROM town_hall_posts
WHERE type IS NULL
ORDER BY created_at DESC;
```

Expected: Empty result (no posts with null type remaining, except regular user posts which legitimately have null type — actually those default to `user_post` via the Swift model, so null is fine for them).

Also verify review posts specifically:

```sql
SELECT id, title, type, review_id
FROM town_hall_posts
WHERE review_id IS NOT NULL
ORDER BY created_at DESC;
```

Expected: All rows have `type = 'review'`.

**Step 4: Commit**

```bash
git add database/123_fix_review_trigger_and_backfill_types.sql
git commit -m "fix: update review trigger to set type='review' and backfill existing posts"
```

---

### Task 2: Client — Add Pin-to-Top Sorting in TownHallFeedViewModel

**Files:**
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift`

**Step 1: Add a private sorting method**

Add this method after the existing `mergePosts` method (after line 236 of `TownHallFeedViewModel.swift`):

```swift
/// Sort posts with pinned announcements (< 7 days old) at top
private func sortWithPinnedFirst(_ posts: [TownHallPost]) -> [TownHallPost] {
    let pinWindow = Date().addingTimeInterval(-7 * 24 * 3600)
    return posts.sorted { a, b in
        let aIsPinned = a.pinned == true && a.createdAt > pinWindow
        let bIsPinned = b.pinned == true && b.createdAt > pinWindow
        if aIsPinned != bIsPinned { return aIsPinned }
        return a.createdAt > b.createdAt
    }
}
```

**Step 2: Apply sorting in `mergePosts`**

In the `mergePosts` method (line 230-236), change the return statement from:

```swift
return map.values.sorted { $0.createdAt > $1.createdAt }
```

to:

```swift
return sortWithPinnedFirst(Array(map.values))
```

**Step 3: Apply sorting in `loadPosts`**

In `loadPosts()` (around line 72-76), after `updateVoteCache` and before setting `currentOffset`, change:

```swift
posts = applyVoteCache(to: fetchedPosts)
```

to:

```swift
posts = sortWithPinnedFirst(applyVoteCache(to: fetchedPosts))
```

**Step 4: Apply sorting in `bindPosts` sink**

In `bindPosts()` (line 157-163), change the sink closure from:

```swift
self.posts = self.applyVoteCache(to: posts)
```

to:

```swift
self.posts = self.sortWithPinnedFirst(self.applyVoteCache(to: posts))
```

**Step 5: Build and verify**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds with no errors.

**Step 6: Commit**

```bash
git add NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift
git commit -m "feat: add 7-day pin-to-top sorting for announcements in town hall"
```

---

### Task 3: Client — Update Review Subtitle to Include Reviewer Name

**Files:**
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift:64-77`

**Step 1: Update the `reviewSubtitle` computed property**

In `TownHallPostCard.swift`, replace lines 64-77 (the `reviewSubtitle` computed property) with:

```swift
/// "Brendan reviewed Jane Doe for a ride"
private var reviewSubtitle: String? {
    guard isReview, let review = post.review else { return nil }
    var text = ""
    if let author = post.author {
        text += "\(author.name) reviewed "
    } else {
        text += "Reviewed "
    }
    if let name = review.fulfillerName {
        text += name
    }
    if review.rideId != nil {
        text += " for a ride"
    } else if review.favorId != nil {
        text += " for a favor"
    }
    return text
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds with no errors.

**Step 3: Commit**

```bash
git add NaarsCars/Features/TownHall/Views/TownHallPostCard.swift
git commit -m "feat: include reviewer name in review post subtitle"
```

---

### Task 4: Manual Verification

**Step 1: Verify announcements in town hall**

Open the app, navigate to Town Hall. The "App Submission" broadcast should now show:
- Megaphone icon + "Announcement" pill badge in naarsPrimary color
- Blue highlighted border around the card
- Pin icon next to the timestamp
- Post pinned to the top of the feed (if < 7 days old)

**Step 2: Verify reviews in town hall**

The review posts should now show:
- "Review" pill badge in orange
- 5 visual stars (filled/empty based on rating)
- Italic subtitle: "Brendan reviewed CTO for a ride"
- Star emojis in the post content body (for newly created reviews; existing reviews keep their original content)

**Step 3: Final commit with all changes**

If any build issues were found and fixed, commit those fixes.
