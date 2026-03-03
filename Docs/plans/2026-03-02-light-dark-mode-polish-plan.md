# Light/Dark Mode UI Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the dark mode conversation name fade artifact and add consistent light mode background contrast across all main views.

**Architecture:** Two independent fixes: (1) replace color-dependent gradient overlay in FadingTitleText with a color-independent `.mask()`, and (2) update the light mode primary background color and apply it explicitly to all 6 main tab views so white cards stand out against a slightly gray page background.

**Tech Stack:** SwiftUI, UIKit (UIColor for adaptive colors)

---

### Task 1: Fix FadingTitleText with mask approach

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationRow.swift:142-174`

**Step 1: Replace FadingTitleText implementation**

Replace the entire `FadingTitleText` struct body. The overlay gradient approach fades to a specific background color (breaks in dark mode). The mask approach fades the text itself from opaque to transparent — works on any background.

```swift
struct FadingTitleText: View {
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(width: maxWidth, alignment: .leading)
            .clipped()
            .mask(
                HStack(spacing: 0) {
                    Rectangle().fill(Color.black)
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40)
                }
            )
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationRow.swift
git commit -m "fix: use mask instead of overlay for FadingTitleText fade effect

The gradient overlay faded to a hardcoded background color, creating a
visible artifact in dark mode. The mask approach fades the text itself
from opaque to transparent, working identically on any background."
```

---

### Task 2: Update light mode background color

**Files:**
- Modify: `NaarsCars/UI/Styles/ColorTheme.swift:97-104`

**Step 1: Change naarsBackground light mode value**

Change the light mode hex from `F8F9FA` to `F2F2F7` (iOS system grouped background color). This creates visible contrast against white cards/rows.

```swift
/// Primary background - main app background
static let naarsBackground = Color(UIColor { traitCollection in
    switch traitCollection.userInterfaceStyle {
    case .dark:
        return UIColor(hex: "121212") // Material Design dark background
    default:
        return UIColor(hex: "F2F2F7") // iOS system grouped background
    }
})
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/UI/Styles/ColorTheme.swift
git commit -m "style: darken light mode background to F2F2F7 for card contrast

Changes naarsBackground from near-white F8F9FA to iOS system grouped
background F2F2F7. This creates visible contrast between the page
background and white card surfaces, matching the Settings view aesthetic."
```

---

### Task 3: Add background to ScrollView-based views

**Files:**
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift` (listContentView ~line 121)
- Modify: `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift` (postsFeedContent, skeletonLoadingView, postsListView)
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift` (body ScrollView ~line 37)

**Step 1: RequestsDashboardView — add background to ScrollView**

In `listContentView`, add `.background(Color.naarsBackground)` after the ScrollView's closing brace (after `.refreshable` or equivalent). The exact location is on the `ScrollViewReader` or the `ScrollView` block.

Add to the ScrollView:
```swift
ScrollView {
    // ... existing content ...
}
.background(Color.naarsBackground)
```

**Step 2: TownHallFeedView — add background to all ScrollViews**

TownHallFeedView has multiple ScrollView branches (skeletonLoadingView, postsListView). Add `.background(Color.naarsBackground)` to each ScrollView.

For `skeletonLoadingView`:
```swift
ScrollView {
    // ... existing content ...
}
.background(Color.naarsBackground)
```

For `postsListView`, add to the outer ScrollView (inside ScrollViewReader):
```swift
ScrollView {
    // ... existing content ...
}
.refreshable { ... }
.background(Color.naarsBackground)
```

**Step 3: MyProfileView — add background to ScrollView**

In the `body`, add `.background(Color.naarsBackground)` to the ScrollView:
```swift
ScrollView {
    VStack(spacing: Constants.Spacing.lg) {
        // ... sections ...
    }
    .padding()
}
.background(Color.naarsBackground)
```

**Step 4: Build to verify**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add NaarsCars/Features/Requests/Views/RequestsDashboardView.swift \
       NaarsCars/Features/TownHall/Views/TownHallFeedView.swift \
       NaarsCars/Features/Profile/Views/MyProfileView.swift
git commit -m "style: add naarsBackground to ScrollView-based main views

Applies the grouped background color to Requests, Town Hall, and
Profile views so white cards stand out against the gray page."
```

---

### Task 4: Add background to List-based views

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationsListView.swift`
- Modify: `NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift`
- Modify: `NaarsCars/Features/Notifications/Views/NotificationsListView.swift`

For List views, we need both `.scrollContentBackground(.hidden)` (to remove the default white List background) and `.background(Color.naarsBackground)`.

**Step 1: ConversationsListView — all List instances**

There are 3 List instances in this file: skeleton loading list (~line 37), searchResultsList (~line 72), and conversationsList (~line 146). Add to each:

```swift
.listStyle(.plain)
.scrollContentBackground(.hidden)
.background(Color.naarsBackground)
```

**Step 2: LeaderboardView — all List instances**

There are 2 List instances: skeleton loading (~line 36) and main list (~line 57). Add to each:

```swift
.listStyle(.plain)
.scrollContentBackground(.hidden)
.background(Color.naarsBackground)
```

**Step 3: NotificationsListView — all List instances**

There are 2 List instances: skeleton loading (~line 65) and notificationsList (~line 94). Add to each:

```swift
.listStyle(.plain)
.scrollContentBackground(.hidden)
.background(Color.naarsBackground)
```

**Step 4: Build to verify**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationsListView.swift \
       NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift \
       NaarsCars/Features/Notifications/Views/NotificationsListView.swift
git commit -m "style: add naarsBackground to List-based main views

Uses scrollContentBackground(.hidden) + naarsBackground on Messages,
Leaderboard, and Notifications lists for consistent gray page background."
```
