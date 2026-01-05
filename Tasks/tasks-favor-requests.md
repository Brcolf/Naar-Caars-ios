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

## Tasks

- [ ] 0.0 Create feature branch
  - [ ] 0.1 `git checkout -b feature/favor-requests`

- [ ] 1.0 Create Favor data models
  - [ ] 1.1 Open Favor.swift and verify/add all fields
  - [ ] 1.2 Add fields: userId, date, time, location, duration, requirements, description, gift
  - [ ] 1.3 Add status field with FavorStatus enum type
  - [ ] 1.4 Add claimedBy, reviewed, reviewSkipped fields
  - [ ] 1.5 Create FavorStatus enum (open, pending, confirmed, completed)
  - [ ] 1.6 Create Duration enum (thirtyMin, oneHour, twoHours, halfDay, fullDay, multiDay)
  - [ ] 1.7 🧪 Write FavorTests.testCodableDecoding_Success

- [ ] 2.0 Implement FavorService
  - [ ] 2.1 Create FavorService.swift with singleton pattern
  - [ ] 2.2 Implement fetchFavors() with cache check
  - [ ] 2.3 Implement createFavor() with cache invalidation
  - [ ] 2.4 Implement updateFavor() and deleteFavor()
  - [ ] 2.5 🧪 Write FavorServiceTests.testFetchFavors_CacheHit
  - [ ] 2.6 🧪 Write FavorServiceTests.testCreateFavor_InvalidatesCache

### 🔒 CHECKPOINT: QA-FAVOR-001
> Run: `./QA/Scripts/checkpoint.sh favor-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: FavorService tests pass
> Must pass before continuing

- [ ] 3.0 Build Favors Dashboard View
  - [ ] 3.1 Create FavorsDashboardView.swift
  - [ ] 3.2 Add segmented picker for filtering
  - [ ] 3.3 ⭐ Show skeleton loading while fetching
  - [ ] 3.4 Display List of favors using FavorCard
  - [ ] 3.5 Add floating "+" button for new favor
  - [ ] 3.6 Add pull-to-refresh

- [ ] 4.0 Implement FavorsDashboardViewModel
  - [ ] 4.1 Create FavorsDashboardViewModel.swift
  - [ ] 4.2 Implement loadFavors() and filterFavors()
  - [ ] 4.3 Setup realtime subscription
  - [ ] 4.4 🧪 Write FavorsDashboardViewModelTests.testLoadFavors_Success

- [ ] 5.0 Build Create Favor View
  - [ ] 5.1 Create CreateFavorView.swift
  - [ ] 5.2 Add fields: title, location, duration picker, date, requirements, description, gift
  - [ ] 5.3 Validate required fields
  - [ ] 5.4 Navigate back on success

- [ ] 6.0 Implement CreateFavorViewModel
  - [ ] 6.1 Create CreateFavorViewModel.swift
  - [ ] 6.2 Implement validateForm() and createFavor()
  - [ ] 6.3 🧪 Write CreateFavorViewModelTests.testValidateForm_MissingLocation
  - [ ] 6.4 🧪 Write CreateFavorViewModelTests.testCreateFavor_Success

- [ ] 7.0 Build Favor Detail View
  - [ ] 7.1 Create FavorDetailView.swift
  - [ ] 7.2 Display poster, location, duration, date/time
  - [ ] 7.3 Show status badge and action buttons
  - [ ] 7.4 Add edit/delete for poster

- [ ] 8.0 Build UI Components
  - [ ] 8.1 Update FavorCard.swift with full implementation
  - [ ] 8.2 Display duration badge
  - [ ] 8.3 Add Xcode previews

- [ ] 9.0 Verify favor requests implementation
  - [ ] 9.1 Test creating, viewing, editing, deleting favors
  - [ ] 9.2 Test realtime updates and caching
  - [ ] 9.3 Commit: "feat: implement favor requests"

### 🔒 CHECKPOINT: QA-FAVOR-FINAL
> Run: `./QA/Scripts/checkpoint.sh favor-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_FAVOR_001
> All favor tests must pass before starting Request Claiming
