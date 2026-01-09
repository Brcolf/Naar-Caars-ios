# Tasks: Ride Requests

Based on `prd-ride-requests.md`

## Affected Flows

- FLOW_RIDE_001: Create Ride Request
- FLOW_RIDE_002: View Ride Details
- FLOW_RIDE_003: Edit Ride Request
- FLOW_RIDE_004: Delete Ride Request
- FLOW_RIDE_005: Post Q&A Question

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/RideService.swift` - Ride operations service
- `Core/Services/RealtimeManager.swift` - Centralized subscription management ⭐ USE THIS
- `Core/Models/Ride.swift` - Ride data model (extend from foundation)
- `Core/Models/RideStatus.swift` - Ride status enum
- `Core/Models/RequestQA.swift` - Q&A model for rides
- `Features/Rides/Views/RidesDashboardView.swift` - List of all rides
- `Features/Rides/Views/RideDetailView.swift` - Single ride detail screen
- `Features/Rides/Views/CreateRideView.swift` - Create new ride form
- `Features/Rides/Views/EditRideView.swift` - Edit existing ride form
- `Features/Rides/ViewModels/RidesDashboardViewModel.swift` - Dashboard view model
- `Features/Rides/ViewModels/RideDetailViewModel.swift` - Detail view model
- `Features/Rides/ViewModels/CreateRideViewModel.swift` - Create form view model
- `UI/Components/Cards/RideCard.swift` - Ride card component
- `UI/Components/Common/RequestQAView.swift` - Q&A section component

### Test Files
- `NaarsCarsTests/Core/Services/RideServiceTests.swift` - RideService unit tests
- `NaarsCarsTests/Features/Rides/RidesDashboardViewModelTests.swift` - Dashboard VM tests
- `NaarsCarsTests/Features/Rides/CreateRideViewModelTests.swift` - Create ride VM tests
- `NaarsCarsTests/Features/Rides/RideDetailViewModelTests.swift` - Detail VM tests
- `NaarsCarsSnapshotTests/Rides/RideCardSnapshots.swift` - Ride card UI snapshots
- `NaarsCarsIntegrationTests/Rides/RideCreationTests.swift` - Ride creation integration

## Notes

- This feature depends on foundation, authentication, and user profile
- Rides can have co-requestors (participants table)
- Supports Q&A thread for clarification questions
- ⭐ MUST use RealtimeManager for subscriptions (prevents memory leaks)
- ⭐ Use CacheManager for rides list (2-minute TTL)
- ⭐ Show skeleton loading while fetching
- 🧪 items are QA tasks - write tests as you implement
- 🔒 CHECKPOINT items are mandatory quality gates - do not skip

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
  - [x] 0.1 Create and checkout: `git checkout -b feature/ride-requests`

- [x] 1.0 Create Ride data models
  - [x] 1.1 Open Ride.swift (created in foundation) and verify all fields exist
  - [x] 1.2 Add fields: userId, type, date, time, pickup, destination, seats, notes, gift
  - [x] 1.3 Add status field with RideStatus enum type
  - [x] 1.4 Add claimedBy, reviewed, reviewSkipped, reviewSkippedAt fields
  - [x] 1.5 Add optional joined fields: poster, claimer, participants, qaCount
  - [x] 1.6 Create RideStatus enum with cases: open, pending, confirmed, completed
  - [x] 1.7 Add displayText computed property to RideStatus
  - [x] 1.8 Add color computed property to RideStatus (for badges)
  - [x] 1.9 Add proper CodingKeys for snake_case mapping
  - [x] 1.10 🧪 Write RideTests.testCodableDecoding_SnakeCase_Success
  - [x] 1.11 Create RequestQA.swift model in Core/Models
  - [x] 1.12 Add fields: id, requestId, requestType, userId, question, answer, createdAt
  - [x] 1.13 Add optional asker Profile for display

- [x] 2.0 Implement RideService
  - [x] 2.1 Create RideService.swift in Core/Services with singleton pattern
  - [x] 2.2 Implement fetchRides() with optional filters for status, userId, claimedBy
  - [x] 2.3 ⭐ Check CacheManager.getCachedRides() first
  - [x] 2.4 ⭐ If cache hit and fresh, return cached data
  - [x] 2.5 Order rides by date ascending (soonest first)
  - [x] 2.6 Implement enrichRidesWithProfiles() helper
  - [x] 2.7 ⭐ Cache results with CacheManager.cacheRides()
  - [x] 2.8 🧪 Write RideServiceTests.testFetchRides_CacheHit_ReturnsWithoutNetwork
  - [x] 2.9 🧪 Write RideServiceTests.testFetchRides_CacheMiss_FetchesAndCaches
  - [x] 2.10 Implement fetchRide(id:) for single ride with all related data
  - [x] 2.11 Implement createRide() method accepting all ride parameters
  - [x] 2.12 Format date as "yyyy-MM-dd" and time as "HH:mm:ss"
  - [x] 2.13 ⭐ Invalidate rides cache after create
  - [x] 2.14 🧪 Write RideServiceTests.testCreateRide_InvalidatesCache
  - [x] 2.15 Implement updateRide() method for editing existing rides
  - [x] 2.16 Implement deleteRide(id:) method
  - [x] 2.17 Implement Q&A methods: fetchQA, postQuestion, postAnswer
  - [x] 2.18 Add error handling for all methods

### 🔒 CHECKPOINT: QA-RIDE-001
> Run: `./QA/Scripts/checkpoint.sh ride-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_RIDE_001 (partial - service layer)
> Must pass before continuing

- [x] 3.0 Build Rides Dashboard View
  - [x] 3.1 Create RidesDashboardView.swift in Features/Rides/Views
  - [x] 3.2 Add @StateObject for RidesDashboardViewModel
  - [x] 3.3 Add segmented picker for filtering (All, Mine, Claimed)
  - [x] 3.4 ⭐ Show SkeletonRideCard components while loading (3 cards)
  - [x] 3.5 Display List of rides using RideCard component
  - [x] 3.6 Add NavigationLink to RideDetailView for each ride
  - [x] 3.7 Add floating "+" button to create new ride
  - [x] 3.8 Show empty state if no rides match filter
  - [x] 3.9 Add pull-to-refresh functionality
  - [x] 3.10 ⭐ Subscribe to rides changes using RealtimeManager

- [x] 4.0 Implement RidesDashboardViewModel
  - [x] 4.1 Create RidesDashboardViewModel.swift
  - [x] 4.2 Add @Published properties: rides, filter, isLoading, error
  - [x] 4.3 Implement loadRides() method
  - [x] 4.4 Implement filterRides() to update displayed list
  - [x] 4.5 ⭐ Setup realtime subscription for live updates
  - [x] 4.6 🧪 Write RidesDashboardViewModelTests.testLoadRides_Success
  - [x] 4.7 🧪 Write RidesDashboardViewModelTests.testFilterRides_MineOnly

- [x] 5.0 Build Create Ride View
  - [x] 5.1 Create CreateRideView.swift in Features/Rides/Views
  - [x] 5.2 Add @StateObject for CreateRideViewModel
  - [x] 5.3 Add DatePicker for date selection
  - [x] 5.4 Add time picker for departure time
  - [x] 5.5 Add TextField for pickup location
  - [x] 5.6 Add TextField for destination
  - [x] 5.7 Add Stepper for number of seats (1-7)
  - [x] 5.8 Add TextField for notes (optional)
  - [x] 5.9 Add TextField for gift (optional)
  - [x] 5.10 Add "Post Request" button
  - [x] 5.11 Validate required fields before submission
  - [x] 5.12 Navigate back on successful creation

- [x] 6.0 Implement CreateRideViewModel
  - [x] 6.1 Create CreateRideViewModel.swift
  - [x] 6.2 Add @Published properties for all form fields
  - [x] 6.3 Implement validateForm() method
  - [x] 6.4 Implement createRide() method
  - [x] 6.5 🧪 Write CreateRideViewModelTests.testValidateForm_MissingPickup_ReturnsError
  - [x] 6.6 🧪 Write CreateRideViewModelTests.testValidateForm_PastDate_ReturnsError
  - [x] 6.7 🧪 Write CreateRideViewModelTests.testCreateRide_Success

### 🔒 CHECKPOINT: QA-RIDE-002
> Run: `./QA/Scripts/checkpoint.sh ride-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_RIDE_001 (complete)
> Must pass before continuing

- [x] 7.0 Build Ride Detail View
  - [x] 7.1 Create RideDetailView.swift
  - [x] 7.2 Display ride poster info with UserAvatarLink
  - [x] 7.3 Display route (pickup → destination)
  - [x] 7.4 Display date, time, seats
  - [x] 7.5 Display notes and gift if present
  - [x] 7.6 Display status badge
  - [x] 7.7 Show action buttons based on user role and status
  - [x] 7.8 Add Q&A section using RequestQAView
  - [x] 7.9 Add edit/delete buttons for poster
  - [x] 7.10 Implement pull-to-refresh

- [x] 8.0 Implement RideDetailViewModel
  - [x] 8.1 Create RideDetailViewModel.swift
  - [x] 8.2 Implement loadRide(id:) method
  - [x] 8.3 Implement postQuestion() method
  - [x] 8.4 Implement deleteRide() method
  - [x] 8.5 🧪 Write RideDetailViewModelTests.testLoadRide_Success
  - [x] 8.6 🧪 Write RideDetailViewModelTests.testPostQuestion_Success

- [x] 9.0 Build Edit Ride View
  - [x] 9.1 Create EditRideView.swift (similar to CreateRideView)
  - [x] 9.2 Pre-populate form with existing ride data
  - [x] 9.3 Add "Save Changes" button
  - [x] 9.4 Notify claimer if ride is claimed and details change

- [x] 10.0 Build UI Components
  - [x] 10.1 Update RideCard.swift with full implementation
  - [x] 10.2 Display poster avatar, name
  - [x] 10.3 Display route with arrow icon
  - [x] 10.4 Display date/time formatted nicely
  - [x] 10.5 Display status badge with color
  - [x] 10.6 Create RequestQAView.swift component
  - [x] 10.7 Display list of questions with answers
  - [x] 10.8 Add input field for new questions
  - [x] 10.9 Add Xcode previews

- [x] 11.0 Verify ride requests implementation
  - [x] 11.1 Build and ensure zero compilation errors
  - [ ] 11.2 Test creating ride - verify appears in list (Manual testing required)
  - [ ] 11.3 Test viewing ride details - verify all data displays (Manual testing required)
  - [ ] 11.4 Test editing ride - verify changes persist (Manual testing required)
  - [ ] 11.5 Test deleting ride - verify removed from list (Manual testing required)
  - [ ] 11.6 Test Q&A posting - verify question appears (Manual testing required)
  - [ ] 11.7 Test realtime updates - verify live changes (Manual testing required)
  - [ ] 11.8 Test caching - verify faster subsequent loads (Manual testing required)
  - [ ] 11.9 Code review and commit: "feat: implement ride requests"

### 🔒 CHECKPOINT: QA-RIDE-FINAL
> Run: `./QA/Scripts/checkpoint.sh ride-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_RIDE_001, FLOW_RIDE_002, FLOW_RIDE_003, FLOW_RIDE_004, FLOW_RIDE_005
> All ride tests must pass before starting Favor Requests
