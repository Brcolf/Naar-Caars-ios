# Timezone Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a timezone field to rides and favors so all participants interpret event times consistently, defaulting to Pacific time with daylight savings support.

**Architecture:** Store an IANA timezone identifier (e.g., `America/Los_Angeles`) alongside each request. The iOS `TimeZone` type handles DST automatically via IANA identifiers. A new `TimeZonePicker` component lets users override the default. All date/time combination logic uses the stored timezone.

**Tech Stack:** Supabase migration (new column), Swift `TimeZone`, SwiftUI Picker, existing `TimePickerView`

---

## Context

### Current State
- Rides store `date` (DATE "yyyy-MM-dd") and `time` (TIME "HH:mm:ss")
- Favors store `date` (DATE "yyyy-MM-dd") and `time` (TIME "HH:mm:ss", nullable)
- No timezone info stored — times are ambiguous
- `RequestItem.eventTime` combines date+time using device-local `Calendar.current`
- `RideService`/`FavorService` format dates with `.current` timezone
- `CalendarService` creates events using the combined `eventTime` (device-local)

### Key Files
| File | Role |
|------|------|
| `NaarsCars/Core/Models/Ride.swift` | Ride model |
| `NaarsCars/Core/Models/Favor.swift` | Favor model |
| `NaarsCars/Core/Models/RequestItem.swift` | Unified enum, `eventTime` computed property |
| `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift` | Ride form state |
| `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift` | Favor form state |
| `NaarsCars/Features/Rides/Views/CreateRideView.swift` | Ride creation UI |
| `NaarsCars/Features/Favors/Views/CreateFavorView.swift` | Favor creation UI |
| `NaarsCars/Features/Rides/Views/EditRideView.swift` | Ride edit UI |
| `NaarsCars/Features/Favors/Views/EditFavorView.swift` | Favor edit UI |
| `NaarsCars/Core/Services/RideService.swift` | Ride CRUD (lines 115-179 create, 291-350 update) |
| `NaarsCars/Core/Services/FavorService.swift` | Favor CRUD (lines 115-168 create) |
| `NaarsCars/Features/Rides/Views/RideDetailView.swift` | Ride detail display |
| `NaarsCars/Features/Favors/Views/FavorDetailView.swift` | Favor detail display |
| `NaarsCars/UI/Components/Common/TimePickerView.swift` | Custom time picker component |
| `NaarsCars/Core/Services/CalendarService.swift` | Calendar event creation |
| `NaarsCars/Core/Services/ClaimService.swift` | Push notification with event data |

---

## Task 1: Database Migration — Add timezone column

**Files:**
- Create: `supabase/migrations/YYYYMMDD_add_timezone_to_requests.sql`

**Step 1: Write and apply the migration**

```sql
-- Add timezone column to rides table
ALTER TABLE rides ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles';

-- Add timezone column to favors table
ALTER TABLE favors ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles';
```

Using `America/Los_Angeles` as the default — this is the IANA identifier for Pacific time and automatically handles PST/PDT transitions. Existing rows get Pacific time as default, which is reasonable since the app currently has no timezone info.

**Step 2: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: add timezone column to rides and favors tables"
```

---

## Task 2: Update Ride and Favor Models

**Files:**
- Modify: `NaarsCars/Core/Models/Ride.swift`
- Modify: `NaarsCars/Core/Models/Favor.swift`

**Step 1: Add timezone property to Ride**

Add after the existing `time` property:

```swift
let timezone: String  // IANA timezone identifier (e.g., "America/Los_Angeles")
```

Add a computed property for convenience:

```swift
var timeZone: TimeZone {
    TimeZone(identifier: timezone) ?? TimeZone(identifier: "America/Los_Angeles")!
}
```

Ensure the `CodingKeys` enum includes `timezone` if one exists, or verify Codable auto-synthesis handles it.

**Step 2: Add timezone property to Favor**

Same pattern — add `let timezone: String` and the computed `timeZone` property.

**Step 3: Commit**

```bash
git add NaarsCars/Core/Models/Ride.swift NaarsCars/Core/Models/Favor.swift
git commit -m "feat: add timezone field to Ride and Favor models"
```

---

## Task 3: Update RequestItem.eventTime to Use Stored Timezone

**Files:**
- Modify: `NaarsCars/Core/Models/RequestItem.swift`

**Step 1: Update eventTime and combineDateAndTime**

The current `combineDateAndTime(date:time:)` uses `Calendar.current` (device-local). Update it to accept a timezone parameter:

```swift
private func combineDateAndTime(date: Date, time: String, timeZone: TimeZone) -> Date? {
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)

    let timeParts = time.split(separator: ":")
    guard timeParts.count >= 2,
          let hour = Int(timeParts[0]),
          let minute = Int(timeParts[1]) else {
        return nil
    }

    var components = DateComponents()
    components.year = dateComponents.year
    components.month = dateComponents.month
    components.day = dateComponents.day
    components.hour = hour
    components.minute = minute
    components.second = timeParts.count > 2 ? Int(timeParts[2]) : 0
    components.timeZone = timeZone

    return calendar.date(from: components)
}
```

Update `eventTime` to pass the request's timezone:

```swift
var eventTime: Date {
    switch self {
    case .ride(let ride):
        return combineDateAndTime(date: ride.date, time: ride.time, timeZone: ride.timeZone) ?? ride.date
    case .favor(let favor):
        if let time = favor.time {
            return combineDateAndTime(date: favor.date, time: time, timeZone: favor.timeZone) ?? favor.date
        }
        return favor.date
    }
}
```

Add a convenience accessor for the timezone:

```swift
var timeZone: TimeZone {
    switch self {
    case .ride(let ride): return ride.timeZone
    case .favor(let favor): return favor.timeZone
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Core/Models/RequestItem.swift
git commit -m "feat: use stored timezone in RequestItem.eventTime"
```

---

## Task 4: Create TimeZonePicker Component

**Files:**
- Create: `NaarsCars/UI/Components/Common/TimeZonePicker.swift`

**Step 1: Create the picker component**

A simple picker showing common US timezones with a sensible default. Uses IANA identifiers so `TimeZone` handles DST automatically.

```swift
//
//  TimeZonePicker.swift
//  NaarsCars
//
//  Timezone picker for request creation/editing
//

import SwiftUI

struct TimeZonePicker: View {
    @Binding var selectedTimezone: String

    /// Common US timezones with user-friendly labels
    private static let timezones: [(id: String, label: String)] = [
        ("America/Los_Angeles", "Pacific Time"),
        ("America/Denver", "Mountain Time"),
        ("America/Chicago", "Central Time"),
        ("America/New_York", "Eastern Time"),
        ("Pacific/Honolulu", "Hawaii Time"),
        ("America/Anchorage", "Alaska Time"),
    ]

    var body: some View {
        Picker("timezone_picker_label".localized, selection: $selectedTimezone) {
            ForEach(Self.timezones, id: \.id) { tz in
                Text(tz.label).tag(tz.id)
            }
        }
    }
}
```

**Step 2: Add localization key**

Add `"timezone_picker_label"` to `Localizable.xcstrings` with value `"Time Zone"`.

**Step 3: Add to Xcode project if needed**

With objectVersion 77, check if the file needs explicit pbxproj entry (it's in `UI/Components/Common/` — check if other files in that directory are auto-discovered or manually referenced).

**Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Common/TimeZonePicker.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add TimeZonePicker component"
```

---

## Task 5: Add Timezone to Create/Edit Ride Forms

**Files:**
- Modify: `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift`
- Modify: `NaarsCars/Features/Rides/Views/CreateRideView.swift`
- Modify: `NaarsCars/Features/Rides/Views/EditRideView.swift`

**Step 1: Add timezone property to CreateRideViewModel**

Add alongside existing published properties:

```swift
@Published var timezone: String = "America/Los_Angeles"
```

**Step 2: Add TimeZonePicker to CreateRideView**

Place it after the time picker section (after `TimePickerView`):

```swift
TimeZonePicker(selectedTimezone: $viewModel.timezone)
```

**Step 3: Pre-populate timezone in EditRideView**

In the `.onAppear` block where existing ride data is loaded, add:

```swift
viewModel.timezone = ride.timezone
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift NaarsCars/Features/Rides/Views/CreateRideView.swift NaarsCars/Features/Rides/Views/EditRideView.swift
git commit -m "feat: add timezone picker to ride create/edit forms"
```

---

## Task 6: Add Timezone to Create/Edit Favor Forms

**Files:**
- Modify: `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift`
- Modify: `NaarsCars/Features/Favors/Views/CreateFavorView.swift`
- Modify: `NaarsCars/Features/Favors/Views/EditFavorView.swift`

**Step 1: Add timezone property to CreateFavorViewModel**

```swift
@Published var timezone: String = "America/Los_Angeles"
```

**Step 2: Add TimeZonePicker to CreateFavorView**

Place after the time section (after the time toggle and conditional TimePickerView):

```swift
TimeZonePicker(selectedTimezone: $viewModel.timezone)
```

**Step 3: Pre-populate timezone in EditFavorView**

```swift
viewModel.timezone = favor.timezone
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift NaarsCars/Features/Favors/Views/CreateFavorView.swift NaarsCars/Features/Favors/Views/EditFavorView.swift
git commit -m "feat: add timezone picker to favor create/edit forms"
```

---

## Task 7: Update RideService and FavorService to Include Timezone

**Files:**
- Modify: `NaarsCars/Core/Services/RideService.swift`
- Modify: `NaarsCars/Core/Services/FavorService.swift`

**Step 1: Update RideService.createRide()**

Add `timezone: String` parameter. Include in the payload:

```swift
"timezone": AnyCodable(timezone),
```

**Step 2: Update RideService.updateRide()**

Add `timezone: String? = nil` parameter. Include conditionally:

```swift
if let timezone = timezone {
    updates["timezone"] = AnyCodable(timezone)
}
```

**Step 3: Update FavorService.createFavor()**

Same pattern — add `timezone: String` parameter and include in payload.

**Step 4: Update FavorService.updateFavor()**

Same pattern — add optional `timezone` parameter.

**Step 5: Update call sites in CreateRideViewModel/CreateFavorViewModel**

Pass `timezone: timezone` to the service create/update methods.

**Step 6: Commit**

```bash
git add NaarsCars/Core/Services/RideService.swift NaarsCars/Core/Services/FavorService.swift NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift
git commit -m "feat: include timezone in ride/favor create and update payloads"
```

---

## Task 8: Display Timezone in Detail Views

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`

**Step 1: Show timezone abbreviation next to time in RideDetailView**

Find where `ride.time` is displayed and append the timezone abbreviation. The abbreviation should reflect DST status at the event time (e.g., "PST" in winter, "PDT" in summer):

```swift
// Replace raw time display with formatted version including timezone
let eventDate = RequestItem.ride(ride).eventTime
let abbrev = ride.timeZone.abbreviation(for: eventDate) ?? ride.timeZone.abbreviation() ?? "PT"
Text("\(ride.time) \(abbrev)")
```

**Step 2: Same for FavorDetailView**

```swift
if let time = favor.time {
    let eventDate = RequestItem.favor(favor).eventTime
    let abbrev = favor.timeZone.abbreviation(for: eventDate) ?? favor.timeZone.abbreviation() ?? "PT"
    Text("\(time) \(abbrev)")
}
```

**Step 3: Commit**

```bash
git add NaarsCars/Features/Rides/Views/RideDetailView.swift NaarsCars/Features/Favors/Views/FavorDetailView.swift
git commit -m "feat: display timezone abbreviation next to time in detail views"
```

---

## Task 9: Update CalendarService and ClaimService to Use Stored Timezone

**Files:**
- Modify: `NaarsCars/Core/Services/CalendarService.swift`
- Modify: `NaarsCars/Core/Services/ClaimService.swift`

**Step 1: Update CalendarService.createEventForRide/Favor**

The `eventTime` from `RequestItem` now already uses the stored timezone (from Task 3), so the start date passed to `createEvent()` is correct. No changes needed in CalendarService — it receives a `Date` which is timezone-agnostic (absolute point in time).

Verify this is the case by reading the code. If `eventTime` correctly produces a UTC-absolute `Date` using the stored timezone, CalendarService is already correct.

**Step 2: Update ClaimService.queueClaimPushNotification**

The date parsing in `queueClaimPushNotification` currently uses `Calendar.current` to combine date+time. Update it to also fetch and use the stored timezone:

Add `timezone` to the select fields:

```swift
let selectFields = requestType == "ride"
    ? "date, time, pickup, destination, notes, timezone"
    : "date, time, location, title, description, duration, timezone"
```

Use the fetched timezone for date combination:

```swift
let storedTimezone = json["timezone"] as? String ?? "America/Los_Angeles"
let tz = TimeZone(identifier: storedTimezone) ?? TimeZone(identifier: "America/Los_Angeles")!
var calendar = Calendar.current
calendar.timeZone = tz
```

Also include the timezone in the push payload so the client can use it:

```swift
eventData["event_timezone"] = storedTimezone
```

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ClaimService.swift
git commit -m "feat: use stored timezone in claim push notification date parsing"
```

---

## Task 10: Add TimeZonePicker to Xcode Project + Build Verification

**Files:**
- Possibly modify: `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Step 1: Check if TimeZonePicker.swift needs manual pbxproj entry**

Check if other files in `UI/Components/Common/` (like `TimePickerView.swift`) have explicit pbxproj entries.

**Step 2: Add to pbxproj if needed**

Follow the same pattern used for CalendarService.swift — add PBXFileReference, PBXBuildFile, group membership, and Sources build phase entry.

**Step 3: Build the project**

```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Fix any compilation errors.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: timezone picker - build verification and project integration"
```

---

## Verification Checklist

- [ ] Creating a new ride defaults timezone to Pacific Time
- [ ] Timezone picker shows 6 US timezone options
- [ ] Changing timezone persists to database
- [ ] Editing a ride pre-populates the saved timezone
- [ ] Ride detail view shows timezone abbreviation (PST/PDT) next to time
- [ ] Favor creation/edit has same timezone picker behavior
- [ ] `RequestItem.eventTime` uses the stored timezone (not device-local)
- [ ] Calendar events are created at the correct absolute time regardless of device timezone
- [ ] Push notification event data uses the stored timezone
- [ ] Existing rides/favors show "Pacific Time" (database default)
- [ ] App builds without errors
