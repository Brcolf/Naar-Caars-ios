# QA Checkpoint Guide

## Overview

This guide defines how to execute QA checkpoints during Naar's Cars iOS development. Checkpoints are mandatory stopping points that enforce quality gates before proceeding to the next phase of work.

---

## Quick Reference

### Checkpoint Commands

```bash
# Run a specific checkpoint
./QA/Scripts/checkpoint.sh <checkpoint-id>

# Examples:
./QA/Scripts/checkpoint.sh foundation-001
./QA/Scripts/checkpoint.sh auth-002
./QA/Scripts/checkpoint.sh messaging-final

# Run all tests for a feature
./QA/Scripts/checkpoint.sh --feature messaging

# Generate checkpoint report
./QA/Scripts/generate-report.sh <checkpoint-id>
```

### Checkpoint Status Markers

When you complete a checkpoint, update the task file:

```markdown
### 🔒 CHECKPOINT: QA-AUTH-002
> Status: ✅ PASSED | Date: 2025-01-15 | Report: QA/Reports/auth-002/
```

Or if blocked:

```markdown
### 🔒 CHECKPOINT: QA-AUTH-002
> Status: ❌ BLOCKED | See: QA/Reports/auth-002/failures.md
> Blocking Issues:
> - [ ] AuthServiceTests.testLoginValidation - assertion failure
> - [ ] Fix required before proceeding
```

---

## Checkpoint Execution Process

### Step 1: Recognize the Checkpoint

When you encounter this in a task file:

```markdown
### 🔒 CHECKPOINT: QA-[FEATURE]-[NUMBER]
> Run: `./QA/Scripts/checkpoint.sh [checkpoint-id]`
> Guide: QA/CHECKPOINT-GUIDE.md
> Must pass before continuing
```

**STOP.** Do not proceed to the next task until this checkpoint passes.

### Step 2: Run the Checkpoint Script

```bash
./QA/Scripts/checkpoint.sh auth-002
```

The script will:
1. Identify which tests to run based on the checkpoint
2. Execute unit tests for the affected feature
3. Execute integration tests (if applicable)
4. Execute snapshot tests (if applicable)
5. Generate a report

### Step 3: Review Results

**If all tests pass:**
```
✅ CHECKPOINT QA-AUTH-002 PASSED
   Unit Tests: 24/24 passed
   Integration: 3/3 passed
   Duration: 12.4s
   Report: QA/Reports/auth-002/summary.md
```

Update the checkpoint in the task file to `✅ PASSED` and continue.

**If tests fail:**
```
❌ CHECKPOINT QA-AUTH-002 FAILED
   Unit Tests: 22/24 passed (2 failed)
   Integration: 3/3 passed
   
   FAILURES:
   1. AuthServiceTests.testLoginWithInvalidCredentials
      File: NaarsCarsTests/Core/Services/AuthServiceTests.swift:87
      Expected: AppError.invalidCredentials
      Actual: AppError.networkError
      
   2. LoginViewModelTests.testLoadingState
      File: NaarsCarsTests/Features/Auth/LoginViewModelTests.swift:45
      Expected: isLoading == true
      Actual: isLoading == false
```

### Step 4: Fix Failures

For each failure:

1. **Read the error** - Understand what failed and why
2. **Locate the source** - Open the failing test file
3. **Identify root cause** - Is it a test bug or implementation bug?
4. **Fix the issue** - Update code or test as needed
5. **Re-run the checkpoint** - Verify the fix works

### Step 5: Document and Continue

Once passed:
1. Update checkpoint status in task file
2. Commit your changes with message: `checkpoint: QA-AUTH-002 passed`
3. Continue to the next task

---

## Checkpoint Types

### Database Checkpoint (Task 5.0)

⚠️ **Special Case:** The database checkpoint (Task 5.0) is executed **manually in Supabase Dashboard** before app development begins. This is the only checkpoint that doesn't use the automated script.

**What to verify:**
- SEC-DB-* security tests (10 tests)
- PERF-DB-* performance tests (5 tests)
- EDGE-* Edge Function tests (3 tests)

**How to execute:**
1. Open Supabase Dashboard → SQL Editor
2. Run verification queries from DATABASE-SCHEMA.md
3. Test each SEC-DB scenario manually
4. Document results in task file

See **Database Test Categories** section below for details.

### Unit Test Checkpoints

Focus: Individual functions and classes in isolation

```bash
# What runs:
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsTests/[Feature]
```

**Passing criteria:**
- All targeted unit tests pass
- No new compiler warnings introduced
- Coverage ≥ 80% on new code

### Integration Test Checkpoints

Focus: Service layer with real Supabase test environment

```bash
# What runs:
./QA/Scripts/seed-test-data.sh && \
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsIntegrationTests/[Feature]
```

**Passing criteria:**
- All integration tests pass
- Test data properly seeded
- No cross-test contamination

### Snapshot Test Checkpoints

Focus: UI appearance hasn't regressed

```bash
# What runs:
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsSnapshotTests/[Feature]
```

**Passing criteria:**
- All snapshots match baseline
- OR baselines updated intentionally (document why)

### Phase Completion Checkpoints

Focus: Entire phase is stable and complete

These run ALL test types for ALL features in a phase. Only triggered at end of major phases (Foundation, Core, Communication, etc.).

---

## Database Test Categories

These tests are executed manually in Task 5.0 before app development begins.

### SEC-DB-* Security Tests

| Test ID | Test Description | Expected Result | How to Verify |
|---------|------------------|-----------------|---------------|
| SEC-DB-001 | Query profiles as unauthenticated | Blocked by RLS | Run query without auth token |
| SEC-DB-002 | Query profiles as unapproved user (eve) | Only own profile returned | Login as eve@test.com, query profiles |
| SEC-DB-003 | Query profiles as approved user (bob) | All approved profiles returned | Login as bob@test.com, query profiles |
| SEC-DB-004 | Update another user's profile | Blocked by RLS | Try UPDATE on different user's profile |
| SEC-DB-005 | Set own is_admin=true as non-admin | Blocked by trigger | Try UPDATE profiles SET is_admin=true |
| SEC-DB-006 | Admin (alice) approve user | Succeeds | Login as alice, approve pending user |
| SEC-DB-007 | Non-admin approve user | Blocked by RLS | Login as bob, try to approve user |
| SEC-DB-008 | Query messages not in conversation | Blocked by RLS | Query messages for conversation you're not in |
| SEC-DB-009 | Insert ride with different user_id | Blocked by RLS | Try INSERT INTO rides with other user's ID |
| SEC-DB-010 | Claim own ride | Blocked by constraint/RLS | Try to claim your own ride |

**Verification query template:**
```sql
-- SEC-DB-002: Test as unapproved user
-- First, get JWT token for eve@test.com in Supabase Auth
-- Then run:
SELECT * FROM profiles;
-- Expected: Only eve's profile returned
```

### PERF-DB-* Performance Tests

| Test ID | Test Description | Target | How to Verify |
|---------|------------------|--------|---------------|
| PERF-DB-001 | Query open rides (100 rows) | <100ms | EXPLAIN ANALYZE SELECT * FROM rides WHERE status='open' |
| PERF-DB-002 | Query leaderboard (50 users) | <200ms | EXPLAIN ANALYZE SELECT * FROM get_leaderboard('year') |
| PERF-DB-003 | Query conversation messages (100) | <100ms | EXPLAIN ANALYZE SELECT * FROM messages WHERE conversation_id=... |
| PERF-DB-004 | Insert message with trigger | <50ms | Time INSERT INTO messages with trigger execution |
| PERF-DB-005 | Indexes exist for all FKs | Verified | Query pg_indexes for expected indexes |

**Verification query:**
```sql
-- Check indexes exist
SELECT tablename, indexname, indexdef 
FROM pg_indexes 
WHERE schemaname = 'public'
ORDER BY tablename;
```

### EDGE-* Edge Function Tests

| Test ID | Test Description | Expected Result | How to Verify |
|---------|------------------|-----------------|---------------|
| EDGE-001 | Send push to valid token | 200 response, notification received | Invoke function with valid device token |
| EDGE-002 | Send push to invalid token | Token removed from database | Invoke with invalid token, check push_tokens table |
| EDGE-003 | Cleanup tokens older than 90 days | Correct count returned | Add old token, run cleanup, verify removed |

**Verification:**
```bash
# Invoke Edge Function
supabase functions invoke send-push-notification --body '{"token":"test","title":"Test","body":"Test message"}'
```

### PERF-CLI-* Client Performance Tests

These are executed during QA-FOUNDATION-FINAL (Task 22.0) after app is built:

| Test ID | Test Description | Target | How to Verify |
|---------|------------------|--------|---------------|
| PERF-CLI-001 | App cold launch to main screen | <1 second | Use Xcode Instruments or stopwatch |
| PERF-CLI-002 | Cache hit returns immediately | <10ms | Log timestamp before/after cache call |
| PERF-CLI-003 | Rate limiter blocks rapid taps | Second tap blocked | Tap button twice rapidly, verify second blocked |
| PERF-CLI-004 | Image compression meets limits | Output ≤ preset max size | Compress test image, verify bytes |

---

## Test File Locations

```
NaarsCars/
├── NaarsCarsTests/                    # Unit tests
│   ├── Core/
│   │   ├── Services/
│   │   │   ├── AuthServiceTests.swift
│   │   │   ├── RideServiceTests.swift
│   │   │   └── MessageServiceTests.swift
│   │   ├── Utilities/
│   │   │   ├── RateLimiterTests.swift
│   │   │   ├── CacheManagerTests.swift
│   │   │   └── ImageCompressorTests.swift
│   │   └── Models/
│   │       ├── ProfileTests.swift
│   │       ├── RideTests.swift
│   │       └── FavorTests.swift
│   ├── Features/
│   │   ├── Authentication/
│   │   │   ├── LoginViewModelTests.swift
│   │   │   └── SignupViewModelTests.swift
│   │   ├── Rides/
│   │   ├── Favors/
│   │   └── Messaging/
│   └── Mocks/
│       ├── MockSupabaseClient.swift
│       └── MockAuthService.swift
│
├── NaarsCarsIntegrationTests/         # Integration tests
│   ├── Auth/
│   ├── Rides/
│   └── Realtime/
│
└── NaarsCarsSnapshotTests/            # Snapshot tests
    ├── Authentication/
    ├── Dashboard/
    └── Messaging/
```

---

## Writing Tests for Checkpoints

### Unit Test Template

```swift
import XCTest
@testable import NaarsCars

final class AuthServiceTests: XCTestCase {
    var sut: AuthService!  // System Under Test
    var mockSupabase: MockSupabaseClient!
    
    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = AuthService(client: mockSupabase)
    }
    
    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }
    
    // MARK: - FLOW_AUTH_002: Login Tests
    
    func testLoginWithValidCredentials() async throws {
        // Given
        mockSupabase.mockSession = MockSession.valid
        
        // When
        try await sut.logIn(email: "test@test.com", password: "password123")
        
        // Then
        XCTAssertNotNil(sut.currentUserId)
        XCTAssertNotNil(sut.currentProfile)
    }
    
    func testLoginWithInvalidCredentials() async {
        // Given
        mockSupabase.mockError = .invalidCredentials
        
        // When/Then
        do {
            try await sut.logIn(email: "test@test.com", password: "wrong")
            XCTFail("Expected error to be thrown")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
```

### Integration Test Template

```swift
import XCTest
@testable import NaarsCars

final class AuthIntegrationTests: XCTestCase {
    var sut: AuthService!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use real Supabase test client
        sut = AuthService(client: SupabaseTestClient.shared)
        // Seed test data
        try await TestDataSeeder.seedAuthTestData()
    }
    
    override func tearDown() async throws {
        try await TestDataSeeder.cleanAuthTestData()
        sut = nil
        try await super.tearDown()
    }
    
    func testFullSignupFlow() async throws {
        // Given - unused invite code from test data
        let inviteCode = "TESTCODE1"
        
        // When
        try await sut.signUp(
            email: "newuser-\(UUID())@test.com",
            password: "TestPassword123!",
            name: "Test User",
            inviteCode: inviteCode,
            car: nil
        )
        
        // Then
        XCTAssertNotNil(sut.currentUserId)
        XCTAssertEqual(sut.currentProfile?.approved, false)
    }
}
```

---

## Checkpoint-to-Test Mapping

| Checkpoint | Test Target | Test Type |
|------------|-------------|-----------|
| Task 5.0 (Database) | SEC-DB-*, PERF-DB-*, EDGE-* | Manual |
| foundation-001 | NaarsCarsTests/Core/Models | Unit |
| foundation-002 | Manual: App launches, navigation works | Manual |
| foundation-003 | NaarsCarsTests/Core/Utilities/RateLimiter*, CacheManager* | Unit |
| foundation-004 | NaarsCarsTests/Core/Utilities/ImageCompressor*, Services/RealtimeManager* | Unit |
| foundation-final | All NaarsCarsTests/Core + PERF-CLI-* | Unit + Manual |
| auth-001 | NaarsCarsTests/Core/Services/AuthService*Signup* | Unit |
| auth-002 | NaarsCarsTests/Core/Services/AuthService*Login*, Features/Authentication | Unit |
| auth-003 | NaarsCarsTests/Core/Services/AuthService*Session* | Unit |
| auth-final | All NaarsCarsTests/*Auth* + NaarsCarsIntegrationTests/Auth | Unit + Integration |
| profile-001 | NaarsCarsTests/Core/Services/ProfileService*, Utilities/Validators* | Unit |
| profile-002 | NaarsCarsTests/Features/Profile | Unit |
| profile-final | All Profile tests + NaarsCarsSnapshotTests/Profile | Unit + Snapshot |
| ride-001 | NaarsCarsTests/Core/Services/RideService* | Unit |
| ride-002 | NaarsCarsTests/Features/Rides | Unit |
| ride-final | All Ride tests + Integration | Unit + Integration |
| favor-001 | NaarsCarsTests/Core/Services/FavorService* | Unit |
| favor-final | All Favor tests | Unit |
| claim-001 | NaarsCarsTests/Core/Services/ClaimService* | Unit |
| claim-final | All Claim tests + Integration | Unit + Integration |
| messaging-001 | NaarsCarsTests/Core/Services/MessageService* | Unit |
| messaging-final | All Messaging tests + Integration | Unit + Integration |

---

## Checkpoint-to-Flow Mapping

Each checkpoint validates specific user flows. Reference `QA/FLOW-CATALOG.md` for flow definitions.

| Checkpoint | Flows Validated |
|------------|-----------------|
| Task 5.0 (Database) | FLOW_FOUNDATION_001 (database portion) |
| QA-FOUNDATION-001 | FLOW_FOUNDATION_001 (models portion) |
| QA-FOUNDATION-002 | FLOW_FOUNDATION_001 (app launch portion) |
| QA-FOUNDATION-003 | FLOW_FOUNDATION_001 (utilities) |
| QA-FOUNDATION-004 | FLOW_FOUNDATION_001 (realtime, image processing) |
| QA-FOUNDATION-FINAL | FLOW_FOUNDATION_001 (complete) |
| QA-AUTH-001 | FLOW_AUTH_001 (Signup) |
| QA-AUTH-002 | FLOW_AUTH_002 (Login) |
| QA-AUTH-003 | FLOW_AUTH_003 (Reset), FLOW_AUTH_004 (Logout) |
| QA-AUTH-FINAL | All FLOW_AUTH_* |
| QA-PROFILE-001 | FLOW_PROFILE_001 (service layer) |
| QA-PROFILE-002 | FLOW_PROFILE_001, FLOW_PROFILE_002 |
| QA-PROFILE-FINAL | All FLOW_PROFILE_* |
| QA-RIDE-001 | FLOW_RIDE_001 (Create - service) |
| QA-RIDE-002 | FLOW_RIDE_001-002 (Create, View) |
| QA-RIDE-FINAL | FLOW_RIDE_001-005 |
| QA-CLAIM-001 | FLOW_CLAIM_001 (service) |
| QA-CLAIM-FINAL | FLOW_CLAIM_001-003 |
| QA-MSG-001 | FLOW_MSG_001 (Open conversation) |
| QA-MSG-FINAL | FLOW_MSG_001-003 |

---

## Troubleshooting

### "Command not found: xcodebuild"

Ensure Xcode command line tools are installed:
```bash
xcode-select --install
```

### Tests timeout

Integration tests may timeout if Supabase test environment is slow:
```bash
# Increase timeout
xcodebuild test ... -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120
```

### Snapshot tests fail unexpectedly

Snapshots are device-specific. Always run on iPhone 15 simulator:
```bash
xcrun simctl list devices | grep "iPhone 15"
# Use exact device name in -destination parameter
```

### Test database contamination

If tests fail with "duplicate key" or stale data:
```bash
# Reset test data
./QA/Scripts/seed-test-data.sh --clean
```

### Database checkpoint (Task 5.0) issues

If SEC-DB tests fail:
1. Verify RLS is enabled: Check Dashboard → Authentication → Policies
2. Verify triggers exist: Check Dashboard → Database → Functions
3. Re-run 004_rls_policies.sql if policies missing
4. Check that test users have correct roles (alice=admin, eve=unapproved)

---

## Checkpoint Report Format

Reports are saved to `QA/Reports/[checkpoint-id]/`:

```
QA/Reports/auth-002/
├── summary.md          # Human-readable summary
├── unit-results.json   # Raw unit test results
├── integration-results.json
├── coverage.json       # Code coverage data
└── failures/           # Details on any failures
    ├── failure-001.md
    └── screenshots/    # UI test failure screenshots
```

### Summary Template

```markdown
# Checkpoint Report: QA-AUTH-002

**Date:** 2025-01-15 14:32:00 PST
**Triggered After Task:** 4.17 (Login form complete)
**Duration:** 18.4 seconds

## Results

| Layer | Tests | Passed | Failed | Skipped |
|-------|-------|--------|--------|---------|
| Unit | 24 | 24 | 0 | 0 |
| Integration | 3 | 3 | 0 | 0 |
| Snapshot | 4 | 4 | 0 | 0 |

## Coverage

| File | Coverage |
|------|----------|
| AuthService.swift | 92% |
| LoginViewModel.swift | 88% |
| SignupViewModel.swift | 85% |

## Flows Validated

- [x] FLOW_AUTH_002: Login with Email/Password
- [x] FLOW_AUTH_003: Password Reset

## Status: ✅ PASSED
```

---

## Definition of Done

A checkpoint is considered **PASSED** when:

1. ✅ All unit tests pass (100%)
2. ✅ All integration tests pass (100%)
3. ✅ All snapshot tests pass (or baselines intentionally updated)
4. ✅ No new compiler warnings
5. ✅ Code coverage ≥ 80% on new code
6. ✅ Report generated and saved
7. ✅ Checkpoint status updated in task file

A checkpoint is **BLOCKED** when any test fails. You must fix failures before proceeding.

**Special case - Task 5.0 Database Checkpoint:**
1. ✅ All SEC-DB-* tests pass (manual verification)
2. ✅ All PERF-DB-* tests meet targets
3. ✅ All EDGE-* tests pass
4. ✅ Results documented in task file
5. ✅ Proceed to app development (Task 6.0+)

---

## Questions?

If you're unsure whether to proceed past a checkpoint:
1. Re-read the failing test output carefully
2. Check if it's a flaky test (run again)
3. If legitimately blocked, fix the issue first
4. When in doubt, don't skip the checkpoint

The whole point is to catch issues early. A few minutes spent fixing now saves hours of debugging later.
