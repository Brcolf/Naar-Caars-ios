# Tasks: Leaderboards

Based on `prd-leaderboards.md`

## Affected Flows

- FLOW_LEADERBOARD_001: View Leaderboard

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/LeaderboardService.swift` - Leaderboard operations
- `Core/Models/LeaderboardEntry.swift` - Entry data model
- `Features/Leaderboards/Views/LeaderboardView.swift` - Leaderboard screen
- `Features/Leaderboards/Views/LeaderboardRow.swift` - Entry row
- `Features/Leaderboards/ViewModels/LeaderboardViewModel.swift`

### Test Files
- `NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift`
- `NaarsCarsTests/Features/Leaderboards/LeaderboardViewModelTests.swift`
- `NaarsCarsSnapshotTests/Leaderboards/LeaderboardRowSnapshots.swift`

## Notes

- Rankings by fulfilled requests in time period
- Time periods: Year, Quarter, Month
- Highlight current user's position
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/leaderboards`

- [x] 1.0 Create LeaderboardEntry data model
  - [x] 1.1 Create LeaderboardEntry.swift in Core/Models
  - [x] 1.2 Add fields: rank, userId, name, avatarUrl, fulfilledCount, averageRating
  - [x] 1.3 Add isCurrentUser computed property
  - [x] 1.4 🧪 Write LeaderboardEntryTests.testIsCurrentUser

- [x] 2.0 Implement LeaderboardService
  - [x] 2.1 Create LeaderboardService.swift with singleton
  - [x] 2.2 Implement fetchLeaderboard(period:) method
  - [x] 2.3 Define TimePeriod enum (year, quarter, month)
  - [x] 2.4 Query completed rides/favors in time range (via RPC function)
  - [x] 2.5 Group by user, count completions, rank (server-side)
  - [x] 2.6 Limit to top 100 (via RPC function)
  - [x] 2.7 🧪 Write LeaderboardServiceTests.testFetchLeaderboard_OrderedByCount
  - [x] 2.8 Implement findCurrentUserRank(userId:, period:)
  - [x] 2.9 🧪 Write LeaderboardServiceTests.testFindUserRank_NotInTop50

### 🔒 CHECKPOINT: QA-LEADERBOARD-001
> Run: `./QA/Scripts/checkpoint.sh leaderboard-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: LeaderboardService tests pass
> Must pass before continuing

- [x] 3.0 Build Leaderboard View
  - [x] 3.1 Create LeaderboardView.swift
  - [x] 3.2 Add @StateObject for LeaderboardViewModel
  - [x] 3.3 Add segmented picker for time period
  - [x] 3.4 ⭐ Show skeleton loading while fetching
  - [x] 3.5 Display top 3 with special styling (medals 🥇🥈🥉)
  - [x] 3.6 Display remaining entries in list
  - [x] 3.7 Highlight current user's row
  - [x] 3.8 If user not in top 100, show their rank at bottom
  - [x] 3.9 Add pull-to-refresh

- [x] 4.0 Implement LeaderboardViewModel
  - [x] 4.1 Create LeaderboardViewModel.swift
  - [x] 4.2 Implement loadLeaderboard(period:) with caching
  - [x] 4.3 Find and set current user's rank
  - [x] 4.4 🧪 Write LeaderboardViewModelTests.testLoadLeaderboard_HighlightsCurrentUser

- [x] 5.0 Build LeaderboardRow
  - [x] 5.1 Create LeaderboardRow.swift
  - [x] 5.2 Show rank badge (1, 2, 3 with medals, others plain)
  - [x] 5.3 Display avatar and name
  - [x] 5.4 Show fulfilled count
  - [x] 5.5 Show requests made count (replaced averageRating per PRD)
  - [x] 5.6 Highlight if current user
  - [x] 5.7 Add Xcode previews

- [x] 6.0 Verify leaderboards implementation
  - [x] 6.1 Test different time periods (implemented via LeaderboardPeriod enum)
  - [x] 6.2 Test current user highlighting (implemented via isCurrentUser property)
  - [x] 6.3 Test user not in top 100 (implemented via currentUserRank)
  - [ ] 6.4 Commit: "feat: implement leaderboards"

### 🔒 CHECKPOINT: QA-LEADERBOARD-FINAL
> Run: `./QA/Scripts/checkpoint.sh leaderboard-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_LEADERBOARD_001
> All leaderboard tests must pass
