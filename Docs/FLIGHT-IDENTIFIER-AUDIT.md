# Flight Identifier Parser Feature — Audit Report

## A) Product requirement recap

Users may paste a commercial flight number (e.g. "DL 1234", "DL1234", "UA 8") into the Ride Request "notes" field. After a ride is posted (or when ride details are saved), the app should: (1) detect a flight number in the notes (best-effort, no live status), (2) extract and store a normalized flight code on the ride record (e.g. "DL1234"), (3) display that code on the Ride Card and Ride Detail UI (like estimated cost), and (4) make the code tappable so that tapping opens the browser to a Google search for that flight (e.g. `https://www.google.com/search?q=DL1234+flight+status`). No live flight-status APIs are used.

---

## B) Implementation walkthrough (trigger → parse → persist → display → tap)

1. **Trigger**  
   User taps "Post" on Create Ride. `CreateRideViewModel.createRide()` calls `RideService.createRide(..., notes: ...)`. The service inserts the ride, decodes the created row, then starts two fire-and-forget `Task { }` blocks: one for estimated cost, one for flight parse. The created ride is returned immediately (with `flight_normalized` still nil from the insert response). The flight task runs asynchronously with the same `notes` passed into `createRide`.

2. **Parse**  
   Inside the background task, `RideService.parseAndSaveFlightInfo(rideId:notes:)` is called. It calls `FlightCodeParser.parseFirstFlightCode(from: notes)`. The parser uses a regex: 2–3 letters (with word boundary), optional space/dash, then 1–4 digits; it must not be preceded by `#` or a word character. If there is a match it returns a `FlightParseResult` (e.g. `normalized: "DL1234"`); otherwise it returns nil and the method returns without writing.

3. **Persist**  
   If the parser returns a result, the service builds `updateData = ["flight_normalized": result.normalized]` and calls `supabase.from("rides").update(updateData).eq("id", rideId).execute()`. There is no retry. Success is logged; errors are logged and swallowed (no user-facing error).

4. **Display**  
   Ride Card and Ride Detail do not refetch by themselves after create. They show whatever `Ride` they have. That comes from: (a) list: `RidesDashboardViewModel.getFilteredRides(sdRides:)` maps `SDRide` → `Ride` (including `flightNormalized`); SDRide is filled by `DashboardSyncEngine` from the last `fetchRides()` response. (b) Detail: `RideDetailViewModel.loadRide(id:)` calls `fetchRide(id:)` and sets `ride`. So the list shows the ride as of the last fetch (right after create, that is the insert response, so `flightNormalized == nil`). The detail view shows the ride as of the last `loadRide` (which may be the same insert response if the user opened detail before the background task finished). To see the saved flight, the user must trigger a refetch (e.g. pull-to-refresh on list, or open detail and pull-to-refresh / re-enter screen so `loadRide` runs again after the task has written).

5. **Tap**  
   When `FlightInfo.displayInfo(for: ride)` is non-nil, `RideCard` and `RideDetailView` show `FlightRowView(flightInfo:style:)`. The row uses `Link(destination: Constants.URLs.flightStatusSearch(normalizedFlightNumber:))` so tapping opens the system browser (or in-app Safari); no Google Maps dependency.

---

## C) File-by-file list

| File path | Relevant symbols | Notes |
|-----------|------------------|--------|
| `NaarsCars/Features/Rides/Views/CreateRideView.swift` | `Button("ride_create_post"...)` → `viewModel.createRide()` | Entry point: user posts ride; notes come from `viewModel.notes`. |
| `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift` | `createRide()`, `notes` | Formats time, calls `rideService.createRide(..., notes: notes.trimming...)`. Empty notes become `nil`. |
| `NaarsCars/Core/Services/RideService.swift` | `createRide(...)`, `parseAndSaveFlightInfo(rideId:notes:)` | Inserts ride (no `flight_normalized` in insert). Starts `Task { parseAndSaveFlightInfo(rideId, notes) }`. Parser runs in task; on success, PATCHes `flight_normalized` to rides. |
| `NaarsCars/Core/Utilities/FlightCodeParser.swift` | `parseFirstFlightCode(from: String?)` | Regex: `(?<![#\w])([A-Za-z]{2,3})\b[\s\-]*(\d{1,4})(?![0-9])`. Returns `FlightParseResult?` (rawMatch, airlineCode, numberDigits, normalized, googleQueryURL). |
| `NaarsCars/Core/Models/Ride.swift` | `flightNormalized: String?`, `CodingKeys.flightNormalized = "flight_normalized"` | Model and Codable mapping for DB column. |
| `NaarsCars/Core/Models/FlightInfo.swift` | `displayInfo(for: Ride)`, `fromPersisted(normalized:)`, `extract(from:pickup:destination:)` | Display: if `ride.flightNormalized` non-empty, use `fromPersisted`; else parse from notes via `FlightNumberParser` + `AirportRouteParser` (and airline/airport DB). |
| `NaarsCars/UI/Components/Cards/RideCard.swift` | `if let flightInfo = FlightInfo.displayInfo(for: ride)` | Renders `FlightRowView(flightInfo, .compact)` when displayInfo is non-nil. |
| `NaarsCars/Features/Rides/Views/RideDetailView.swift` | `if let flightInfo = FlightInfo.displayInfo(for: ride)` | Renders `FlightRowView(flightInfo, .detail)` in a card when displayInfo is non-nil. |
| `NaarsCars/UI/Components/Common/FlightRowView.swift` | `FlightRowView`, `statusSearchURL`, `Link(destination: url)` | Uses `Constants.URLs.flightStatusSearch(normalizedFlightNumber:)` to build URL; `Link` opens in browser. |
| `NaarsCars/Core/Utilities/Constants.swift` | `URLs.flightStatusSearch(normalizedFlightNumber:)` | Returns `"https://www.google.com/search?q=\(encoded)+flight+status"`. |
| `NaarsCars/Core/Storage/SDModels.swift` | `SDRide.flightNormalized` | SwiftData model for local cache; must mirror Ride. |
| `NaarsCars/Core/Storage/DashboardSyncEngine.swift` | `syncRides` / `updateSDRide` | Writes `ride.flightNormalized` into SDRide when syncing from API. |
| `NaarsCars/Features/Rides/ViewModels/RidesDashboardViewModel.swift` | `getFilteredRides(sdRides:)`, `syncRidesToSwiftData` | Maps SDRide → Ride (incl. `flightNormalized`); updates SDRide from fetched Ride. |
| `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | Same pattern as RidesDashboard | Request list also maps Ride ↔ SDRide with `flightNormalized`. |
| `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift` | Ride init from SDRide | Passes `flightNormalized: sdRide.flightNormalized` when building Ride. |

---

## D) Failure analysis and evidence

### Database and model

- **Supabase `public.rides`**: Column `flight_normalized` (text, nullable) is present (verified via `information_schema.columns`).
- **Ride model**: `flightNormalized` is optional, mapped to `"flight_normalized"` in CodingKeys; decode/encode are correct.
- **Insert**: Ride insert does not send `flight_normalized` (correct; it is set later by the background task).
- **Update**: Only `parseAndSaveFlightInfo` writes `flight_normalized`; `updateRide` (user edit) does not touch it, so it is not overwritten on edit.

### Likely causes of “not working”

1. **Stale UI after create**  
   After create, the returned ride and the list/detail view often show the ride from the insert response (or a single subsequent fetch). The background task updates the row later. If the UI does not refetch after that, `ride.flightNormalized` stays nil in the list/detail until the user triggers a refetch (pull-to-refresh, re-open detail, or list refresh).

2. **Parser returns nil**  
   If notes are empty, or the regex does not match (e.g. different spacing, more than 3 letters, or digits not immediately after the optional space/dash), `parseFirstFlightCode` returns nil and nothing is persisted. No user-visible error.

3. **Persistence failure**  
   If the Supabase update fails (e.g. network, RLS, or a different schema in another environment), the error is only logged; the UI never gets an updated ride with `flight_normalized`.

### Debug logs added (DEBUG only)

- **RideService.createRide** (after decode):  
  `[FlightAudit] createRide completed; rideId=..., notesLength=..., notesPreview=...`  
  Confirms notes are passed and length; preview shows first 80 chars.

- **RideService.parseAndSaveFlightInfo**  
  - Entry: `[FlightAudit] parseAndSaveFlightInfo entered; rideId=..., notesNil=..., notesLength=...`  
  - Parser nil: `[FlightAudit] parseAndSaveFlightInfo parser returned nil (no match)`  
  - Parser success: `[FlightAudit] parseAndSaveFlightInfo parser success; normalized=...`  
  - Persist success: `[FlightAudit] parseAndSaveFlightInfo persistence success`  
  - Persist failure: `[FlightAudit] parseAndSaveFlightInfo persistence failed: ...`

- **FlightInfo.displayInfo(for:)**  
  - When using persisted: `[FlightAudit] displayInfo using persisted flight_normalized=...`  
  - Fallback: `[FlightAudit] displayInfo ride.flightNormalized=..., fallbackFromNotes=...`

### How to interpret logs

- **Create a ride with notes like "Need pickup for DL 1234".**
- Expect: `createRide completed` with `notesLength > 0` and preview containing "DL".
- Then: `parseAndSaveFlightInfo entered` with same `notesLength`.
- If parser matches: `parser success; normalized=DL1234` then `persistence success` (and existing "Parsed and saved flight..." log).
- If parser fails: `parser returned nil`; then no persistence logs.
- When the ride is shown (list or detail): either `displayInfo using persisted flight_normalized=DL1234` (after refetch) or `displayInfo ride.flightNormalized=nil, fallbackFromNotes=DL1234` if fallback from notes is used.

If you never see `parseAndSaveFlightInfo entered`, the task is not running. If you see `parser returned nil` for input that should match, the regex or input (e.g. trimming) is the issue. If you see `persistence failed`, the Supabase update is failing.

---

## E) Minimal fix plan (bulleted)

1. **Ensure parser is invoked with actual notes**  
   - Already correct: `notesForFlight = notes` is captured and passed into the task.  
   - Optional: add a DEBUG log at the very start of `createRide` to log `notes` length and a short prefix, to confirm CreateRideViewModel is sending non-empty notes.

2. **Reduce “stale UI” after create**  
   - After successful create and navigation (e.g. to list or detail), trigger a refetch so the ride is re-loaded from the server after the background task has had time to run.  
   - Options:  
     - In the create success path (e.g. in CreateRideView or coordinator), after `onRideCreated?(ride.id)` and before or after dismiss, call a refresh (e.g. notification or callback that RidesDashboard/RequestsDashboard and/or RideDetailViewModel refetch).  
     - Or: when Ride Detail is shown for a ride that was just created (e.g. same session), refetch after a short delay (e.g. 2 seconds) so the flight_normalized write is likely complete.  
   - Prefer a single place (e.g. “refresh rides list” or “refresh this ride”) so the UI consistently shows updated `flight_normalized` without polling.

3. **Optional: retry persistence once**  
   - In `parseAndSaveFlightInfo`, on failure (other than cancellation), retry the update once after a short delay (e.g. 1–2 seconds) to smooth over transient network issues. Keep logging so persistence failures remain visible.

4. **Keep DEBUG logs**  
   - Leave the `[FlightAudit]` logs behind `#if DEBUG` until the feature is verified in production; then remove or gate behind a debug flag if desired.

5. **No schema or model change required**  
   - Column and model are correct; no migration or CodingKeys change needed for the fix.

---

## F) Risks and side effects

- **Refetch after create**: Refreshing the list or the single ride after create may cause a brief loading state or list flicker; keep the refresh minimal (e.g. one refetch, no extra polling).
- **Delayed refetch**: If using a delayed refetch (e.g. 2s) on detail, the user might still see no flight for a couple of seconds; acceptable for a best-effort, non-blocking feature.
- **Parser**: The current regex is strict (word boundary, 2–3 letters, 1–4 digits). If users paste formats like "Flight: DL 1234" or "Delta 1234", the parser may not match; that is a product/UX choice (could relax regex or add more patterns later).
- **No external APIs**: No change; still open-data only, no background polling, and tap continues to open browser only.

---

## Exact code locations to share with ChatGPT

- **Trigger (create + start background task):**  
  `NaarsCars/Core/Services/RideService.swift` — `createRide(...)` (insert, then `Task { parseAndSaveFlightInfo(rideId, notesForFlight) }`).

- **Parser:**  
  `NaarsCars/Core/Utilities/FlightCodeParser.swift` — `parseFirstFlightCode(from:)` and the regex `flightPattern`.

- **Persistence:**  
  `NaarsCars/Core/Services/RideService.swift` — `parseAndSaveFlightInfo(rideId:notes:)` (parser call + `supabase.from("rides").update(...)`).

- **Display source of truth:**  
  `NaarsCars/Core/Models/FlightInfo.swift` — `displayInfo(for: ride)` (persisted vs fallback from notes).

- **UI binding:**  
  `NaarsCars/UI/Components/Cards/RideCard.swift` — `FlightInfo.displayInfo(for: ride)`.  
  `NaarsCars/Features/Rides/Views/RideDetailView.swift` — same, in the ride detail body.

- **Tap (open browser):**  
  `NaarsCars/UI/Components/Common/FlightRowView.swift` — `Link(destination: statusSearchURL)`.  
  `NaarsCars/Core/Utilities/Constants.swift` — `URLs.flightStatusSearch(normalizedFlightNumber:)`.

- **DEBUG audit logs:**  
  `RideService.swift` (createRide + parseAndSaveFlightInfo).  
  `FlightInfo.swift` (displayInfo).

- **DB column:**  
  Supabase `public.rides.flight_normalized` (TEXT, nullable). Migration: `supabase/migrations/20260216_0005_add_flight_normalized_to_rides.sql` (and `database/109_add_flight_normalized_to_rides.sql`).
