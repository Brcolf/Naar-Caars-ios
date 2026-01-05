# Naar's Cars iOS - User Flow Catalog

## Overview

This document defines all user flows for the Naar's Cars iOS application. Each flow has a stable ID used for:
- Test naming and organization
- Checkpoint validation
- Coverage tracking

---

## Flow ID Format

```
FLOW_[CATEGORY]_[NUMBER]

Examples:
- FLOW_AUTH_001      → Authentication flow #1
- FLOW_RIDE_003      → Ride flow #3
- FLOW_MSG_002       → Messaging flow #2
```

---

## Phase 0: Foundation & Authentication

### FLOW_FOUNDATION_001: App Launch & Session Restoration

**Description:** User launches app, system restores session if exists. This flow also encompasses the database setup and verification that must occur before app development.

**Preconditions:**
- App installed on device
- May or may not have existing session
- **Database:** All 14 tables created with RLS enabled
- **Database:** All triggers and functions deployed
- **Database:** Seed data loaded (development only)

**Happy Path:**
```
1. App launches → Shows splash/loading
2. Check Keychain for existing session token
3a. [Has valid session] → Fetch profile → Navigate to Main Tab View
3b. [No session/expired] → Navigate to Login View
4. Complete within 1 second (PERF-CLI-001)
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Supabase unreachable | Show offline banner, retry button |
| F2 | Session exists but profile deleted | Clear session, show login |
| F3 | Network timeout | Retry with exponential backoff (max 3) |

**Database Security Tests (Task 5.0):**
| Test ID | Scenario | Expected Behavior |
|---------|----------|-------------------|
| SEC-DB-001 | Query profiles as unauthenticated | Blocked by RLS |
| SEC-DB-002 | Query profiles as unapproved user | Only own profile returned |
| SEC-DB-003 | Query profiles as approved user | All approved profiles returned |
| SEC-DB-004 | Update another user's profile | Blocked by RLS |
| SEC-DB-005 | Set own is_admin=true as non-admin | Blocked by trigger |
| SEC-DB-006 | Admin approve user | Succeeds |
| SEC-DB-007 | Non-admin approve user | Blocked by RLS |
| SEC-DB-008 | Query messages not in conversation | Blocked by RLS |
| SEC-DB-009 | Insert ride with different user_id | Blocked by RLS |
| SEC-DB-010 | Claim own ride | Blocked by constraint/RLS |

**Database Performance Tests (Task 5.0):**
| Test ID | Scenario | Target |
|---------|----------|--------|
| PERF-DB-001 | Query open rides (100 rows) | <100ms |
| PERF-DB-002 | Query leaderboard (50 users) | <200ms |
| PERF-DB-003 | Query conversation messages (100) | <100ms |
| PERF-DB-004 | Insert message with trigger | <50ms |
| PERF-DB-005 | Indexes exist for all FKs | Verified |

**Edge Function Tests (Task 5.0):**
| Test ID | Scenario | Expected Behavior |
|---------|----------|-------------------|
| EDGE-001 | Send push to valid token | 200 response, notification received |
| EDGE-002 | Send push to invalid token | Token removed from database |
| EDGE-003 | Cleanup tokens older than 90 days | Correct count returned |

**Client Performance Tests (Task 22.0):**
| Test ID | Scenario | Target |
|---------|----------|--------|
| PERF-CLI-001 | App cold launch to main screen | <1 second |
| PERF-CLI-002 | Cache hit returns immediately | <10ms |
| PERF-CLI-003 | Rate limiter blocks rapid taps | Second tap blocked |
| PERF-CLI-004 | Image compression meets limits | Output ≤ preset max size |

**Test Coverage:**
- Manual: Database security tests (SEC-DB-*)
- Manual: Database performance tests (PERF-DB-*)
- Manual: Edge Function tests (EDGE-*)
- Unit: `AppLaunchManagerTests`
- Unit: `RateLimiterTests`, `CacheManagerTests`, `ImageCompressorTests`
- Unit: `RealtimeManagerTests`
- Integration: `SessionRestorationTests`
- Manual: Client performance tests (PERF-CLI-*)

---

### FLOW_AUTH_001: Signup with Invite Code

**Description:** New user signs up using valid invite code

**Preconditions:**
- User has valid, unused invite code
- No existing account

**Happy Path:**
```
1. User on Login screen → Tap "Sign Up"
2. Enter invite code → Tap "Verify Code"
3. System validates code (exists + unused)
4. Navigate to Account Details form
5. Enter: Name, Email, Password, Car (optional)
6. Tap "Create Account"
7. System creates auth user → Creates profile (approved=false)
8. System marks invite code as used
9. Navigate to Pending Approval screen
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Invalid code | Show error "Invalid or expired invite code" |
| F2 | Email already registered | Show error "Account exists" |
| F3 | Weak password | Show inline validation error |
| F4 | Network failure during signup | Preserve form, show retry |
| F5 | Rate limited | Show "Please wait a moment" |

**Test Coverage:**
- Unit: `SignupViewModelTests`, `AuthServiceTests.testSignup*`
- Integration: `SignupFlowIntegrationTests`
- UI: `SignupFlowUITests`

---

### FLOW_AUTH_002: Login with Email/Password

**Description:** Existing user logs in

**Preconditions:**
- User has existing account

**Happy Path:**
```
1. User on Login screen
2. Enter email + password
3. Tap "Log In"
4. System authenticates with Supabase
5. Fetch user profile
6a. [approved=true] → Navigate to Main Tab View
6b. [approved=false] → Navigate to Pending Approval screen
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Wrong credentials | Show error "Invalid email or password" |
| F2 | Account disabled | Show error "Contact admin" |
| F3 | Network failure | Show retry option |
| F4 | Rate limited | Show "Please wait a moment" |

**Test Coverage:**
- Unit: `LoginViewModelTests`, `AuthServiceTests.testLogin*`
- Integration: `LoginFlowIntegrationTests`
- UI: `LoginFlowUITests`

---

### FLOW_AUTH_003: Password Reset

**Description:** User resets forgotten password

**Preconditions:**
- User has existing account, knows email

**Happy Path:**
```
1. User on Login screen → Tap "Forgot Password?"
2. Sheet opens with email input
3. Enter email → Tap "Send Reset Link"
4. System sends email via Supabase
5. Show success message (same regardless of email existence)
6. Dismiss sheet after 3 seconds
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Email not found | Show same success message (security) |
| F2 | Rate limited | Show "Try again in X minutes" |

**Test Coverage:**
- Unit: `PasswordResetViewModelTests`
- Integration: `PasswordResetIntegrationTests`

---

### FLOW_AUTH_004: Logout

**Description:** User logs out of the app

**Preconditions:**
- User is logged in

**Happy Path:**
```
1. User in Profile tab → Tap "Log Out"
2. Show confirmation dialog
3. User confirms → System clears session
4. Clear caches, unsubscribe realtime
5. Navigate to Login screen
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Network failure | Clear local session anyway |

**Test Coverage:**
- Unit: `AuthServiceTests.testLogout`
- Integration: `LogoutCleanupTests`

---

## Phase 1: Core Experience

### FLOW_PROFILE_001: View Own Profile

**Description:** User views their own profile

**Preconditions:**
- User logged in and approved

**Happy Path:**
```
1. Tap Profile tab
2. System fetches current user profile
3. Display: Avatar, Name, Email, Phone, Car, Joined date
4. Display: Invite codes section
5. Display: Reviews received
```

**Test Coverage:**
- Unit: `ProfileViewModelTests.testLoadOwnProfile`
- Snapshot: `ProfileViewSnapshots`

---

### FLOW_PROFILE_002: Edit Profile

**Description:** User edits their profile information

**Preconditions:**
- User viewing own profile

**Happy Path:**
```
1. Tap "Edit Profile" button
2. Navigate to Edit screen with pre-populated fields
3. Modify: Name, Phone, Car, Avatar
4. Tap "Save"
5. System updates profile in Supabase
6. Show success feedback (haptic + visual)
7. Navigate back to Profile view
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Validation error | Highlight invalid fields |
| F2 | Network failure | Enable retry, preserve edits |

**Test Coverage:**
- Unit: `EditProfileViewModelTests`
- Integration: `ProfileUpdateTests`

---

### FLOW_PROFILE_003: Upload Avatar

**Description:** User uploads profile picture

**Preconditions:**
- User on Edit Profile screen

**Happy Path:**
```
1. Tap avatar or "Change Photo"
2. PhotosPicker opens
3. Select image
4. Image compressed to <1MB
5. Upload to Supabase Storage (avatars bucket)
6. Update profile with new URL
7. Display new avatar
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Image too large | Compress more or show error |
| F2 | Upload fails | Show retry option |
| F3 | User cancels | No change |

**Test Coverage:**
- Unit: `ImageCompressorTests`
- Integration: `AvatarUploadTests`

---

### FLOW_RIDE_001: Create Ride Request

**Description:** User creates a new ride request

**Preconditions:**
- User logged in and approved

**Happy Path:**
```
1. Dashboard → Tap "+" or "New Request"
2. Select "Ride" type
3. Fill form: Pickup, Destination, Date, Time, Seats, Notes, Gift
4. Optionally add co-requestors
5. Tap "Post Request"
6. System creates ride in Supabase
7. Show success feedback
8. Navigate to Dashboard (ride visible)
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Missing required fields | Inline validation errors |
| F2 | Past date selected | Show error |
| F3 | Network failure | Preserve form, enable retry |

**Test Coverage:**
- Unit: `CreateRideViewModelTests`
- Integration: `RideCreationTests`
- UI: `CreateRideUITests`

---

### FLOW_RIDE_002: View Ride Details

**Description:** User views details of a ride request

**Preconditions:**
- Ride exists in system

**Happy Path:**
```
1. Tap ride card in Dashboard list
2. Navigate to Ride Detail view
3. Display: Poster info, Route, Date/Time, Seats, Notes, Gift
4. Display: Status badge, Action buttons based on role
5. Display: Q&A section
6. Display: Co-requestors if any
```

**Test Coverage:**
- Unit: `RideDetailViewModelTests`
- Snapshot: `RideDetailViewSnapshots`

---

### FLOW_RIDE_003: Edit Ride Request

**Description:** User edits their ride request

**Preconditions:**
- User is poster or co-requestor
- Ride exists

**Happy Path:**
```
1. On Ride Detail → Tap "Edit"
2. Navigate to Edit form (pre-populated)
3. Modify fields
4. Tap "Save Changes"
5. System updates ride
6. If claimed, notify claimer
7. Navigate back to Detail view
```

**Test Coverage:**
- Unit: `CreateRideViewModelTests.testEditMode`
- Integration: `RideUpdateTests`

---

### FLOW_RIDE_004: Delete Ride Request

**Description:** User deletes their ride request

**Preconditions:**
- User is poster
- Ride exists

**Happy Path:**
```
1. On Ride Detail → Tap "Delete"
2. Show confirmation dialog
3. If claimed, show enhanced warning with claimer name
4. User confirms → System deletes ride
5. If was claimed, notify claimer
6. Navigate to Dashboard
```

**Test Coverage:**
- Unit: `RideDetailViewModelTests.testDelete`
- Integration: `RideDeletionTests`

---

### FLOW_RIDE_005: Post Q&A Question

**Description:** User asks question on a ride

**Preconditions:**
- User viewing ride they don't own

**Happy Path:**
```
1. On Ride Detail → Scroll to Q&A section
2. Type question in input field
3. Tap "Post"
4. System creates Q&A entry
5. Question appears in list
6. Poster notified
```

**Test Coverage:**
- Unit: `RequestQAViewModelTests`
- Integration: `QAPostingTests`

---

### FLOW_FAVOR_001: Create Favor Request

**Description:** User creates a favor request

**Preconditions:**
- User logged in and approved

**Happy Path:**
```
1. Dashboard → Tap "+" → Select "Favor"
2. Fill form: Title, Location, Duration, Date, Requirements, Description, Gift
3. Optionally add co-requestors
4. Tap "Post Request"
5. System creates favor in Supabase
6. Navigate to Dashboard
```

**Test Coverage:**
- Unit: `CreateFavorViewModelTests`
- Integration: `FavorCreationTests`

---

### FLOW_CLAIM_001: Claim Request

**Description:** User claims an open request

**Preconditions:**
- Open ride/favor exists
- User is not poster

**Happy Path:**
```
1. On Request Detail → Tap "I Can Help!"
2. System verifies user has phone number
3a. [No phone] → Prompt to add in profile
3b. [Has phone] → Continue
4. System updates status to "confirmed"
5. System creates/adds to conversation
6. Poster notified
7. UI updates to show "Claimed by You"
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Already claimed by another | Show error, refresh |
| F2 | Network failure | Show retry |

**Test Coverage:**
- Unit: `ClaimViewModelTests`
- Integration: `ClaimFlowTests`
- UI: `ClaimFlowUITests`

---

### FLOW_CLAIM_002: Unclaim Request

**Description:** User unclaims a request

**Preconditions:**
- User has claimed request
- Status is confirmed

**Happy Path:**
```
1. On Request Detail → Tap "Unclaim"
2. Show confirmation dialog
3. User confirms
4. System resets status to "open"
5. Poster notified
6. UI updates
```

**Test Coverage:**
- Unit: `ClaimViewModelTests.testUnclaim`
- Integration: `UnclaimFlowTests`

---

### FLOW_CLAIM_003: Mark Request Complete

**Description:** Poster marks request as completed

**Preconditions:**
- User is poster
- Request is claimed

**Happy Path:**
```
1. On Request Detail → Tap "Mark Complete"
2. Show confirmation
3. User confirms
4. System updates status to "completed"
5. Review prompt appears
6. Navigate to Review flow
```

**Test Coverage:**
- Unit: `ClaimViewModelTests.testComplete`
- Integration: `CompleteFlowTests`

---

## Phase 2: Communication

### FLOW_MSG_001: Open Request Conversation

**Description:** User opens chat for a claimed request

**Preconditions:**
- Request is claimed
- User is poster or claimer

**Happy Path:**
```
1. On Request Detail → Tap "Message"
2. Navigate to Conversation view
3. Load message history
4. Mark messages as read
5. Display messages with sender info
```

**Test Coverage:**
- Unit: `ConversationViewModelTests`
- Integration: `ConversationLoadTests`

---

### FLOW_MSG_002: Send Message

**Description:** User sends a message in conversation

**Preconditions:**
- In conversation view

**Happy Path:**
```
1. Type message in input field
2. Tap send button
3. Message appears immediately (optimistic UI)
4. System sends to Supabase
5. Other participants notified
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | Network failure | Show retry, mark as unsent |
| F2 | Conversation deleted | Show error |

**Test Coverage:**
- Unit: `MessageServiceTests.testSendMessage`
- Integration: `RealtimeMessageTests`
- UI: `SendMessageUITests`

---

### FLOW_MSG_003: Start Direct Message

**Description:** User starts DM with another user

**Preconditions:**
- User viewing another user's profile

**Happy Path:**
```
1. On Profile → Tap "Message"
2. Check for existing DM conversation
3a. [Exists] → Navigate to existing conversation
3b. [New] → Create new conversation, navigate
4. Display conversation view
```

**Test Coverage:**
- Unit: `MessageServiceTests.testCreateDM`
- Integration: `DMCreationTests`

---

### FLOW_NOTIF_001: Receive Push Notification

**Description:** User receives push notification

**Preconditions:**
- App in background
- Push notifications enabled

**Happy Path:**
```
1. Remote notification received
2. System displays banner
3. User taps notification
4. App opens to relevant screen (deep link)
```

**Test Coverage:**
- Unit: `DeepLinkParserTests`
- Manual: Push notification testing

---

### FLOW_NOTIF_002: View In-App Notifications

**Description:** User views notification history

**Preconditions:**
- User logged in

**Happy Path:**
```
1. Tap bell icon in header
2. Navigate to Notifications list
3. Display notifications grouped by day
4. Pinned announcements at top
5. Tap notification → Navigate to relevant content
6. Mark as read on tap
```

**Test Coverage:**
- Unit: `NotificationListViewModelTests`
- Snapshot: `NotificationListSnapshots`

---

## Phase 3: Community

### FLOW_REVIEW_001: Leave Review After Completion

**Description:** Poster leaves review for helper

**Preconditions:**
- Request just marked complete
- User is poster

**Happy Path:**
```
1. Review sheet appears automatically
2. Display request summary
3. Select star rating (1-5)
4. Enter review text
5. Tap "Submit Review"
6. System creates review
7. System creates Town Hall post
8. Helper notified
```

**Test Coverage:**
- Unit: `LeaveReviewViewModelTests`
- Integration: `ReviewCreationTests`

---

### FLOW_TOWNHALL_001: Post to Town Hall

**Description:** User posts to community forum

**Preconditions:**
- User logged in and approved

**Happy Path:**
```
1. Town Hall tab → Tap composer
2. Enter text (max 500 chars)
3. Optionally attach image
4. Tap "Post"
5. Post appears in feed
6. Real-time update for others
```

**Test Coverage:**
- Unit: `TownHallViewModelTests`
- Integration: `TownHallPostTests`

---

### FLOW_LEADERBOARD_001: View Leaderboard

**Description:** User views community leaderboard

**Preconditions:**
- User logged in

**Happy Path:**
```
1. Leaderboard tab
2. Select time period (Year/Quarter/Month)
3. Display ranked users with stats
4. Highlight current user's position
```

**Test Coverage:**
- Unit: `LeaderboardViewModelTests`
- Snapshot: `LeaderboardViewSnapshots`

---

## Phase 4: Administration

### FLOW_ADMIN_001: Approve Pending User

**Description:** Admin approves pending user

**Preconditions:**
- User is admin

**Happy Path:**
```
1. Admin Panel → View pending users
2. Tap "Approve" on user
3. Show confirmation
4. System sets approved=true
5. User notified
6. User removed from pending list
```

**Test Coverage:**
- Unit: `AdminViewModelTests.testApproveUser`
- Integration: `UserApprovalTests`

---

### FLOW_ADMIN_002: Send Broadcast

**Description:** Admin sends announcement

**Preconditions:**
- User is admin

**Happy Path:**
```
1. Admin Panel → Compose announcement
2. Enter title + message
3. Toggle "Pin to notifications"
4. Tap "Send"
5. Push sent to all users
6. If pinned, added to notification feeds
```

**Test Coverage:**
- Unit: `AdminViewModelTests.testSendBroadcast`
- Integration: `BroadcastTests`

---

### FLOW_INVITE_001: Generate Invite Code

**Description:** User generates new invite code

**Preconditions:**
- User logged in and approved

**Happy Path:**
```
1. Profile → Invite section → Tap "Generate Code"
2. System creates new unique code
3. Code appears in list
4. Copy/share options available
```

**Test Coverage:**
- Unit: `InviteCodeGeneratorTests`
- Integration: `InviteCodeCreationTests`

---

## Flow Coverage Matrix

Use this matrix to track test coverage status:

| Flow ID | Unit | Integration | UI | Snapshot | Status |
|---------|------|-------------|-----|----------|--------|
| FLOW_FOUNDATION_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_AUTH_001 | ⏳ | ⏳ | ⏳ | ⏳ | Not Started |
| FLOW_AUTH_002 | ⏳ | ⏳ | ⏳ | ⏳ | Not Started |
| FLOW_AUTH_003 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_AUTH_004 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_PROFILE_001 | ⏳ | - | - | ⏳ | Not Started |
| FLOW_PROFILE_002 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_PROFILE_003 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_RIDE_001 | ⏳ | ⏳ | ⏳ | - | Not Started |
| FLOW_RIDE_002 | ⏳ | - | - | ⏳ | Not Started |
| FLOW_RIDE_003 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_RIDE_004 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_RIDE_005 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_FAVOR_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_CLAIM_001 | ⏳ | ⏳ | ⏳ | - | Not Started |
| FLOW_CLAIM_002 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_CLAIM_003 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_MSG_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_MSG_002 | ⏳ | ⏳ | ⏳ | - | Not Started |
| FLOW_MSG_003 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_NOTIF_001 | ⏳ | - | - | - | Not Started |
| FLOW_NOTIF_002 | ⏳ | - | - | ⏳ | Not Started |
| FLOW_REVIEW_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_TOWNHALL_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_LEADERBOARD_001 | ⏳ | - | - | ⏳ | Not Started |
| FLOW_ADMIN_001 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_ADMIN_002 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_INVITE_001 | ⏳ | ⏳ | - | - | Not Started |

**Legend:**
- ⏳ Not Started
- 🟡 In Progress  
- ✅ Complete
- ❌ Failing
- `-` Not Applicable
