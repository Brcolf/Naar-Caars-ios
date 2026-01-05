# QA Runner Instructions for Cursor

## Overview

This document provides specific instructions for executing QA checkpoints when developing in Cursor. These instructions ensure consistent test execution and proper handling of results.

---

## Critical Rule

**When you encounter a checkpoint in a task list, you MUST stop and execute it before proceeding.**

```markdown
### 🔒 CHECKPOINT: QA-AUTH-002
> Run: `./QA/Scripts/checkpoint.sh auth-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Must pass before continuing
```

This is a **blocking gate**. Do not mark subsequent tasks as complete until the checkpoint passes.

---

## Checkpoint Execution Flow

### Step 1: Recognize and Stop

When you see the 🔒 CHECKPOINT marker:
1. Stop working on new tasks
2. Save any pending changes
3. Commit work in progress: `git commit -m "WIP: before checkpoint auth-002"`

### Step 2: Run Tests

Execute the checkpoint script:

```bash
./QA/Scripts/checkpoint.sh auth-002
```

If the script isn't available yet (early in project), run tests manually:

```bash
# Unit tests for the feature
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsTests/Features/Authentication \
  2>&1 | xcpretty

# Check for compilation errors first
xcodebuild build \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Step 3: Parse Results

**If tests pass:**
```
✅ All tests passed

Update the checkpoint in the task file:
### 🔒 CHECKPOINT: QA-AUTH-002
> Status: ✅ PASSED | Date: 2025-01-15
```

**If tests fail:**
```
❌ Tests failed

DO NOT proceed. Fix failures first.

Report format:
### 🔒 CHECKPOINT: QA-AUTH-002
> Status: ❌ BLOCKED
> Failures:
> - AuthServiceTests.testLogin: Expected success, got error
> - LoginViewModelTests.testValidation: Assertion failed
```

### Step 4: Handle Failures

For each failure, follow this process:

1. **Analyze the failure message**
   ```
   AuthServiceTests.testLoginWithValidCredentials FAILED
   XCTAssertNotNil failed: currentUserId was nil
   ```

2. **Identify root cause**
   - Is the test wrong? (Test expects incorrect behavior)
   - Is the implementation wrong? (Code has a bug)
   - Is setup wrong? (Mock not configured correctly)

3. **Propose a fix** (do not auto-apply)
   ```markdown
   ## Proposed Fix for AuthServiceTests.testLoginWithValidCredentials
   
   **Root Cause:** The mock session is not being returned because
   mockSupabase.signIn() returns nil instead of a valid session.
   
   **Fix:** Update MockSupabaseClient to return mockSession
   
   ```swift
   // In MockSupabaseClient.swift
   func signIn(email: String, password: String) async throws -> Session {
       if shouldFail {
           throw mockError ?? AuthError.invalidCredentials
       }
       return mockSession  // Was missing this return
   }
   ```
   
   **Action Required:** Reply "approve fix" to apply, or "skip" to investigate manually.
   ```

4. **Wait for approval before applying fix**

5. **Re-run checkpoint after fix**

### Step 5: Update Task File

Once checkpoint passes:

```markdown
### 🔒 CHECKPOINT: QA-AUTH-002
> Status: ✅ PASSED | Date: 2025-01-15
> Tests: 24 passed, 0 failed
> Coverage: AuthService 92%, LoginViewModel 88%
```

Then continue to the next task.

---

## Test Commands Reference

### Build Only (Fast Check)

```bash
xcodebuild build \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  | xcpretty
```

### Unit Tests by Feature

```bash
# Foundation
xcodebuild test -only-testing:NaarsCarsTests/Core

# Authentication
xcodebuild test -only-testing:NaarsCarsTests/Features/Authentication

# Rides
xcodebuild test -only-testing:NaarsCarsTests/Features/Rides

# Favors  
xcodebuild test -only-testing:NaarsCarsTests/Features/Favors

# Messaging
xcodebuild test -only-testing:NaarsCarsTests/Features/Messaging

# Notifications
xcodebuild test -only-testing:NaarsCarsTests/Features/Notifications
```

### Integration Tests

```bash
# Seed test data first
./QA/Scripts/seed-test-data.sh

# Run integration tests
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsIntegrationTests
```

### Snapshot Tests

```bash
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NaarsCarsSnapshotTests
```

### All Tests

```bash
xcodebuild test \
  -project NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Database Testing (Task 5.0)

⚠️ **Special Case:** Task 5.0 database tests are executed **manually in Supabase Dashboard** before app development begins. This is the only checkpoint that doesn't use Xcode tests.

### When to Execute

Complete Task 5.0 database verification **after** executing SQL scripts 001-008 and seeding test data (009), but **before** starting app development (Task 6.0+).

### SEC-DB-* Security Tests

Execute in Supabase Dashboard SQL Editor:

```sql
-- SEC-DB-001: Query profiles as unauthenticated
-- Expected: 0 rows returned (blocked by RLS)
SELECT * FROM profiles;

-- SEC-DB-002: Query profiles as unapproved user (eve@test.com)
-- First get eve's JWT from Auth, then:
-- Expected: Only eve's profile returned
SELECT * FROM profiles;

-- SEC-DB-003: Query profiles as approved user (bob@test.com)
-- Expected: All approved profiles returned
SELECT * FROM profiles WHERE approved = true;

-- SEC-DB-004: Update another user's profile
-- Expected: 0 rows updated (blocked by RLS)
UPDATE profiles SET name = 'Hacked' WHERE email = 'alice@test.com';

-- SEC-DB-005: Set own is_admin=true as non-admin
-- Expected: Blocked by trigger (no change)
UPDATE profiles SET is_admin = true WHERE email = 'bob@test.com';
```

### PERF-DB-* Performance Tests

Execute with EXPLAIN ANALYZE:

```sql
-- PERF-DB-001: Query open rides (<100ms)
EXPLAIN ANALYZE SELECT * FROM rides WHERE status = 'open';

-- PERF-DB-002: Query leaderboard (<200ms)
EXPLAIN ANALYZE SELECT * FROM get_leaderboard('year');

-- PERF-DB-003: Query conversation messages (<100ms)
EXPLAIN ANALYZE SELECT * FROM messages 
WHERE conversation_id = '[conversation_id]' 
ORDER BY created_at DESC LIMIT 100;

-- PERF-DB-005: Verify indexes exist
SELECT tablename, indexname 
FROM pg_indexes 
WHERE schemaname = 'public' 
ORDER BY tablename;
```

### EDGE-* Edge Function Tests

Execute from terminal:

```bash
# EDGE-001: Test push notification
supabase functions invoke send-push-notification \
  --body '{"token":"test_token","title":"Test","body":"Test message"}'

# EDGE-002: Test invalid token handling
supabase functions invoke send-push-notification \
  --body '{"token":"invalid_token","title":"Test","body":"Test"}'
# Then verify token was removed from push_tokens table

# EDGE-003: Test cleanup function
supabase functions invoke cleanup-tokens
```

### Recording Results

Document results in the task file:

```markdown
- [x] 5.2 🧪 SEC-DB-001: Query profiles as unauthenticated - ✅ Blocked
- [x] 5.3 🧪 SEC-DB-002: Query profiles as unapproved user - ✅ Only own profile
- [x] 5.4 🧪 SEC-DB-003: Query profiles as approved user - ✅ All approved returned
...
- [x] 5.11 🧪 PERF-DB-001: Query open rides - ✅ 42ms (<100ms)
- [x] 5.12 🧪 PERF-DB-002: Query leaderboard - ✅ 156ms (<200ms)
...
- [x] 5.20 ✅ Database setup verified - proceed to app development
```

---

## Checkpoint-to-Test Mapping

| Checkpoint ID | Test Targets | Flows Covered |
|---------------|--------------|---------------|
| Task 5.0 (Database) | Manual: SEC-DB-*, PERF-DB-*, EDGE-* | FLOW_FOUNDATION_001 (database) |
| `foundation-001` | `NaarsCarsTests/Core/Models` | FLOW_FOUNDATION_001 (models) |
| `foundation-002` | Manual: App launches, navigation works | FLOW_FOUNDATION_001 (app) |
| `foundation-003` | `NaarsCarsTests/Core/Utilities/RateLimiter*`, `CacheManager*` | FLOW_FOUNDATION_001 |
| `foundation-004` | `NaarsCarsTests/Core/Utilities/ImageCompressor*`, `Services/RealtimeManager*` | FLOW_FOUNDATION_001 |
| `foundation-final` | `NaarsCarsTests/Core` + Manual PERF-CLI-* | FLOW_FOUNDATION_001 (complete) |
| `auth-001` | `NaarsCarsTests/Core/Services/AuthService*`, `Features/Authentication/Signup*` | FLOW_AUTH_001 |
| `auth-002` | `NaarsCarsTests/Features/Authentication/Login*` | FLOW_AUTH_002 |
| `auth-003` | `NaarsCarsTests/Features/Authentication` | FLOW_AUTH_003, FLOW_AUTH_004 |
| `auth-final` | Full auth + `NaarsCarsIntegrationTests/Auth` | All FLOW_AUTH_* |
| `profile-001` | `NaarsCarsTests/Core/Services/ProfileService*`, `Utilities/Validators*` | FLOW_PROFILE_001 (service) |
| `profile-002` | `NaarsCarsTests/Features/Profile` | FLOW_PROFILE_001-002 |
| `profile-final` | Profile + `NaarsCarsSnapshotTests/Profile` | All FLOW_PROFILE_* |
| `ride-001` | `NaarsCarsTests/Core/Services/RideService*` | FLOW_RIDE_001 (service) |
| `ride-002` | `NaarsCarsTests/Features/Rides` | FLOW_RIDE_001-002 |
| `ride-final` | Rides + `NaarsCarsIntegrationTests/Rides` | FLOW_RIDE_001-005 |
| `favor-001` | `NaarsCarsTests/Core/Services/FavorService*` | FLOW_FAVOR_001 (service) |
| `favor-final` | `NaarsCarsTests/Features/Favors` | FLOW_FAVOR_001 |
| `claim-001` | `NaarsCarsTests/Core/Services/ClaimService*` | FLOW_CLAIM_001 (service) |
| `claim-final` | Claiming + `NaarsCarsIntegrationTests/Claiming` | FLOW_CLAIM_001-003 |
| `messaging-001` | `NaarsCarsTests/Core/Services/MessageService*` | FLOW_MSG_001 (service) |
| `messaging-final` | Messaging + `NaarsCarsIntegrationTests/Messaging` | FLOW_MSG_001-003 |
| `push-001` | `NaarsCarsTests/Core/Utilities/DeepLinkParser*` | FLOW_NOTIF_001 |
| `push-final` | `NaarsCarsTests/Features/PushNotifications` | FLOW_NOTIF_001 |
| `notifications-001` | `NaarsCarsTests/Core/Services/NotificationService*` | FLOW_NOTIF_002 (service) |
| `notifications-final` | `NaarsCarsTests/Features/Notifications` | FLOW_NOTIF_002 |
| `review-001` | `NaarsCarsTests/Core/Services/ReviewService*` | FLOW_REVIEW_001 (service) |
| `review-final` | `NaarsCarsTests/Features/Reviews` | FLOW_REVIEW_001 |
| `townhall-001` | `NaarsCarsTests/Core/Services/TownHallService*` | FLOW_TOWNHALL_001 (service) |
| `townhall-final` | `NaarsCarsTests/Features/TownHall` | FLOW_TOWNHALL_001 |
| `leaderboard-001` | `NaarsCarsTests/Core/Services/LeaderboardService*` | FLOW_LEADERBOARD_001 (service) |
| `leaderboard-final` | `NaarsCarsTests/Features/Leaderboards` | FLOW_LEADERBOARD_001 |
| `admin-001` | `NaarsCarsTests/Core/Services/AdminService*` | FLOW_ADMIN_001-002 (service) |
| `admin-final` | `NaarsCarsTests/Features/Admin` | FLOW_ADMIN_001-002 |
| `invite-001` | `NaarsCarsTests/Core/Services/InviteService*` | FLOW_INVITE_001 (service) |
| `invite-final` | `NaarsCarsTests/Features/Invites` | FLOW_INVITE_001 |

---

## Writing Tests During Development

### When to Write Tests

Tests should be written **as part of the task**, not after. The task list includes specific 🧪 QA sub-tasks:

```markdown
- [ ] 2.5 Implement validateInviteCode() method in AuthService
- [ ] 2.6 🧪 Write unit test for validateInviteCode() happy path
- [ ] 2.7 🧪 Write unit test for validateInviteCode() invalid code
- [ ] 2.8 🧪 Write unit test for validateInviteCode() already used
```

### Test File Creation

When creating a new test file:

```swift
import XCTest
@testable import NaarsCars

final class [ClassName]Tests: XCTestCase {
    
    // MARK: - Properties
    var sut: [ClassUnderTest]!  // System Under Test
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        sut = [ClassUnderTest]()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func test[MethodName]_[Scenario]_[ExpectedBehavior]() {
        // Given
        
        // When
        
        // Then
    }
}
```

### Test Naming Convention

```
test[Method]_[Scenario]_[Expected]

Examples:
- testLogin_WithValidCredentials_ReturnsSession
- testLogin_WithInvalidPassword_ThrowsError
- testValidateInviteCode_WhenCodeExpired_ReturnsInvalid
```

---

## Failure Handling Protocol

### DO:
- ✅ Stop and investigate failures immediately
- ✅ Read the full error message
- ✅ Check if it's a test bug or implementation bug
- ✅ Propose fixes with clear explanations
- ✅ Wait for approval before applying fixes
- ✅ Re-run tests after fixing

### DON'T:
- ❌ Skip failing tests
- ❌ Comment out failing tests
- ❌ Auto-fix without explanation
- ❌ Proceed past checkpoint with failures
- ❌ Assume flaky tests will pass next time

---

## Reporting Format

When reporting checkpoint results, use this format:

```markdown
## Checkpoint Report: QA-AUTH-002

**Executed:** 2025-01-15 14:32 PST
**Duration:** 18.4 seconds

### Results Summary
| Type | Total | Passed | Failed |
|------|-------|--------|--------|
| Unit | 24 | 24 | 0 |
| Integration | 3 | 3 | 0 |

### Flow Coverage
- [x] FLOW_AUTH_002: Login with Email/Password
- [x] FLOW_AUTH_003: Password Reset

### Status: ✅ PASSED

Ready to continue to next task.
```

Or if failed:

```markdown
## Checkpoint Report: QA-AUTH-002

**Executed:** 2025-01-15 14:32 PST
**Duration:** 12.1 seconds

### Results Summary
| Type | Total | Passed | Failed |
|------|-------|--------|--------|
| Unit | 24 | 22 | 2 |

### Failures

#### 1. AuthServiceTests.testLoginWithInvalidCredentials
**File:** `NaarsCarsTests/Core/Services/AuthServiceTests.swift:87`
**Error:** `XCTAssertEqual failed: ("networkError") is not equal to ("invalidCredentials")`
**Root Cause:** AuthService.logIn() catches network errors but doesn't distinguish from auth errors
**Proposed Fix:**
```swift
// In AuthService.swift, update logIn() error handling
catch let error as AuthError {
    throw AppError.invalidCredentials
} catch {
    throw AppError.networkError
}
```

#### 2. LoginViewModelTests.testLoadingState
**File:** `NaarsCarsTests/Features/Authentication/LoginViewModelTests.swift:45`
**Error:** `XCTAssertTrue failed: isLoading was false`
**Root Cause:** isLoading not set before async call
**Proposed Fix:**
```swift
// In LoginViewModel.swift
func login() async {
    isLoading = true  // Add this line
    defer { isLoading = false }
    // ... rest of method
}
```

### Status: ❌ BLOCKED

**Action Required:** Reply with:
- "approve all" to apply both fixes
- "approve 1" to apply first fix only
- "skip" to investigate manually
```

---

## Environment Setup

### Required Tools

```bash
# Verify Xcode
xcode-select -p
# Should show: /Applications/Xcode.app/Contents/Developer

# Verify simulator
xcrun simctl list devices | grep "iPhone 15"
# Should show available iPhone 15 simulator

# Install xcpretty for readable output (optional)
gem install xcpretty
```

### First-Time Setup

```bash
# Clone and setup
cd NaarsCars

# Create test targets if not exist
# (Usually done in Xcode: File > New > Target > Unit Testing Bundle)

# Verify test targets exist
xcodebuild -list
# Should show: NaarsCarsTests, NaarsCarsIntegrationTests, etc.
```

---

## Questions or Issues?

If you encounter issues running checkpoints:

1. **Build fails:** Fix compilation errors first
2. **Simulator not found:** Run `xcrun simctl list devices`
3. **Tests timeout:** Check network connectivity, increase timeout
4. **Flaky tests:** Document and investigate, don't ignore

Remember: Checkpoints exist to catch bugs early. A few minutes spent here saves hours later.
