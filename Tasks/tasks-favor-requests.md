# Tasks: Favor Requests

Based on `prd-favor-requests.md`

## Affected Flows

- FLOW_FAVOR_001: Create Favor Request

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/FavorService.swift` - Favor operations service
- `Core/Services/RealtimeManager.swift` - Centralized subscription management ⭐ USE THIS
- `Core/Models/Favor.swift` - Favor data model (extend from foundation)
- `Core/Models/FavorStatus.swift` - Favor status enum
- `Features/Favors/Views/FavorsDashboardView.swift` - List of all favors
- `Features/Favors/Views/FavorDetailView.swift` - Single favor detail screen
- `Features/Favors/Views/CreateFavorView.swift` - Create new favor form
- `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` - Dashboard view model
- `Features/Favors/ViewModels/FavorDetailViewModel.swift` - Detail view model
- `Features/Favors/ViewModels/CreateFavorViewModel.swift` - Create form view model
- `UI/Components/Cards/FavorCard.swift` - Favor card component

### Test Files
- `NaarsCarsTests/Core/Services/FavorServiceTests.swift` - FavorService unit tests
- `NaarsCarsTests/Features/Favors/CreateFavorViewModelTests.swift` - Create favor VM tests
- `NaarsCarsTests/Features/Favors/FavorsDashboardViewModelTests.swift` - Dashboard VM tests
- `NaarsCarsSnapshotTests/Favors/FavorCardSnapshots.swift` - Favor card UI snapshots

## Notes

- Similar structure to ride requests but with different fields
- Duration instead of seats, location instead of pickup/destination
- ⭐ MUST use RealtimeManager for subscriptions
- ⭐ Use CacheManager for favors list (2-minute TTL)
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

- [x] 0.0 Create feature branch
  - [x] 0.1 `git checkout -b feature/favor-requests`

- [x] 1.0 Create Favor data models
  - [x] 1.1 Open Favor.swift and verify/add all fields
  - [x] 1.2 Add fields: userId, date, time, location, duration, requirements, description, gift
  - [x] 1.3 Add status field with FavorStatus enum type
  - [x] 1.4 Add claimedBy, reviewed, reviewSkipped fields
  - [x] 1.5 Create FavorStatus enum (open, pending, confirmed, completed)
  - [x] 1.6 Create Duration enum (underHour, coupleHours, coupleDays, notSure)
  - [x] 1.7 🧪 Write FavorTests.testCodableDecoding_Success

- [x] 2.0 Implement FavorService
  - [x] 2.1 Create FavorService.swift with singleton pattern
  - [x] 2.2 Implement fetchFavors() with cache check
  - [x] 2.3 Implement createFavor() with cache invalidation
  - [x] 2.4 Implement updateFavor() and deleteFavor()
  - [x] 2.5 🧪 Write FavorServiceTests.testFetchFavors_CacheHit
  - [x] 2.6 🧪 Write FavorServiceTests.testCreateFavor_InvalidatesCache

### 🔒 CHECKPOINT: QA-FAVOR-001
> Run: `./QA/Scripts/checkpoint.sh favor-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: FavorService tests pass
> Must pass before continuing

- [x] 3.0 Build Favors Dashboard View
  - [x] 3.1 Create FavorsDashboardView.swift
  - [x] 3.2 Add segmented picker for filtering
  - [x] 3.3 ⭐ Show skeleton loading while fetching
  - [x] 3.4 Display List of favors using FavorCard
  - [x] 3.5 Add floating "+" button for new favor
  - [x] 3.6 Add pull-to-refresh

- [x] 4.0 Implement FavorsDashboardViewModel
  - [x] 4.1 Create FavorsDashboardViewModel.swift
  - [x] 4.2 Implement loadFavors() and filterFavors()
  - [x] 4.3 Setup realtime subscription
  - [x] 4.4 🧪 Write FavorsDashboardViewModelTests.testLoadFavors_Success

- [x] 5.0 Build Create Favor View
  - [x] 5.1 Create CreateFavorView.swift
  - [x] 5.2 Add fields: title, location, duration picker, date, requirements, description, gift
  - [x] 5.3 Validate required fields
  - [x] 5.4 Navigate back on success

- [x] 6.0 Implement CreateFavorViewModel
  - [x] 6.1 Create CreateFavorViewModel.swift
  - [x] 6.2 Implement validateForm() and createFavor()
  - [x] 6.3 🧪 Write CreateFavorViewModelTests.testValidateForm_MissingLocation
  - [x] 6.4 🧪 Write CreateFavorViewModelTests.testCreateFavor_Success

- [x] 7.0 Build Favor Detail View
  - [x] 7.1 Create FavorDetailView.swift
  - [x] 7.2 Display poster, location, duration, date/time
  - [x] 7.3 Show status badge and action buttons
  - [x] 7.4 Add edit/delete for poster

- [x] 8.0 Build UI Components
  - [x] 8.1 Update FavorCard.swift with full implementation
  - [x] 8.2 Display duration badge
  - [x] 8.3 Add Xcode previews

- [x] 9.0 Verify favor requests implementation
  - [x] 9.1 Build and ensure zero compilation errors
  - [ ] 9.2 Test creating, viewing, editing, deleting favors (Manual testing required)
  - [ ] 9.3 Test realtime updates and caching (Manual testing required)
  - [ ] 9.4 Commit: "feat: implement favor requests"

### 🔒 CHECKPOINT: QA-FAVOR-FINAL
> Run: `./QA/Scripts/checkpoint.sh favor-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_FAVOR_001
> All favor tests must pass before starting Request Claiming
