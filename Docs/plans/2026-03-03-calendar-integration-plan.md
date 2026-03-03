# Calendar Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to add confirmed requests to their iOS Calendar with a 1-hour reminder, via in-app prompt and push notification action.

**Architecture:** Two entry points to the same CalendarService: (1) an in-app alert shown when viewing a confirmed request (up to 2 offers, tracked locally), and (2) an "Add to Calendar" action on the push notification sent to the requestor when their request is claimed. A shared CalendarOfferTracker (UserDefaults) prevents duplicate offers across both paths.

**Tech Stack:** EventKit, UserNotifications, Supabase RPC (queue_push_notification), Edge Function update

---

## Context

### Key Files Reference
| File | Role |
|------|------|
| `NaarsCars/Core/Models/Ride.swift` | Ride model (date, time, pickup, destination) |
| `NaarsCars/Core/Models/Favor.swift` | Favor model (date, time, location, title) |
| `NaarsCars/Core/Models/RequestItem.swift` | Unified enum with `eventTime` computed property |
| `NaarsCars/Core/Services/ClaimService.swift` | Handles claim/unclaim/complete transitions |
| `NaarsCars/Core/Services/PushNotificationService.swift` | Manages APNs categories and actions |
| `NaarsCars/App/AppDelegate.swift` | Handles notification tap actions |
| `NaarsCars/Features/Rides/Views/RideDetailView.swift` | Ride detail UI |
| `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift` | Ride detail state |
| `NaarsCars/Features/Favors/Views/FavorDetailView.swift` | Favor detail UI |
| `NaarsCars/Features/Favors/ViewModels/FavorDetailViewModel.swift` | Favor detail state |
| `NaarsCars/Info.plist` | App permissions (needs calendar key) |
| `supabase/functions/send-notification/index.ts` | Edge Function for APNs push |
| `supabase/functions/_shared/notificationTypes.ts` | Notification type constants |

### Existing Patterns
- **UserDefaults flag tracking:** `EditProfileViewModel.swift` uses `UserDefaults.standard.bool(forKey:)` for `hasShownPhoneDisclosure`
- **Supabase RPC calls:** `supabase.rpc("function_name", params: [...]).execute()`
- **Notification categories:** `PushNotificationService.setupNotificationCategories()` registers UNNotificationCategory with actions
- **Action handling:** `AppDelegate.userNotificationCenter(_:didReceive:)` switches on `response.actionIdentifier`
- **Sheet/alert pattern:** Detail views use `@State var showX: Bool` + `.alert(isPresented:)` modifiers
- **Singleton services:** `ClaimService.shared`, `PushNotificationService.shared`

---

## Task 1: Create CalendarService

**Files:**
- Create: `NaarsCars/Core/Services/CalendarService.swift`

**Step 1: Create CalendarService.swift**

```swift
//
//  CalendarService.swift
//  NaarsCars
//
//  Service for EventKit calendar operations
//

import EventKit
import Foundation

/// Service for creating calendar events from confirmed requests
@MainActor
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    /// Request calendar access. Returns true if granted.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                AppLogger.error("calendar", "Failed to request calendar access: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        AppLogger.error("calendar", "Failed to request calendar access: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Check if calendar access is currently authorized
    var hasAccess: Bool {
        if #available(iOS 17.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    /// Create a calendar event for a ride request
    /// - Returns: The event identifier if created successfully
    func createEvent(
        title: String,
        location: String?,
        startDate: Date,
        endDate: Date?,
        notes: String?
    ) async -> String? {
        // Request access if not already granted
        guard hasAccess || await requestAccess() else {
            AppLogger.info("calendar", "Calendar access denied")
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.location = location
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Add 1-hour reminder
        let alarm = EKAlarm(relativeOffset: -3600)
        event.addAlarm(alarm)

        do {
            try eventStore.save(event, span: .thisEvent)
            AppLogger.info("calendar", "Calendar event created: \(event.eventIdentifier ?? "unknown")")
            return event.eventIdentifier
        } catch {
            AppLogger.error("calendar", "Failed to create calendar event: \(error)")
            return nil
        }
    }

    /// Create a calendar event from a Ride
    func createEventForRide(_ ride: Ride) async -> String? {
        let eventTime = RequestItem.ride(ride).eventTime
        return await createEvent(
            title: "Ride: \(ride.pickup) → \(ride.destination)",
            location: ride.pickup,
            startDate: eventTime,
            endDate: nil,
            notes: ride.notes
        )
    }

    /// Create a calendar event from a Favor
    func createEventForFavor(_ favor: Favor) async -> String? {
        let eventTime = RequestItem.favor(favor).eventTime
        let durationInterval: TimeInterval = {
            switch favor.duration {
            case .underHour: return 3600
            case .coupleHours: return 7200
            case .coupleDays: return 86400
            case .notSure: return 3600
            }
        }()
        return await createEvent(
            title: "Favor: \(favor.title)",
            location: favor.location,
            startDate: eventTime,
            endDate: eventTime.addingTimeInterval(durationInterval),
            notes: favor.description
        )
    }

    /// Create a calendar event from push notification data (when user taps "Add to Calendar" action)
    func createEventFromPushData(_ userInfo: [AnyHashable: Any]) async -> String? {
        guard let title = userInfo["event_title"] as? String,
              let dateString = userInfo["event_date"] as? String else {
            AppLogger.error("calendar", "Missing event data in push payload")
            return nil
        }

        let formatter = ISO8601DateFormatter()
        guard let startDate = formatter.date(from: dateString) else {
            AppLogger.error("calendar", "Invalid event date in push payload: \(dateString)")
            return nil
        }

        let location = userInfo["event_location"] as? String
        let notes = userInfo["event_notes"] as? String

        return await createEvent(
            title: title,
            location: location,
            startDate: startDate,
            endDate: nil,
            notes: notes
        )
    }
}
```

**Step 2: Verify it compiles (after adding to Xcode project in Task 8)**

---

## Task 2: Create CalendarOfferTracker

**Files:**
- Create: `NaarsCars/Core/Utilities/CalendarOfferTracker.swift`

**Step 1: Create CalendarOfferTracker.swift**

```swift
//
//  CalendarOfferTracker.swift
//  NaarsCars
//
//  Tracks calendar event offer state per request to limit prompts
//

import Foundation

/// Tracks how many times a user has been offered to add a request to their calendar,
/// and whether they accepted. Persists via UserDefaults.
final class CalendarOfferTracker {

    static let shared = CalendarOfferTracker()

    private let defaults = UserDefaults.standard
    private let storageKey = "calendarOfferState"
    private let maxDismissals = 2

    private init() {}

    // MARK: - State

    private struct OfferState: Codable {
        var dismissCount: Int = 0
        var eventCreated: Bool = false
    }

    private func key(requestType: String, requestId: UUID) -> String {
        "\(requestType)_\(requestId.uuidString)"
    }

    private func loadState() -> [String: OfferState] {
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode([String: OfferState].self, from: data) else {
            return [:]
        }
        return state
    }

    private func saveState(_ state: [String: OfferState]) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - Public API

    /// Whether we should offer the calendar event for this request
    func shouldOffer(requestType: String, requestId: UUID) -> Bool {
        let k = key(requestType: requestType, requestId: requestId)
        let allState = loadState()
        guard let state = allState[k] else { return true } // Never offered
        return !state.eventCreated && state.dismissCount < maxDismissals
    }

    /// Record that the user dismissed the calendar offer
    func recordDismissal(requestType: String, requestId: UUID) {
        let k = key(requestType: requestType, requestId: requestId)
        var allState = loadState()
        var state = allState[k] ?? OfferState()
        state.dismissCount += 1
        allState[k] = state
        saveState(allState)
    }

    /// Record that the user created the calendar event
    func recordEventCreated(requestType: String, requestId: UUID) {
        let k = key(requestType: requestType, requestId: requestId)
        var allState = loadState()
        var state = allState[k] ?? OfferState()
        state.eventCreated = true
        allState[k] = state
        saveState(allState)
    }

    /// Check if an event was already created for this request
    func eventAlreadyCreated(requestType: String, requestId: UUID) -> Bool {
        let k = key(requestType: requestType, requestId: requestId)
        return loadState()[k]?.eventCreated ?? false
    }
}
```

**Step 2: Verify it compiles (after adding to Xcode project in Task 8)**

---

## Task 3: Add NSCalendarsFullAccessUsageDescription to Info.plist

**Files:**
- Modify: `NaarsCars/Info.plist`

**Step 1: Add calendar permission key**

Add these keys before the closing `</dict>`:

```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>Naar's Cars adds confirmed requests to your calendar with a reminder so you don't forget.</string>
<key>NSCalendarsUsageDescription</key>
<string>Naar's Cars adds confirmed requests to your calendar with a reminder so you don't forget.</string>
```

Note: `NSCalendarsFullAccessUsageDescription` is for iOS 17+. `NSCalendarsUsageDescription` is the fallback for iOS 16 and earlier.

**Step 2: Commit**

```bash
git add NaarsCars/Info.plist
git commit -m "feat: add calendar permission description to Info.plist"
```

---

## Task 4: Integrate Calendar Offer into RideDetailView

**Files:**
- Modify: `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`

**Step 1: Add calendar state to RideDetailViewModel**

Add new published property and methods to `RideDetailViewModel`:

```swift
// Add property alongside existing @Published vars (after line ~20)
@Published var showCalendarOffer: Bool = false

// Add these methods at the end of the class (before closing brace)

/// Check and trigger calendar offer for confirmed rides
func checkCalendarOffer() {
    guard let ride = ride,
          ride.status == .confirmed,
          let currentUserId = authService.currentUserId else { return }

    // Offer to claimer or participants (anyone involved)
    let isClaimer = ride.claimedBy == currentUserId
    let isParticipant = ride.participants?.contains(where: { $0.id == currentUserId }) ?? false
    let isPoster = ride.userId == currentUserId
    guard isClaimer || isParticipant || isPoster else { return }

    // Check tracker
    guard CalendarOfferTracker.shared.shouldOffer(requestType: "ride", requestId: ride.id) else { return }

    // Don't offer for past events
    let eventTime = RequestItem.ride(ride).eventTime
    guard eventTime > Date() else { return }

    // Brief delay so the view settles before showing alert
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showCalendarOffer = true
    }
}

/// Handle user accepting the calendar offer
func acceptCalendarOffer() async {
    guard let ride = ride else { return }
    let eventId = await CalendarService.shared.createEventForRide(ride)
    if eventId != nil {
        CalendarOfferTracker.shared.recordEventCreated(requestType: "ride", requestId: ride.id)
    }
}

/// Handle user dismissing the calendar offer
func dismissCalendarOffer() {
    guard let ride = ride else { return }
    CalendarOfferTracker.shared.recordDismissal(requestType: "ride", requestId: ride.id)
}
```

**Step 2: Add calendar alert to RideDetailView**

Add `.alert` modifier to RideDetailView's body, near the other `.alert` and `.sheet` modifiers (after the existing delete alert around line ~101):

```swift
.alert("Add to Calendar?", isPresented: $viewModel.showCalendarOffer) {
    Button("Add to Calendar") {
        Task { await viewModel.acceptCalendarOffer() }
    }
    Button("Not Now", role: .cancel) {
        viewModel.dismissCalendarOffer()
    }
} message: {
    if let ride = viewModel.ride {
        Text("Add this ride to your calendar with a 1-hour reminder?")
    }
}
```

Add the calendar check call in the `.task` modifier, after `loadRide` completes. Find the existing `.task { await viewModel.loadRide(id: rideId) }` and change it to:

```swift
.task {
    await viewModel.loadRide(id: rideId)
    viewModel.checkCalendarOffer()
}
```

**Step 3: Build and test manually**

Open the app, navigate to a confirmed ride where you are a participant/claimer. Verify the alert appears. Dismiss it, navigate away and back — verify it appears again (2nd offer). Dismiss again, navigate away and back — verify it does NOT appear (maxed out). Accept on another request — verify it does NOT appear again for that request.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift NaarsCars/Features/Rides/Views/RideDetailView.swift
git commit -m "feat: add calendar offer to ride detail view (up to 2 offers per request)"
```

---

## Task 5: Integrate Calendar Offer into FavorDetailView

**Files:**
- Modify: `NaarsCars/Features/Favors/ViewModels/FavorDetailViewModel.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`

**Step 1: Add calendar state to FavorDetailViewModel**

Identical pattern to Task 4 but for Favor. Add to `FavorDetailViewModel`:

```swift
// Add property alongside existing @Published vars (after line ~20)
@Published var showCalendarOffer: Bool = false

// Add these methods at the end of the class (before closing brace)

/// Check and trigger calendar offer for confirmed favors
func checkCalendarOffer() {
    guard let favor = favor,
          favor.status == .confirmed,
          let currentUserId = authService.currentUserId else { return }

    let isClaimer = favor.claimedBy == currentUserId
    let isParticipant = favor.participants?.contains(where: { $0.id == currentUserId }) ?? false
    let isPoster = favor.userId == currentUserId
    guard isClaimer || isParticipant || isPoster else { return }

    guard CalendarOfferTracker.shared.shouldOffer(requestType: "favor", requestId: favor.id) else { return }

    let eventTime = RequestItem.favor(favor).eventTime
    guard eventTime > Date() else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showCalendarOffer = true
    }
}

func acceptCalendarOffer() async {
    guard let favor = favor else { return }
    let eventId = await CalendarService.shared.createEventForFavor(favor)
    if eventId != nil {
        CalendarOfferTracker.shared.recordEventCreated(requestType: "favor", requestId: favor.id)
    }
}

func dismissCalendarOffer() {
    guard let favor = favor else { return }
    CalendarOfferTracker.shared.recordDismissal(requestType: "favor", requestId: favor.id)
}
```

**Step 2: Add calendar alert to FavorDetailView**

Add `.alert` modifier near other alerts (after the existing delete alert around line ~85):

```swift
.alert("Add to Calendar?", isPresented: $viewModel.showCalendarOffer) {
    Button("Add to Calendar") {
        Task { await viewModel.acceptCalendarOffer() }
    }
    Button("Not Now", role: .cancel) {
        viewModel.dismissCalendarOffer()
    }
} message: {
    Text("Add this favor to your calendar with a 1-hour reminder?")
}
```

Update the `.task` modifier:

```swift
.task {
    await viewModel.loadFavor(id: favorId)
    viewModel.checkCalendarOffer()
}
```

**Step 3: Build and verify**

**Step 4: Commit**

```bash
git add NaarsCars/Features/Favors/ViewModels/FavorDetailViewModel.swift NaarsCars/Features/Favors/Views/FavorDetailView.swift
git commit -m "feat: add calendar offer to favor detail view (up to 2 offers per request)"
```

---

## Task 6: Queue Push Notification on Claim

This makes claimed requests send a **push notification** to the poster (requestor), not just an in-app notification.

**Files:**
- Modify: `NaarsCars/Core/Services/ClaimService.swift`

**Step 1: Add push notification queueing to ClaimService**

After the `createClaimNotification` call in `claimRequest()` (around line 101), add a call to queue a push notification. Add this method to ClaimService:

```swift
/// Queue a push notification with calendar event data when request is claimed
private func queueClaimPushNotification(
    requestType: String,
    requestId: UUID,
    posterId: UUID,
    claimerId: UUID
) async {
    do {
        // Get claimer profile for the push body
        let claimerProfile = try await ProfileService.shared.fetchProfile(userId: claimerId)

        let title = requestType == "ride" ? "Ride Claimed!" : "Favor Claimed!"
        let body = "\(claimerProfile.name) is helping with your \(requestType) request"

        // Fetch request details for calendar event data in the push payload
        let tableName = requestType == "ride" ? "rides" : "favors"
        let selectFields = requestType == "ride"
            ? "date, time, pickup, destination, notes"
            : "date, time, location, title, description, duration"

        let response = try await supabase
            .from(tableName)
            .select(selectFields)
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()

        var eventData: [String: AnyCodable] = [
            "\(requestType)_id": AnyCodable(requestId.uuidString)
        ]

        // Parse response and build event data for calendar creation on the client
        if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
            if let dateStr = json["date"] as? String,
               let timeStr = json["time"] as? String {
                // Combine date + time into ISO8601 for the push payload
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                if let date = dateFormatter.date(from: dateStr) {
                    let timeParts = timeStr.split(separator: ":")
                    if timeParts.count >= 2,
                       let hour = Int(timeParts[0]),
                       let minute = Int(timeParts[1]) {
                        var calendar = Calendar.current
                        calendar.timeZone = .current
                        var components = calendar.dateComponents([.year, .month, .day], from: date)
                        components.hour = hour
                        components.minute = minute
                        if let eventDate = calendar.date(from: components) {
                            let isoFormatter = ISO8601DateFormatter()
                            eventData["event_date"] = AnyCodable(isoFormatter.string(from: eventDate))
                        }
                    }
                }
            }

            if requestType == "ride" {
                let pickup = json["pickup"] as? String ?? ""
                let destination = json["destination"] as? String ?? ""
                eventData["event_title"] = AnyCodable("Ride: \(pickup) → \(destination)")
                eventData["event_location"] = AnyCodable(pickup)
                eventData["event_notes"] = AnyCodable(json["notes"] as? String)
            } else {
                eventData["event_title"] = AnyCodable("Favor: \(json["title"] as? String ?? "")")
                eventData["event_location"] = AnyCodable(json["location"] as? String)
                eventData["event_notes"] = AnyCodable(json["description"] as? String)
            }
        }

        // Convert eventData to JSONB-compatible format
        let dataJson = try JSONSerialization.data(
            withJSONObject: eventData.mapValues { $0.value ?? NSNull() }
        )
        let dataString = String(data: dataJson, encoding: .utf8) ?? "{}"

        // Call queue_push_notification RPC
        try await supabase.rpc("queue_push_notification", params: [
            "p_recipient_user_id": AnyCodable(posterId.uuidString),
            "p_notification_type": AnyCodable(requestType == "ride" ? "ride_claimed" : "favor_claimed"),
            "p_title": AnyCodable(title),
            "p_body": AnyCodable(body),
            "p_data": AnyCodable(dataString)
        ]).execute()

        AppLogger.info("claims", "Queued claim push notification for poster \(posterId)")
    } catch {
        // Non-fatal: push notification failure shouldn't break the claim flow
        AppLogger.error("claims", "Failed to queue claim push notification: \(error)")
    }
}
```

**Step 2: Call the new method in claimRequest()**

In `claimRequest()`, after the `createClaimNotification` call (line ~101), add:

```swift
// Queue push notification for poster (with calendar event data)
await queueClaimPushNotification(
    requestType: requestType,
    requestId: requestId,
    posterId: posterId,
    claimerId: claimerId
)
```

**Important:** Note the `await` without `try` — this is intentional. The method catches its own errors so push failure doesn't break the claim flow.

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ClaimService.swift
git commit -m "feat: queue push notification to poster when request is claimed"
```

---

## Task 7: Add APNs Category for Claimed Requests + Handle Action

**Files:**
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift` (lines 15-30, 89-153)
- Modify: `NaarsCars/App/AppDelegate.swift` (lines 171-206)
- Modify: `supabase/functions/send-notification/index.ts` (lines 46-50, 312-319)

### Step 1: Add new action and category to PushNotificationService

In `PushNotificationService.swift`, add a new action and category to the enums:

```swift
// Add to NotificationAction enum (around line 22):
case addToCalendar = "ADD_TO_CALENDAR"

// Add to NotificationCategory enum (around line 29):
case requestClaimed = "REQUEST_CLAIMED"
```

In `setupNotificationCategories()`, add the new category (before the `setNotificationCategories` call around line 146):

```swift
// Claimed Request category with Add to Calendar action
let addToCalendarAction = UNNotificationAction(
    identifier: NotificationAction.addToCalendar.rawValue,
    title: "Add to Calendar",
    options: [.foreground]
)

let viewClaimedRequestAction = UNNotificationAction(
    identifier: NotificationAction.viewRequest.rawValue,
    title: "View Details",
    options: [.foreground]
)

let requestClaimedCategory = UNNotificationCategory(
    identifier: NotificationCategory.requestClaimed.rawValue,
    actions: [addToCalendarAction, viewClaimedRequestAction],
    intentIdentifiers: [],
    options: []
)
```

Add `requestClaimedCategory` to the `setNotificationCategories` array:

```swift
notificationCenter.setNotificationCategories([
    completionCategory,
    messageCategory,
    newRequestCategory,
    requestClaimedCategory
])
```

### Step 2: Handle the calendar action in AppDelegate

In `AppDelegate.swift`, in the `userNotificationCenter(_:didReceive:)` method, add a new case in the action switch block (around line 196, after the `viewRequest` case):

```swift
case NotificationAction.addToCalendar.rawValue:
    // Add to Calendar action from claimed request notification
    Task { @MainActor in
        let requestType = userInfo["type"] as? String ?? ""
        let requestId: UUID? = {
            if let id = userInfo["ride_id"] as? String { return UUID(uuidString: id) }
            if let id = userInfo["favor_id"] as? String { return UUID(uuidString: id) }
            return nil
        }()

        let eventId = await CalendarService.shared.createEventFromPushData(userInfo)
        if let eventId, let requestId {
            let rType = userInfo["ride_id"] != nil ? "ride" : "favor"
            CalendarOfferTracker.shared.recordEventCreated(requestType: rType, requestId: requestId)
        }

        // Also navigate to the request detail
        let deepLink = DeepLinkParser.parse(userInfo: userInfo)
        self.handleDeepLink(deepLink, userInfo: userInfo)
    }
```

### Step 3: Update Edge Function to map claimed types to new category

In `supabase/functions/send-notification/index.ts`, update the category mapping:

Add to the `NOTIFICATION_CATEGORIES` constant (around line 46):

```typescript
const NOTIFICATION_CATEGORIES: Record<string, string> = {
  [NOTIFICATION_TYPES.COMPLETION_REMINDER]: 'COMPLETION_REMINDER',
  [NOTIFICATION_TYPES.MESSAGE]: 'MESSAGE',
  new_request: 'NEW_REQUEST',
  request_claimed: 'REQUEST_CLAIMED',
}
```

Add to the category assignment logic in `sendPushToUser` (around line 317):

```typescript
} else if (notificationType === NOTIFICATION_TYPES.RIDE_CLAIMED || notificationType === NOTIFICATION_TYPES.FAVOR_CLAIMED) {
  apnsPayload.aps.category = NOTIFICATION_CATEGORIES.request_claimed
}
```

The full if/else block should read:

```typescript
// Add category for actionable notifications
if (notificationType === NOTIFICATION_TYPES.COMPLETION_REMINDER) {
  apnsPayload.aps.category = NOTIFICATION_CATEGORIES[NOTIFICATION_TYPES.COMPLETION_REMINDER]
} else if (notificationType === NOTIFICATION_TYPES.MESSAGE) {
  apnsPayload.aps.category = NOTIFICATION_CATEGORIES[NOTIFICATION_TYPES.MESSAGE]
} else if (notificationType === NOTIFICATION_TYPES.NEW_RIDE || notificationType === NOTIFICATION_TYPES.NEW_FAVOR) {
  apnsPayload.aps.category = NOTIFICATION_CATEGORIES.new_request
} else if (notificationType === NOTIFICATION_TYPES.RIDE_CLAIMED || notificationType === NOTIFICATION_TYPES.FAVOR_CLAIMED) {
  apnsPayload.aps.category = NOTIFICATION_CATEGORIES.request_claimed
}
```

### Step 4: Deploy the updated Edge Function

```bash
# From project root
supabase functions deploy send-notification
```

Or use the Supabase MCP tool to deploy.

### Step 5: Commit

```bash
git add NaarsCars/Core/Services/PushNotificationService.swift NaarsCars/App/AppDelegate.swift supabase/functions/send-notification/index.ts
git commit -m "feat: add Add to Calendar action on claimed request push notifications"
```

---

## Task 8: Add New Files to Xcode Project + Build Verification

**Files:**
- Modify: `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Step 1: Add CalendarService.swift and CalendarOfferTracker.swift to the Xcode project**

Open the Xcode project and add both files:
- `NaarsCars/Core/Services/CalendarService.swift` → add to `Core/Services` group
- `NaarsCars/Core/Utilities/CalendarOfferTracker.swift` → add to `Core/Utilities` group

Also add the EventKit framework to the target's "Frameworks, Libraries, and Embedded Content" if not auto-linked (EventKit is usually auto-linked when you `import EventKit`).

**Step 2: Build the project**

```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Fix any compilation errors.

**Step 3: Commit**

```bash
git add NaarsCars/NaarsCars.xcodeproj/project.pbxproj NaarsCars/Core/Services/CalendarService.swift NaarsCars/Core/Utilities/CalendarOfferTracker.swift
git commit -m "feat: calendar integration - EventKit service, offer tracking, push notification support"
```

---

## Verification Checklist

After all tasks are complete, verify:

- [ ] Viewing a confirmed ride as claimer/participant → calendar alert appears
- [ ] Dismissing the alert → it appears again on next visit (2nd offer)
- [ ] Dismissing a 2nd time → no more offers for that request
- [ ] Accepting the offer → event appears in iOS Calendar with 1-hour reminder
- [ ] Accepting → no more offers for that request
- [ ] Past events → no calendar offer
- [ ] Claiming a request → poster receives push notification
- [ ] Push notification has "Add to Calendar" action button
- [ ] Tapping "Add to Calendar" on push → event created in Calendar with reminder
- [ ] After creating via push → in-app offer does NOT appear for that request
- [ ] After creating via in-app → push action still works but tracker prevents duplicate logic issues
- [ ] Favors work identically to rides for all above scenarios
- [ ] App builds without warnings related to these changes
