# Badge Avatars Everywhere Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show badge emoji rings on all 40pt+ avatars across the app using a shared BadgeCache, and add a new Frequent Carbardian badge.

**Architecture:** A `BadgeCache` singleton (`@Observable`) stores `[UUID: [LeaderboardBadge]]` with 1-hour TTL, populated as a side effect of existing leaderboard and profile fetches. `AvatarView` gains an optional `userId` parameter and auto-reads from the cache when size >= 40. A new `frequentCarbardian` badge is added for 10+ requests.

**Tech Stack:** Swift/SwiftUI, PostgreSQL (plpgsql), Supabase MCP

---

### Task 1: Add Frequent Carbardian badge to LeaderboardBadge enum

**Files:**
- Modify: `NaarsCars/Core/Models/LeaderboardBadge.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift`

**Step 1: Add the new case to the enum**

In `LeaderboardBadge.swift`, add after line 16 (`case bigSaver = "big_saver"`):

```swift
case frequentCarbardian = "frequent_carbardian"
```

**Step 2: Add to all computed properties**

In `displayName` switch, add after the `.bigSaver` case:
```swift
case .frequentCarbardian: return "Frequent Carbardian"
```

In `iconName` switch, add after the `.bigSaver` case:
```swift
case .frequentCarbardian: return "car.2.fill"
```

In `emoji` switch, add after the `.bigSaver` case:
```swift
case .frequentCarbardian: return "🚙"
```

In `badgeDescription` switch, add after the `.bigSaver` case:
```swift
case .frequentCarbardian: return "badge_frequent_carbardian_desc".localized
```

**Step 3: Add localization string**

In `NaarsCars/Resources/Localizable.xcstrings`, insert after the `badge_five_star_desc` block (after line 4910), before `badge_good_neighbor_desc`:

```json
    "badge_frequent_carbardian_desc" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Requested 10+ rides and favors"
          }
        }
      }
    },
```

**Step 4: Update test for decoding**

In `LeaderboardBadgeTests.swift`, add a test:

```swift
func testDecodingFrequentCarbardian() throws {
    let json = "\"frequent_carbardian\"".data(using: .utf8)!
    let badge = try JSONDecoder().decode(LeaderboardBadge.self, from: json)
    XCTAssertEqual(badge, .frequentCarbardian)
}
```

**Step 5: Commit**

```bash
git add NaarsCars/Core/Models/LeaderboardBadge.swift NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add Frequent Carbardian badge for 10+ requests"
```

---

### Task 2: Add Frequent Carbardian to database functions

**Files:**
- Create: `database/126_add_frequent_carbardian_badge.sql`

**Step 1: Write migration that updates both badge functions**

The migration must update `get_user_badges` to add a request count check, and update `get_xp_leaderboard` to include the new badge in its assembly.

For `get_user_badges`: Add a variable `v_requests_made` that counts total rides + favors created by the user (all-time). Add `SELECT 'frequent_carbardian' AS badge WHERE v_requests_made >= 10` to the badge assembly.

For `get_xp_leaderboard`: The deployed version uses `xp_events` table. Add a correlated subquery for `requests_made_cnt` in `user_stats` that counts `source_type IN ('ride_requested', 'favor_requested')`. Add `SELECT 'frequent_carbardian' WHERE us.requests_made_cnt >= 10` to the badge assembly.

**Important:** Read the deployed function source from `pg_proc` via `mcp__supabase__execute_sql` before writing the migration, to ensure you're working with the actual live code (which uses `xp_events`), not the migration file on disk.

**Step 2: Apply via Supabase MCP**

Use `mcp__supabase__apply_migration` with name `add_frequent_carbardian_badge`.

**Step 3: Verify**

Run via `mcp__supabase__execute_sql`:
```sql
-- Check Brendan who has 38 requests — should now have frequent_carbardian
SELECT * FROM get_user_badges('0da568d8-924c-4420-8853-206a48d277b6');

-- Also check leaderboard
SELECT user_id, name, badges FROM get_xp_leaderboard('1970-01-01', CURRENT_DATE)
WHERE user_id = '0da568d8-924c-4420-8853-206a48d277b6';
```

Expected: Both return `["frequent_carbardian"]` for Brendan.

**Step 4: Commit**

```bash
git add database/126_add_frequent_carbardian_badge.sql
git commit -m "feat: add frequent_carbardian badge to DB functions"
```

---

### Task 3: Create BadgeCache singleton

**Files:**
- Create: `NaarsCars/Core/Services/BadgeCache.swift`

**Step 1: Implement BadgeCache**

```swift
//
//  BadgeCache.swift
//  NaarsCars
//
//  In-memory cache for user badge data
//

import Foundation
import Observation

/// In-memory cache for user badge data, populated by existing fetches
@Observable
@MainActor
final class BadgeCache {
    static let shared = BadgeCache()

    private var cache: [UUID: (badges: [LeaderboardBadge], cachedAt: Date)] = [:]
    private let ttl: TimeInterval = 3600 // 1 hour

    private init() {}

    /// Get cached badges for a user. Returns empty array on miss or expiry.
    func badges(for userId: UUID) -> [LeaderboardBadge] {
        guard let entry = cache[userId],
              Date().timeIntervalSince(entry.cachedAt) < ttl else {
            return []
        }
        return entry.badges
    }

    /// Store badges for a single user
    func store(badges: [LeaderboardBadge], for userId: UUID) {
        cache[userId] = (badges, Date())
    }

    /// Bulk populate from leaderboard entries
    func storeBatch(entries: [LeaderboardEntry]) {
        let now = Date()
        for entry in entries {
            cache[entry.userId] = (entry.badges, now)
        }
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/BadgeCache.swift
git commit -m "feat: add BadgeCache singleton for shared badge data"
```

---

### Task 4: Populate BadgeCache from existing fetches

**Files:**
- Modify: `NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift`
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift`
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift`

**Step 1: Populate from leaderboard fetch**

In `LeaderboardViewModel.swift`, in the `fetchFresh` method, after `entries = freshEntries` (around line 76), add:

```swift
BadgeCache.shared.storeBatch(entries: freshEntries)
```

**Step 2: Populate from profile badge fetches**

In `PublicProfileView.swift`, where badges are fetched (in the `.task` block), after `badges = (try? await badgesTask) ?? []`, add:

```swift
BadgeCache.shared.store(badges: badges, for: userId)
```

In `MyProfileView.swift`, same pattern — after badges are fetched, add:

```swift
if let userId = userId {
    BadgeCache.shared.store(badges: badges, for: userId)
}
```

**Step 3: Commit**

```bash
git add NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift NaarsCars/Features/Profile/Views/PublicProfileView.swift NaarsCars/Features/Profile/Views/MyProfileView.swift
git commit -m "feat: populate BadgeCache from leaderboard and profile fetches"
```

---

### Task 5: Add userId parameter to AvatarView

**Files:**
- Modify: `NaarsCars/UI/Components/Common/AvatarView.swift`

**Step 1: Add userId property and cache lookup**

Add a new property after line 15 (`var badges: [LeaderboardBadge] = []`):

```swift
var userId: UUID? = nil
```

Add a computed property that resolves badges — explicit parameter takes priority, then cache lookup (only at 40pt+):

```swift
private var resolvedBadges: [LeaderboardBadge] {
    if !badges.isEmpty { return badges }
    guard let userId = userId, size >= 40 else { return [] }
    return BadgeCache.shared.badges(for: userId)
}
```

**Step 2: Replace all `badges` references in the body with `resolvedBadges`**

In `body`, change:
- `let displayBadges = Array(badges.prefix(3))` → `let displayBadges = Array(resolvedBadges.prefix(3))`
- `badges.isEmpty ? size : size + badgeContainerSize` → `resolvedBadges.isEmpty ? size : size + badgeContainerSize` (both width and height)

In `badgeAngles`, change:
- `let displayBadges = Array(badges.prefix(3))` → `let displayBadges = Array(resolvedBadges.prefix(3))`

**Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Common/AvatarView.swift
git commit -m "feat: AvatarView auto-reads badges from cache via userId"
```

---

### Task 6: Add userId to UserAvatarLink

**Files:**
- Modify: `NaarsCars/UI/Components/Common/UserAvatarLink.swift`

**Step 1: Pass userId through to AvatarView**

Change the AvatarView call in `UserAvatarLink` (line 17-21) to include userId:

```swift
AvatarView(
    imageUrl: profile.avatarUrl,
    name: profile.name,
    size: size,
    userId: profile.id
)
```

This automatically enables badge rings on all UserAvatarLink usages (RideCard, FavorCard).

**Step 2: Commit**

```bash
git add NaarsCars/UI/Components/Common/UserAvatarLink.swift
git commit -m "feat: UserAvatarLink passes userId for badge display"
```

---

### Task 7: Add userId to remaining 40pt+ AvatarView call sites

**Files:**
- Modify: `NaarsCars/UI/Components/Cards/ReviewCard.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationAvatar.swift`
- Modify: `NaarsCars/Features/Admin/Views/PendingUsersView.swift`
- Modify: `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift`
- Modify: `NaarsCars/Features/Admin/Views/UserManagementView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
- Modify: `NaarsCars/UI/Components/Messaging/UserSearchView.swift` (50pt call only, skip 32pt)
- Modify: `NaarsCars/Features/Profile/Views/EditProfileView.swift`
- Modify: `NaarsCars/Features/Profile/Views/SettingsView.swift`

**Step 1: Add `userId` to each call site**

For each file, find the AvatarView call that is 40pt+ and add the `userId` parameter. The exact parameter depends on what user data is available in scope at each call site. Read each file to determine the correct userId source.

Examples:
- `ConversationAvatar.swift` line 18: `AvatarView(imageUrl: participant.avatarUrl, name: participant.name, size: 50, userId: participant.id)`
- `PendingUsersView.swift` line 114: add `userId: user.id`
- `ReviewCard.swift`: add `userId: reviewerId` (check if ReviewCard has a reviewer UUID prop — if not, add one)
- `EditProfileView.swift`: add `userId: viewModel.userId` or similar

**Important:** Read each file before editing to find the correct userId source. Do NOT add userId to calls below 40pt (ConversationDetailView 32pt/26pt, UserSearchView 32pt, ConversationsListView toast 36pt, SpotlightCard 36pt, town hall 24pt, message bubbles 28pt, typing indicators 28pt).

**Step 2: Commit**

```bash
git add -A
git commit -m "feat: add userId to all 40pt+ AvatarView call sites"
```

---

### Task 8: Update LeaderboardServiceTests

**Files:**
- Modify: `NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift`

**Step 1: Update testFetchSpotlights valid categories**

The test already accepts 3 categories from our earlier work. No changes needed there.

**Step 2: Add test for badge consistency**

Add a new test that verifies the leaderboard and profile badge functions agree:

```swift
/// Test that leaderboard badges and user badges are consistent
func testBadgeConsistency() async throws {
    do {
        let entries = try await leaderboardService.fetchLeaderboard(period: .allTime)
        guard let firstEntry = entries.first else {
            XCTSkip("No leaderboard entries to test")
            return
        }
        let userBadges = try await leaderboardService.fetchUserBadges(userId: firstEntry.userId)
        // All-time leaderboard badges should be subset of all-time user badges
        // (user badges are always all-time, leaderboard can be filtered)
        for badge in firstEntry.badges {
            XCTAssertTrue(userBadges.contains(badge),
                          "Leaderboard badge \(badge.rawValue) not found in user badges")
        }
    } catch {
        XCTFail("Badge consistency test failed: \(error.localizedDescription)")
    }
}
```

**Step 3: Commit**

```bash
git add NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift
git commit -m "test: add badge consistency test between leaderboard and profile"
```
