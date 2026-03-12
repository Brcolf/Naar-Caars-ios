---
color: green
position:
  x: -69
  y: -679
isContextNode: false
agent_name: Amy
---

# Testing & QA

Test suite and quality assurance structure.

## Test Structure

### NaarsCarsTests/
Unit and integration tests for the iOS app.

**Coverage:**
```
NaarsCarsTests/
├── Core/
│   ├── Models/          # Model tests
│   └── Services/        # Service layer tests
│       ├── ClaimServiceTests.swift
│       ├── RideServiceTests.swift
│       ├── FavorServiceTests.swift
│       └── ...
├── Features/
│   ├── Claiming/
│   │   └── ClaimViewModelTests.swift
│   ├── Favors/
│   │   ├── CreateFavorViewModelTests.swift
│   │   └── FavorsDashboardViewModelTests.swift
│   ├── Rides/
│   │   ├── CreateRideViewModelTests.swift
│   │   ├── RideDetailViewModelTests.swift
│   │   └── RidesDashboardViewModelTests.swift
│   ├── Notifications/
│   │   └── NotificationsListViewModelTests.swift
│   └── Reviews/
│       └── LeaveReviewViewModelTests.swift
└── ...
```

### NaarsCarsUITests/
UI automation tests:
- **NaarsCarsUITests.swift** - End-to-end UI flows
- **NaarsCarsUITestsLaunchTests.swift** - Launch performance

## Test Patterns

### Service Tests
Mock Supabase client to test service logic:
```swift
class ClaimServiceTests: XCTestCase {
    var mockSupabase: MockSupabaseClient!
    var claimService: ClaimService!

    override func setUp() {
        mockSupabase = MockSupabaseClient()
        claimService = ClaimService(supabase: mockSupabase)
    }

    func testClaimRequest() async throws {
        // Given
        let rideId = UUID()
        mockSupabase.mockResponse = [...]

        // When
        try await claimService.claimRequest(...)

        // Then
        XCTAssertEqual(mockSupabase.updateCallCount, 1)
    }
}
```

### ViewModel Tests
Test ViewModel logic with mocked services:
```swift
class CreateRideViewModelTests: XCTestCase {
    var viewModel: CreateRideViewModel!
    var mockRideService: MockRideService!

    func testCreateRideValidation() {
        // Test validation logic
    }

    func testCreateRideSuccess() async {
        // Test successful ride creation
    }
}
```

### UI Tests
XCTest UI automation:
```swift
class NaarsCarsUITests: XCTestCase {
    func testLoginFlow() {
        let app = XCUIApplication()
        app.launch()

        // Navigate to login
        app.buttons["Login"].tap()

        // Enter credentials
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("test@example.com")
        // ...
    }
}
```

## QA Documentation

### QA/
Manual QA test cases and checklists:
```
QA/
├── smoke_tests.md
├── regression_tests.md
├── release_checklist.md
├── bug_reports/
└── test_data/
```

## Test Coverage

**Estimated Coverage:**
- **Services:** ~70% - Most services have unit tests
- **ViewModels:** ~50% - Key ViewModels tested
- **Views:** ~10% - Limited UI tests (manual QA heavy)

## Testing Gaps

### 🟡 Missing Tests
1. **End-to-end claim flow** - Would have caught RLS bug
2. **Message sending resilience** - Test offline → online transition
3. **Real-time sync edge cases** - Out-of-order message handling
4. **Performance tests** - Conversation with 10k messages

### 🟡 Manual QA Heavy
Most testing is manual due to:
- Complex real-time interactions
- External dependencies (Supabase, APNs)
- Visual/UX validation needed

## CI/CD

### GitHub Actions (implied)
Likely automated:
- Run tests on PR
- Build verification
- Linting/SwiftLint

### TestFlight
Beta distribution:
- Internal testing
- External beta testers
- Staged rollout

## Testing Strategy Recommendations

### Short-Term
1. Add end-to-end test for claim flow (would prevent RLS bugs)
2. Add tests for message send retry logic
3. Add performance baseline tests

### Long-Term
1. Increase unit test coverage to 80%+
2. Add integration tests with test Supabase project
3. Add visual regression testing (snapshot tests)
4. Implement automated performance monitoring

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
