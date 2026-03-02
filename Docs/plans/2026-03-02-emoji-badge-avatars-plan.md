# Emoji Badge Avatars Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace text-label badge pills with emoji badges that overlay the user's avatar, and add a badges section to profile pages.

**Architecture:** Add an optional `badges` parameter to the existing `AvatarView` component. Emoji badges are positioned in a ring around the avatar using `GeometryReader` and angle-based positioning. A new lightweight `get_user_badges` RPC provides badge data for profile pages. Badge pills are removed from `LeaderboardRow`.

**Tech Stack:** SwiftUI (AvatarView overlay), PostgreSQL (Supabase RPC), existing `LeaderboardBadge` enum.

---

### Task 1: Add `emoji` property to `LeaderboardBadge`

**Files:**
- Modify: `NaarsCars/Core/Models/LeaderboardBadge.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift`

**Step 1: Add test**

Add to `LeaderboardBadgeTests.swift`:

```swift
func testAllBadgesHaveEmoji() {
    for badge in LeaderboardBadge.allCases {
        XCTAssertFalse(badge.emoji.isEmpty)
    }
}
```

**Step 2: Add `emoji` computed property**

Add to `LeaderboardBadge` after the `iconName` property:

```swift
var emoji: String {
    switch self {
    case .roadWarrior: return "🚗"
    case .goodNeighbor: return "🤝"
    case .streakChampion: return "🔥"
    case .fiveStar: return "⭐"
    case .bigSaver: return "💰"
    }
}
```

Also add a `description` property for the profile badge section:

```swift
var badgeDescription: String {
    switch self {
    case .roadWarrior: return "badge_road_warrior_desc".localized
    case .goodNeighbor: return "badge_good_neighbor_desc".localized
    case .streakChampion: return "badge_streak_champ_desc".localized
    case .fiveStar: return "badge_five_star_desc".localized
    case .bigSaver: return "badge_big_saver_desc".localized
    }
}
```

**Step 3: Add localization keys**

Add to `NaarsCars/Resources/Localizable.xcstrings` after existing leaderboard keys:

- `badge_road_warrior_desc` → "Fulfilled 10+ rides"
- `badge_good_neighbor_desc` → "Fulfilled 10+ favors"
- `badge_streak_champ_desc` → "3+ week streak"
- `badge_five_star_desc` → "Received 10+ five-star reviews"
- `badge_big_saver_desc` → "Helped save $250+"
- `badge_section_title` → "Badges"

**Step 4: Commit**

```bash
git add NaarsCars/Core/Models/LeaderboardBadge.swift NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add emoji and description properties to LeaderboardBadge"
```

---

### Task 2: Create `get_user_badges` Supabase RPC function

**Files:**
- Create: `database/122_create_user_badges_function.sql`

**Context:** Profile pages need badge data for a single user. The existing `get_xp_leaderboard` computes badges for all users (expensive). This lightweight function computes badges for one user using all-time data.

**Step 1: Write the SQL**

```sql
-- 122_create_user_badges_function.sql
-- Lightweight function to get badges for a single user (all-time)

DROP FUNCTION IF EXISTS get_user_badges(UUID);

CREATE OR REPLACE FUNCTION get_user_badges(
    target_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    result JSONB;
    rides_cnt BIGINT;
    favors_cnt BIGINT;
    streak_wks BIGINT;
    five_star_cnt BIGINT;
    savings NUMERIC;
BEGIN
    -- Count fulfilled rides (all time)
    SELECT COUNT(*) INTO rides_cnt
    FROM rides
    WHERE claimed_by = target_user_id AND status = 'completed';

    -- Count fulfilled favors (all time)
    SELECT COUNT(*) INTO favors_cnt
    FROM favors
    WHERE claimed_by = target_user_id AND status = 'completed';

    -- Streak (all time, same gaps-and-islands as get_xp_leaderboard)
    WITH fulfilled_weeks AS (
        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE claimed_by = target_user_id AND status = 'completed'
        UNION
        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE claimed_by = target_user_id AND status = 'completed'
    ),
    week_numbered AS (
        SELECT week_start,
            ROW_NUMBER() OVER (ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY (week_start - (rn * INTERVAL '7 days'))
    )
    SELECT COALESCE(MAX(streak_len), 0) INTO streak_wks FROM streaks;

    -- Five-star reviews received
    SELECT COUNT(*) INTO five_star_cnt
    FROM reviews
    WHERE fulfiller_id = target_user_id AND rating = 5;

    -- Total savings from fulfilled rides
    SELECT COALESCE(SUM(estimated_cost), 0) INTO savings
    FROM rides
    WHERE claimed_by = target_user_id AND status = 'completed';

    -- Build badges array
    SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb) INTO result
    FROM (
        SELECT 'road_warrior'    AS badge WHERE rides_cnt >= 10
        UNION ALL
        SELECT 'good_neighbor'   WHERE favors_cnt >= 10
        UNION ALL
        SELECT 'streak_champion' WHERE streak_wks >= 3
        UNION ALL
        SELECT 'five_star'       WHERE five_star_cnt >= 10
        UNION ALL
        SELECT 'big_saver'       WHERE savings >= 250
    ) b;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO authenticated;
```

**Step 2: Apply migration via Supabase MCP**

Use `mcp__supabase__apply_migration` with name `create_user_badges_function`.

**Step 3: Verify**

Run via `mcp__supabase__execute_sql`: `SELECT get_user_badges('1f4097cb-2ae7-428c-909b-417e25e8c5c7');`
Expected: A JSONB array of badge strings.

**Step 4: Commit**

```bash
git add database/122_create_user_badges_function.sql
git commit -m "feat(db): add get_user_badges RPC for single-user badge lookup"
```

---

### Task 3: Modify `AvatarView` to support badge overlays

**Files:**
- Modify: `NaarsCars/UI/Components/Common/AvatarView.swift`

**Context:**
- Current `AvatarView` takes `imageUrl: String?`, `name: String`, `size: CGFloat`
- Add optional `badges: [LeaderboardBadge]` parameter (default `[]`)
- Position up to 3 emoji around the lower half of the avatar in a ring
- Each emoji sits in a small white circle for visibility
- Emoji size = ~30% of avatar diameter
- The existing 23+ call sites remain unchanged (badges defaults to `[]`)

**Step 1: Update AvatarView**

Replace the entire file with:

```swift
//
//  AvatarView.swift
//  NaarsCars
//
//  User avatar with AsyncImage, initials fallback, and optional badge overlay
//

import SwiftUI

/// Avatar view with image loading, initials fallback, and optional badge emoji overlay
struct AvatarView: View {
    let imageUrl: String?
    let name: String
    var size: CGFloat = 50
    var badges: [LeaderboardBadge] = []

    /// Max badges to display around avatar
    private let maxBadges = 3

    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2))
        }
        return "??"
    }

    /// Angles (in degrees) for badge positions based on count
    /// Positioned around the lower half of the avatar
    private var badgeAngles: [Double] {
        let displayBadges = min(badges.count, maxBadges)
        switch displayBadges {
        case 1: return [180]          // 6 o'clock
        case 2: return [150, 210]     // 5 o'clock, 7 o'clock
        case 3: return [120, 180, 240] // 4 o'clock, 6 o'clock, 8 o'clock
        default: return []
        }
    }

    private var emojiSize: CGFloat { size * 0.3 }
    private var badgeContainerSize: CGFloat { emojiSize + 4 }

    var body: some View {
        ZStack {
            // Base avatar
            Group {
                if let imageUrl = imageUrl, !imageUrl.isEmpty {
                    CachedAsyncImage(
                        url: URL(string: imageUrl),
                        placeholder: { ProgressView() },
                        errorView: { initialsView }
                    )
                    .aspectRatio(contentMode: .fill)
                } else {
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            // Badge overlays
            ForEach(Array(badges.prefix(maxBadges).enumerated()), id: \.offset) { index, badge in
                let angle = badgeAngles[index]
                let radians = angle * .pi / 180
                let radius = size / 2
                let xOffset = cos(radians) * radius
                let yOffset = sin(radians) * radius

                Text(badge.emoji)
                    .font(.system(size: emojiSize))
                    .frame(width: badgeContainerSize, height: badgeContainerSize)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(width: size + badgeContainerSize, height: size + badgeContainerSize)
        .accessibilityLabel("Avatar for \(name)")
    }

    private var initialsView: some View {
        Text(initials.uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.naarsPrimary)
            .clipShape(Circle())
    }
}

#Preview {
    VStack(spacing: 30) {
        AvatarView(imageUrl: nil, name: "John Doe", size: 80,
                   badges: [.roadWarrior])
        AvatarView(imageUrl: nil, name: "Jane Smith", size: 80,
                   badges: [.roadWarrior, .fiveStar])
        AvatarView(imageUrl: nil, name: "Bob J", size: 80,
                   badges: [.roadWarrior, .streakChampion, .bigSaver])
        AvatarView(imageUrl: nil, name: "No Badges", size: 80)
    }
    .padding()
}
```

**Important note on frame size:** The outer frame is `size + badgeContainerSize` to accommodate badges that extend beyond the avatar circle. When `badges` is empty, `badgeContainerSize` is still calculated but no badges render — the extra frame space is minimal (~4pt padding). If this causes layout issues at existing call sites, wrap the badge logic in a conditional so the frame only expands when badges are present:

```swift
.frame(
    width: badges.isEmpty ? size : size + badgeContainerSize,
    height: badges.isEmpty ? size : size + badgeContainerSize
)
```

**Step 2: Build and verify existing call sites aren't broken**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Common/AvatarView.swift
git commit -m "feat: add badge emoji overlay support to AvatarView"
```

---

### Task 4: Update `LeaderboardRow` — remove pills, pass badges to avatar

**Files:**
- Modify: `NaarsCars/Features/Leaderboards/Views/LeaderboardRow.swift`

**Step 1: Pass badges to AvatarView**

Replace the AvatarView call (lines 20-24):

```swift
AvatarView(
    imageUrl: entry.avatarUrl,
    name: entry.name,
    size: 44
)
```

With:

```swift
AvatarView(
    imageUrl: entry.avatarUrl,
    name: entry.name,
    size: 44,
    badges: entry.badges
)
```

**Step 2: Remove badge pill HStack**

Replace the name + badges VStack (lines 27-44):

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(entry.name)
        .font(.naarsHeadline)
        .foregroundColor(.primary)

    if !entry.topBadges.isEmpty {
        HStack(spacing: 6) {
            ForEach(entry.topBadges, id: \.self) { badge in
                Label(badge.displayName, systemImage: badge.iconName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.naarsPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.naarsPrimary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
}
```

With just the name:

```swift
Text(entry.name)
    .font(.naarsHeadline)
    .foregroundColor(.primary)
```

**Step 3: Update preview to include badges**

Already done from previous work — previews pass `badges:` to `LeaderboardEntry`.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Leaderboards/Views/LeaderboardRow.swift
git commit -m "feat: move badges from text pills to avatar overlay on LeaderboardRow"
```

---

### Task 5: Add badge fetching to profile service

**Files:**
- Modify: `NaarsCars/Core/Services/LeaderboardService.swift`

**Context:** Add a method to fetch badges for a single user via the `get_user_badges` RPC.

**Step 1: Add `fetchUserBadges` method**

Add after `fetchSpotlights`:

```swift
/// Fetch badges for a single user (all-time)
func fetchUserBadges(userId: UUID) async throws -> [LeaderboardBadge] {
    let client = await SupabaseService.shared.client

    let response = try await client
        .rpc("get_user_badges", params: ["target_user_id": userId.uuidString])
        .execute()

    let decoder = JSONDecoder()
    let rawBadges = try decoder.decode([String].self, from: response.data)
    let badges = rawBadges.compactMap { LeaderboardBadge(rawValue: $0) }

    AppLogger.info("leaderboard", "Fetched \(badges.count) badges for user: \(userId)")
    return badges
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/LeaderboardService.swift
git commit -m "feat: add fetchUserBadges method to LeaderboardService"
```

---

### Task 6: Add badges section to `PublicProfileView`

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift`

**Context:** Read this file first. Find the `headerSection` and the main content sections. We need to:
1. Add a `@State var badges: [LeaderboardBadge] = []` property
2. Fetch badges on appear via `LeaderboardService.shared.fetchUserBadges(userId:)`
3. Pass badges to the AvatarView in the header
4. Add a "Badges" section below the existing content showing all 5 badges (earned/unearned)

**Step 1: Add state and fetch**

Add property:
```swift
@State private var badges: [LeaderboardBadge] = []
```

Add `.task` modifier or extend existing one:
```swift
Task {
    badges = (try? await LeaderboardService.shared.fetchUserBadges(userId: userId)) ?? []
}
```

**Step 2: Pass badges to AvatarView in header**

Update the AvatarView call in `headerSection` to include `badges: badges`.

**Step 3: Add badges section**

Add a badge list section after the existing profile content. Show all `LeaderboardBadge.allCases`:

```swift
private var badgesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("badge_section_title".localized)
            .font(.naarsHeadline)
            .foregroundColor(.primary)

        ForEach(LeaderboardBadge.allCases, id: \.self) { badge in
            HStack(spacing: 12) {
                Text(badge.emoji)
                    .font(.title2)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(badge.displayName)
                        .font(.naarsSubheadline)
                        .fontWeight(.medium)

                    Text(badge.badgeDescription)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if badges.contains(badge) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.naarsSuccess)
                }
            }
            .opacity(badges.contains(badge) ? 1.0 : 0.4)
        }
    }
    .padding()
    .background(Color.naarsCardBackground)
    .cornerRadius(12)
    .padding(.horizontal)
}
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Profile/Views/PublicProfileView.swift
git commit -m "feat: add badge overlay and badges section to PublicProfileView"
```

---

### Task 7: Add badges section to `MyProfileView`

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift`

**Context:** Same approach as Task 6 but for the current user's own profile. Read the file first.

**Step 1: Add state and fetch**

Same pattern — `@State private var badges: [LeaderboardBadge] = []` and fetch on appear using `AuthService.shared.currentUserId`.

**Step 2: Pass badges to AvatarView in header**

Update the AvatarView call (line ~311-315) to include `badges: badges`.

**Step 3: Add badges section**

Reuse the same `badgesSection` view pattern from Task 6. Since both views need it, consider extracting it to a shared component:

Create `NaarsCars/UI/Components/Common/BadgeListSection.swift`:

```swift
//
//  BadgeListSection.swift
//  NaarsCars
//
//  Shared badge list showing earned/unearned badges
//

import SwiftUI

struct BadgeListSection: View {
    let earnedBadges: [LeaderboardBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("badge_section_title".localized)
                .font(.naarsHeadline)
                .foregroundColor(.primary)

            ForEach(LeaderboardBadge.allCases, id: \.self) { badge in
                HStack(spacing: 12) {
                    Text(badge.emoji)
                        .font(.title2)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.displayName)
                            .font(.naarsSubheadline)
                            .fontWeight(.medium)

                        Text(badge.badgeDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if earnedBadges.contains(badge) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.naarsSuccess)
                    }
                }
                .opacity(earnedBadges.contains(badge) ? 1.0 : 0.4)
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
    }
}
```

Then use `BadgeListSection(earnedBadges: badges)` in both `PublicProfileView` and `MyProfileView`.

**Step 4: Add to Xcode project**

Add `BadgeListSection.swift` to the project.pbxproj.

**Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Common/BadgeListSection.swift NaarsCars/Features/Profile/Views/MyProfileView.swift NaarsCars/NaarsCars.xcodeproj/project.pbxproj
git commit -m "feat: add badge overlay and badges section to MyProfileView, extract BadgeListSection"
```

---

### Task 8: Update PublicProfileView to use shared BadgeListSection

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift`

**Step 1:** Replace the inline badges section from Task 6 with `BadgeListSection(earnedBadges: badges)`.

**Step 2: Commit**

```bash
git add NaarsCars/Features/Profile/Views/PublicProfileView.swift
git commit -m "refactor: use shared BadgeListSection in PublicProfileView"
```

---

### Task 9: Run Supabase advisors and final build verification

**Step 1:** Run `mcp__supabase__get_advisors` for security — verify no new issues from `get_user_badges`.

**Step 2:** Run full build to verify no regressions.

**Step 3:** Commit any fixes.
