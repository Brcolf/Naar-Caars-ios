# Naars Cars iOS - Device UI Test Plan (Gemini Handoff)

## Overview
This document is a complete UI test plan for Naars Cars, intended for a new agent to execute on a **real device (BCSPH)** with full device access. It includes:
- Tests already run and their results
- Tests prepared in the current XCUITest suite
- Additional tests that still need design or implementation for exhaustive coverage
- Exact commands to run on device

## Device Access & Preconditions
- **Device:** BCSPH (iOS device connected to Xcode)
- **UDID:** `00008150-000C155E1ED8401C`
- **Device must be unlocked** for UI automation
- **Developer Mode** and **UI Automation** enabled in iOS Settings
- **Trust this computer** accepted on device
- **Xcode version:** Use the current installed `/Applications/Xcode.app`
- **Project path:** `/Users/bcolf/Documents/naars-cars-ios`

## Test Accounts
Use these accounts for login:
- `alice@test.com` / `TestPassword123!`
- `brcolford@gmail.com` / `TestPassword123!`
- `brendancolford@comcast.net` / `TestPassword123!`

## How to Run Tests on Device
Run from repo root:
```
cd /Users/bcolf/Documents/naars-cars-ios
xcodebuild -project NaarsCars/NaarsCars.xcodeproj \
  -scheme NaarsCars \
  -configuration Debug \
  -destination 'id=00008150-000C155E1ED8401C' \
  -allowProvisioningUpdates \
  test -only-testing:NaarsCarsUITests
```

If UI automation fails, verify:
- Device stays unlocked
- Developer Mode and UI Automation toggles are enabled
- No lock screen appears mid‑test

## Tests Already Run (Results)
### 1) Previous expanded suite (passed)
`xcodebuild test -only-testing:NaarsCarsUITests`  
Result: **TEST SUCCEEDED** (included Requests, Messaging, Notifications, Community, Profile, Launch tests).

### 2) Latest expanded suite with multi‑user test (failed)
Run: `xcodebuild test -only-testing:NaarsCarsUITests`  
Result: **TEST FAILED**  
Failure: `testMultiUserCreateClaimAndMessaging`  
Assertion at `NaarsCarsUITests.swift:357`:
```
XCTAssertTrue(input.waitForExistence(timeout: 10))
```
Meaning: message input didn’t appear after navigation (likely the conversation did not open or load in time).

## Tests Prepared in Code (Current XCUITest Suite)
File: `NaarsCars/NaarsCarsUITests/NaarsCarsUITests.swift`

### Existing basic flows
- `testRequestsDashboardFlow`
  - Requests filters, open card, create ride/favor (cancel), scroll
- `testMessagingFlow`
  - Search, open conversation, scroll, send message
- `testNotificationsFlow`
  - Open notifications via bell, tap row, refresh
- `testCommunityFlow`
  - Toggle Town Hall / Leaderboard, scroll
- `testProfileFlow`
  - Open settings, edit profile (cancel)
- `testLaunchPerformance`

### New deeper flows added
- `testMultiUserCreateClaimAndMessaging`
  - Alice creates ride + favor
  - Alice creates DM to `brcolford@gmail.com`
  - Alice creates group message with `brcolford@gmail.com` + `brendancolford@comcast.net`
  - Alice signs out
  - `brcolford@gmail.com` signs in, claims ride/favor, verifies messages
  - Signs out
  - `brendancolford@comcast.net` signs in, verifies group message
  - **Failure currently at message input not appearing**

- `testSignupWithRegularAndBulkInvites`
  - Uses **Admin Invite** flow to generate regular + bulk codes
  - Signs out and completes signup for a new user with each code
  - Verifies **Pending Approval** screen and returns to login
  - Requires **admin access** for account used to generate invites

## Accessibility Identifiers Added (Key for UI Tests)
These IDs were added to stabilize UI automation:
- Login: `login.email`, `login.password`, `login.submit`, `login.signup`
- Requests: `requests.filter.*`, `requests.card`, `requests.createMenu`
- Create Ride: `createRide.pickup`, `createRide.destination`, `createRide.notes`, `createRide.gift`, `createRide.post`, `createRide.cancel`, `createRide.participants`
- Create Favor: `createFavor.title`, `createFavor.description`, `createFavor.location`, `createFavor.duration`, `createFavor.hasTime`, `createFavor.requirements`, `createFavor.gift`, `createFavor.post`, `createFavor.cancel`
- Claiming: `claim.button.*`, `claim.confirm`, `claim.cancel`, `unclaim.confirm`, `unclaim.cancel`, `complete.confirm`, `complete.cancel`
- Messaging: `messages.conversation.row`, `messages.newMessage`, `userSearch.searchField`, `userSearch.row.<email>`, `userSearch.done`, `message.input`, `message.send`, `messages.thread.scroll`, `messages.scrollToBottom`
- Notifications: `bell.button`, `notifications.row`
- Profile: `profile.settings`, `profile.edit`, `profile.edit.cancel`, `profile.signout`, `profile.adminPanel`, `profile.notifications`
- Signup: `signup.inviteCode`, `signup.inviteNext`, `signup.method.email`, `signup.name`, `signup.email`, `signup.password`, `signup.car`, `signup.createAccount`
- Guidelines: `guidelines.scroll`, `guidelines.accept`
- Pending approval: `pendingApproval.screen`, `pendingApproval.returnLogin`, `pendingApproval.enableNotifications`
- Admin: `admin.inviteCodes`, `admin.invite.regular`, `admin.invite.bulk`, `admin.invite.code`, `admin.invite.copy`, `admin.invite.share`, `admin.bulk.generate`, `admin.bulk.cancel`
- Invites: `invite.statement`, `invite.generate`, `invite.generatedCode`, `invite.copy`, `invite.share`, `invite.done`, `invite.cancel`

## What Still Needs To Be Designed / Implemented
Add new UI tests to cover:

### Rides & Favors
- Claim / unclaim / mark complete flows fully end‑to‑end
- Validate auto‑dismiss of claim/unclaim/complete sheets
- Message all participants from request detail
- Add participants flow (UserSearchView)
- Edit ride/favor and verify saved changes
- Delete ride/favor (confirm alert)
- Open maps from ride/favor detail (Apple/Google Maps fallback)

### Messaging
- Send image message (photo picker)
- Send audio message (record, stop, send)
- Send location message (location picker)
- Long‑press message → reactions / report / copy
- Reply to message & reply preview navigation
- Group chat naming + group image (MessageDetailsPopup)
- Read receipts and typing indicator display

### Notifications
- Navigate from notification → request detail (deep link)
- Verify notifications auto‑dismiss when requested
- Badge counts update after viewing

### Profile / Settings
- Toggle notifications preferences & biometrics
- Change avatar (Photos picker + permission handling)
- Edit name/phone/car and save (and phone disclosure flow)
- Logout confirmation and session reset

### Community / Town Hall
- Create post, vote, comment, report
- Switch tabs rapidly, check state persistence

### Admin
- Broadcast announcement flow
- Pending users approve/deny
- User management actions

### Signup / Invite
- Deep link `naarscars.com/signup?code=...`
- Invalid invite code handling
- Apple sign‑up path (if possible on device)

### App‑Level
- App relaunch, background/foreground
- Network offline fallback (if feasible via device settings)

## Known Issues / Suggestions
- **Multi‑user messaging failure**: message input not visible after navigation.
  - Add robust waits for conversation title or message list to appear before typing.
  - Consider adding a `messages.thread.inputBar` identifier.
  - Ensure UserSearch selection successfully navigates to conversation (may need explicit wait for navigation).

## Gemini 3 Flash Prompt
Copy/paste this prompt to Gemini 3 Flash:

```
You are a code‑agent in Cursor. Follow the test plan in /Users/bcolf/Documents/naars-cars-ios/TEST_PLAN_GEMINI_HANDOFF.md.
Run the UI tests on device BCSPH (UDID 00008150-000C155E1ED8401C) using xcodebuild. 
Fix any failing tests and rerun until they pass. 
Prioritize multi‑user create/claim/messaging and signup with regular/bulk invite flows, then implement the remaining unbuilt tests in the plan. 
Always report results and where failures occur.
```



