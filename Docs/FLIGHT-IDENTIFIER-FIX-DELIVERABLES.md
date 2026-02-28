# Flight Identifier Feature — Fix Deliverables

## A) Implementation walkthrough (trigger → parse → persist → display → tap)

- **Trigger:** User taps Post on Create Ride. `CreateRideView` calls `CreateRideViewModel.createRide()`, which calls `RideService.createRide(..., notes: ...)` with the notes string. The service inserts the ride, decodes the created row, starts a fire-and-forget `Task { parseAndSaveFlightInfo(rideId, notes) }`, and returns the ride (with `flight_normalized` still nil).
- **Parse:** Inside the task, `RideService.parseAndSaveFlightInfo(rideId:notes:)` calls `FlightCodeParser.parseFirstFlightCode(from: notes)`. The parser uses a regex (2–3 letters + word boundary + optional space/dash + 1–4 digits; not after # or word char). On match it returns `FlightParseResult` with `normalized` (e.g. "DL1234"); otherwise nil.
- **Persist:** If the parser returned a result, the service PATCHes the ride with `flight_normalized = result.normalized`. On success it posts `NotificationCenter.rideFlightEnrichmentDidComplete` with `userInfo["rideId"] = rideId.uuidString`.
- **Display:** List and detail get `Ride` from `fetchRides`/`fetchRide` (after refetch triggered by the notification) or from SwiftData mapping. They call `FlightInfo.displayInfo(for: ride)`, which uses `ride.flightNormalized` when set (persisted), else parses from notes (fallback). When non-nil, they show `FlightRowView(flightInfo:style:)`.
- **Tap:** `FlightRowView` uses `Link(destination: Constants.URLs.flightStatusSearch(normalizedFlightNumber:))`, opening the browser to a Google search for that flight. No in-app status API.

**Exact files and symbols:**

| Step    | File | Symbol |
|---------|------|--------|
| Trigger | CreateRideView.swift | Button → viewModel.createRide() |
| Trigger | CreateRideViewModel.swift | createRide(), notes |
| Trigger | RideService.swift | createRide(...), Task { parseAndSaveFlightInfo(...) } |
| Parse   | FlightCodeParser.swift | parseFirstFlightCode(from:) |
| Persist | RideService.swift | parseAndSaveFlightInfo(rideId:notes:), supabase.from("rides").update(...) |
| Notify  | RideService.swift | NotificationCenter.post(rideFlightEnrichmentDidComplete) |
| Refresh | RidesDashboardViewModel.swift | flightEnrichmentObserver, loadRides(forceRefresh:true, showLoadingIndicator:false) |
| Refresh | RequestsDashboardViewModel.swift | flightEnrichmentObserver, loadRequests(forceRefresh:true, showLoadingIndicator:false) |
| Refresh | RideDetailView.swift | .onReceive(rideFlightEnrichmentDidComplete) → viewModel.loadRide(id:) |
| Display | FlightInfo.swift | displayInfo(for:), fromPersisted(normalized:) |
| Display | RideCard.swift | FlightInfo.displayInfo(for: ride), FlightRowView |
| Display | RideDetailView.swift | FlightInfo.displayInfo(for: ride), FlightRowView |
| Tap     | FlightRowView.swift | Link(destination: statusSearchURL) |
| Tap     | Constants.swift | URLs.flightStatusSearch(normalizedFlightNumber:) |

---

## 1) What it does today (end-to-end)

- **Create:** User enters notes (e.g. "Need pickup for DL 1234") and taps Post. `CreateRideViewModel.createRide()` calls `RideService.createRide(..., notes: ...)`.
- **Insert:** The service inserts the ride into Supabase (no `flight_normalized` yet), decodes the created row, and returns the ride to the caller. It then starts two fire-and-forget background tasks: one for estimated cost, one for flight.
- **Parse:** The flight task runs `parseAndSaveFlightInfo(rideId:notes:)`. It calls `FlightCodeParser.parseFirstFlightCode(from: notes)`, which uses a regex (2–3 letters, word boundary, optional space/dash, 1–4 digits). If there is a match it returns a normalized code (e.g. "DL1234").
- **Persist:** The service PATCHes the ride row with `flight_normalized = result.normalized`. On success it posts `NotificationCenter.rideFlightEnrichmentDidComplete` with `userInfo["rideId"] = rideId.uuidString`.
- **Refresh:** RidesDashboardViewModel and RequestsDashboardViewModel subscribe to that notification and call `loadRides(forceRefresh: true, showLoadingIndicator: false)` / `loadRequests(forceRefresh: true, showLoadingIndicator: false)`, so the list refetches from the server and syncs to SwiftData. RideDetailView subscribes to the same notification and, if the notification’s rideId matches the displayed rideId, calls `viewModel.loadRide(id: rideId)` so the detail screen refetches that ride.
- **Display:** Ride Card and Ride Detail get `Ride` from the list (SDRide → Ride, including `flightNormalized`) or from `fetchRide(id:)`. They call `FlightInfo.displayInfo(for: ride)`, which uses `ride.flightNormalized` when non-empty (persisted), otherwise parses from notes (fallback). When non-nil, they show `FlightRowView(flightInfo:style:)`.
- **Tap:** The row uses `Link(destination: Constants.URLs.flightStatusSearch(normalizedFlightNumber:))`, which opens the system browser to a Google search for that flight (e.g. "DL1234 flight status"). No in-app flight status API.

---

## 2) Why it wasn’t working (with evidence)

- **Root cause:** Stale UI. The background task that parses and writes `flight_normalized` runs **after** the ride is returned. The list and detail views never refetched when that write completed, so they kept showing the ride from the insert (or the first load), where `flight_normalized` was still nil.
- **Evidence:**
  - Audit doc (D): “Ride Card and Ride Detail do not refetch by themselves after create. They show whatever Ride they have. … To see the saved flight, the user had to trigger a refetch.”
  - Code: `parseAndSaveFlightInfo` runs in a `Task { }` with no follow-up signal to the UI; RidesDashboardViewModel and RideDetailViewModel had no observer for “flight enrichment completed.”
  - DB and model are correct: `flight_normalized` exists in Supabase, and `Ride.flightNormalized` is mapped and decoded. So the bug was not parser or persistence per se, but the UI not being updated after a successful persist.

---

## 3) What changed (files, flow, refresh trigger)

### Files changed

- **NaarsCars/Core/Utilities/NotificationNames.swift**  
  - Added `Notification.Name.rideFlightEnrichmentDidComplete`.  
  - Added `RideFlightEnrichmentNotification.rideIdKey` ("rideId") for userInfo.

- **NaarsCars/Core/Services/RideService.swift**  
  - In `parseAndSaveFlightInfo`, after a successful Supabase update:  
    - Post `rideFlightEnrichmentDidComplete` on the main queue with `userInfo[rideIdKey] = rideId.uuidString`.  
  - Kept/added DEBUG-only logs (createRide completed, parseAndSaveFlightInfo entry/success/fail, and a one-line summary: rideId, notesPreview, normalized, persisted=true).

- **NaarsCars/Core/Utilities/FlightCodeParser.swift**  
  - Added DEBUG-only logs: on entry (notes length), when returning nil (empty or no match), and when returning a match (normalized).

- **NaarsCars/Core/Models/FlightInfo.swift**  
  - In `displayInfo(for:)`, DEBUG logs now include `rideId` and explicit `source=` (persisted | fallbackFromNotes | none) plus the code used.

- **NaarsCars/Features/Rides/ViewModels/RidesDashboardViewModel.swift**  
  - Stored property: `flightEnrichmentObserver: (any NSObjectProtocol)?`.  
  - In `init`, subscribe to `.rideFlightEnrichmentDidComplete` on `.main`; in the handler, `Task { await self?.loadRides(forceRefresh: true, showLoadingIndicator: false) }`.  
  - In `stop()`, remove the observer and set it to nil.

- **NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift**  
  - Stored property: `flightEnrichmentObserver`.  
  - In `init`, subscribe to `.rideFlightEnrichmentDidComplete`; in the handler, `Task { await self?.loadRequests(forceRefresh: true, showLoadingIndicator: false) }`.  
  - In `stop()`, remove the observer.  
  - `loadRequests` now takes `showLoadingIndicator: Bool = true` and only shows the spinner when true (silent refresh when called from the notification).

- **NaarsCars/Features/Rides/Views/RideDetailView.swift**  
  - `.onReceive(NotificationCenter.default.publisher(for: .rideFlightEnrichmentDidComplete))`: if `notification.userInfo[rideIdKey]` equals the current `rideId`, call `Task { await viewModel.loadRide(id: rideId) }`.

### New flow after posting a ride

1. User posts ride with notes containing a flight (e.g. "Need pickup for DL 1234").  
2. Ride is inserted; createRide returns; list/detail may show the new ride with `flight_normalized == nil`.  
3. Background task runs: parser extracts "DL1234", PATCHes `flight_normalized` to the ride, then posts `rideFlightEnrichmentDidComplete` with that ride’s id.  
4. **Rides tab:** RidesDashboardViewModel receives the notification and calls `loadRides(forceRefresh: true, showLoadingIndicator: false)`. List refetches, SwiftData is updated, cards re-render with `flightNormalized` set.  
5. **Requests tab:** RequestsDashboardViewModel receives the same notification and calls `loadRequests(forceRefresh: true, showLoadingIndicator: false)`. Requests list refetches; the ride in the list now has `flight_normalized` and the card shows the flight.  
6. **Ride detail:** If the user is on RideDetailView for that ride, the view receives the notification, sees the rideId match, and calls `viewModel.loadRide(id: rideId)`. The detail refetches and the flight row appears (or updates) without pull-to-refresh.

### How/when the UI refresh is triggered

- **Signal:** One notification, `rideFlightEnrichmentDidComplete`, posted on the main queue from `RideService.parseAndSaveFlightInfo` immediately after a successful Supabase update of `flight_normalized`.  
- **Subscribers:**  
  - **RidesDashboardViewModel** (init): subscribes; on receipt, runs `loadRides(forceRefresh: true, showLoadingIndicator: false)`.  
  - **RequestsDashboardViewModel** (init): subscribes; on receipt, runs `loadRequests(forceRefresh: true, showLoadingIndicator: false)`.  
  - **RideDetailView** (view modifier): `.onReceive`; if the notification’s rideId equals the view’s `rideId`, runs `viewModel.loadRide(id: rideId)`.  
- **No loop:** The notification is only posted when our background task successfully writes `flight_normalized`. No other code posts it, so refetching does not cause another notification.

---

## 4) Test plan

1. **Note formats (no manual refresh)**  
   Create a new ride for each of these notes; confirm the flight row appears on the **list** (Rides or Requests) and on **Ride Detail** without pull-to-refresh (wait 1–2 seconds after post if needed):  
   - `DL1234`  
   - `Need pickup for DL 1234`  
   - `Flight DL-1234 at 6pm`  
   - `UA 8`  
   For each, confirm the displayed code is normalized (e.g. DL1234, UA8) and that tapping it opens a browser to a Google search for that flight (e.g. "DL1234 flight status").

2. **Ride Detail open at post time**  
   Post a ride with notes "DL 100" and navigate straight to the new ride’s detail (e.g. from create success). Confirm the flight row appears shortly without pull-to-refresh.

3. **Tap opens browser**  
   On a ride card or detail that shows a flight code, tap the code. Confirm the browser opens to a Google search URL containing the normalized flight and "flight" (or "flight status").

4. **DEBUG logs (optional)**  
   In a DEBUG build, create a ride with "Need pickup for DL 1234" and confirm in the console:  
   - `[FlightAudit] createRide completed` with notes length and preview.  
   - `[FlightAudit] parseAndSaveFlightInfo entered` and `parser success; normalized=DL1234`.  
   - `[FlightAudit] parseAndSaveFlightInfo persistence success` and `summary: ... persisted=true`.  
   - After list/detail refresh: `[FlightAudit] displayInfo rideId=... source=persisted flight_normalized=DL1234`.
