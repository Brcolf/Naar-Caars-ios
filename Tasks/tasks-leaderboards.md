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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/leaderboards`

- [ ] 1.0 Create LeaderboardEntry data model
  - [ ] 1.1 Create LeaderboardEntry.swift in Core/Models
  - [ ] 1.2 Add fields: rank, userId, name, avatarUrl, fulfilledCount, averageRating
  - [ ] 1.3 Add isCurrentUser computed property
  - [ ] 1.4 🧪 Write LeaderboardEntryTests.testIsCurrentUser

- [ ] 2.0 Implement LeaderboardService
  - [ ] 2.1 Create LeaderboardService.swift with singleton
  - [ ] 2.2 Implement fetchLeaderboard(period:) method
  - [ ] 2.3 Define TimePeriod enum (year, quarter, month)
  - [ ] 2.4 Query completed rides/favors in time range
  - [ ] 2.5 Group by user, count completions, rank
  - [ ] 2.6 Limit to top 50
  - [ ] 2.7 🧪 Write LeaderboardServiceTests.testFetchLeaderboard_OrderedByCount
  - [ ] 2.8 Implement findCurrentUserRank(userId:, period:)
  - [ ] 2.9 🧪 Write LeaderboardServiceTests.testFindUserRank_NotInTop50

### 🔒 CHECKPOINT: QA-LEADERBOARD-001
> Run: `./QA/Scripts/checkpoint.sh leaderboard-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: LeaderboardService tests pass
> Must pass before continuing

- [ ] 3.0 Build Leaderboard View
  - [ ] 3.1 Create LeaderboardView.swift
  - [ ] 3.2 Add @StateObject for LeaderboardViewModel
  - [ ] 3.3 Add segmented picker for time period
  - [ ] 3.4 ⭐ Show skeleton loading while fetching
  - [ ] 3.5 Display top 3 with special styling
  - [ ] 3.6 Display remaining entries in list
  - [ ] 3.7 Highlight current user's row
  - [ ] 3.8 If user not in top 50, show their rank at bottom
  - [ ] 3.9 Add pull-to-refresh

- [ ] 4.0 Implement LeaderboardViewModel
  - [ ] 4.1 Create LeaderboardViewModel.swift
  - [ ] 4.2 Implement loadLeaderboard(period:)
  - [ ] 4.3 Find and set current user's rank
  - [ ] 4.4 🧪 Write LeaderboardViewModelTests.testLoadLeaderboard_HighlightsCurrentUser

- [ ] 5.0 Build LeaderboardRow
  - [ ] 5.1 Create LeaderboardRow.swift
  - [ ] 5.2 Show rank badge (1, 2, 3 with medals, others plain)
  - [ ] 5.3 Display avatar and name
  - [ ] 5.4 Show fulfilled count
  - [ ] 5.5 Show average rating with stars
  - [ ] 5.6 Highlight if current user
  - [ ] 5.7 Add Xcode previews

- [ ] 6.0 Verify leaderboards implementation
  - [ ] 6.1 Test different time periods
  - [ ] 6.2 Test current user highlighting
  - [ ] 6.3 Test user not in top 50
  - [ ] 6.4 Commit: "feat: implement leaderboards"

### 🔒 CHECKPOINT: QA-LEADERBOARD-FINAL
> Run: `./QA/Scripts/checkpoint.sh leaderboard-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_LEADERBOARD_001
> All leaderboard tests must pass
