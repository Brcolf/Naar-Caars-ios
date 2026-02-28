# Pickup location autocomplete – performance investigation

**Symptom:** First tap into the pickup location text field (address autocomplete) often causes ~2–4+ seconds before the UI feels responsive (keyboard/input/suggestions).

**Scope:** Identify root cause(s) with evidence; propose minimal fixes. No large refactors.

---

## 1. Where the pickup autocomplete is implemented

| Role | File | Key symbols |
|------|------|-------------|
| **UI** | `NaarsCars/UI/Components/Inputs/LocationAutocompleteField.swift` | `LocationAutocompleteField`, `private let locationService = LocationService.shared`, `@FocusState isFocused`, `onChange(of: text)` → `performSearch`, `onChange(of: isFocused)` → `showDropdown` |
| **Backing service** | `NaarsCars/Core/Services/LocationService.swift` | `LocationService.shared`, `@MainActor` init, `loadRecentLocations()`, `MKLocalSearchCompleter`, `searchPlaces(query:)`, `completerDidUpdateResults` |
| **Usage (ride creation)** | `NaarsCars/Features/Rides/Views/CreateRideView.swift` | `LocationAutocompleteField(..., text: $viewModel.pickup, ...)` in Section "route" |
| **ViewModel** | `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift` | `@Published var pickup: String` |

**Implementation:** MapKit (`MKLocalSearchCompleter` + `MKLocalSearch`), not Google. The comment in `LocationAutocompleteField.swift` still says "Google Places API" but the implementation is Apple MapKit.

**Flow:**

- **Focus/tap:** `TextField` uses `@FocusState isFocused`. Tapping the field sets `isFocused = true` → `onChange(of: isFocused)` runs → `showDropdown = focused && (...)` and reads `locationService.recentLocations`.
- **Queries:** User types → `onChange(of: text)` → `performSearch(query:)` → 300 ms debounce → `locationService.searchPlaces(query:)` (sets `searchCompleter.queryFragment`) → delegate `completerDidUpdateResults` → continuation resumed → `predictions = results` on main.
- **First use of `LocationService`:** The field has `private let locationService = LocationService.shared`. That is evaluated when the **view struct is first created**, i.e. when the parent builds its body. So when Create Ride is shown and the Form builds the route section, the two `LocationAutocompleteField` structs are created and both read `LocationService.shared` → singleton is created then (unless something else already created it, e.g. `MessageInputBar`).

---

## 2. What happens on “first tap” (from code)

- **Tap → focus:** `isFocused` becomes true; `onChange(of: isFocused)` runs and sets `showDropdown` and reads `locationService.recentLocations`. If the singleton was not yet created (e.g. if the field/view was not yet built), this is when `LocationService()` runs.
- **LocationService init (all on main, `@MainActor`):**
  - `searchCompleter.delegate = self`, `resultTypes`, `region`
  - **`loadRecentLocations()`** – synchronous: `UserDefaults.standard.data(forKey: "recent_locations")` and `JSONDecoder().decode([SavedLocation].self, from: data)`. No other file I/O in this path.
- **When user types (first query):** `performSearch` → 300 ms sleep → `locationService.searchPlaces(query)` → `searchCompleter.queryFragment = query`. MapKit then does work (possibly lazy init, network, etc.) and calls `completerDidUpdateResults` on its delegate; we resume the continuation and set `predictions` on main.

So possible sources of 2–4 s delay:

1. **Singleton creation on first use** – When the first `LocationAutocompleteField` is created (Create Ride screen appear or first tap, depending on when the view body is evaluated), `LocationService.init()` runs on the main thread, including `loadRecentLocations()`. If init or UserDefaults/decode is slow, main thread blocks.
2. **First use of MKLocalSearchCompleter** – The first time `queryFragment` is set, MapKit may do one-time setup (resources, network, etc.). That work might block the main thread or delay the delegate callback.
3. **Keyboard / first responder** – Unrelated to our code but can add perceived delay; instrumentation does not measure this.

---

## 3. Instrumentation added (DEBUG-only)

All logs use the prefix `[LocationPerf]` and `CFAbsoluteTimeGetCurrent()` so you can sort by time and compute deltas.

**LocationService.swift**

- `LocationService.init start`
- `LocationService.init before loadRecentLocations`
- `LocationService.init end`
- `loadRecentLocations start` / `loadRecentLocations end (...)` 
- `searchPlaces query dispatch '...'`
- `completerDidUpdateResults received (count=...)`
- `completerDidUpdateResults resuming continuation`

**LocationAutocompleteField.swift**

- `LocationAutocompleteField onAppear (...)` – when the field view appears (body evaluated; may have already touched `LocationService.shared` earlier when the struct was created)
- `focus gained (tap into field)` – when `isFocused` becomes true
- `performSearch after debounce, calling searchPlaces` – just before `searchPlaces`
- `performSearch first result received (count=...)` – after `searchPlaces` returns
- `performSearch applying results to state` – inside `MainActor.run` when setting `predictions`

**How to capture a timeline**

1. Run the app in DEBUG (Xcode, simulator or device).
2. Open Create Ride (or the screen that shows the pickup field).
3. Tap into the pickup field (and optionally type 2+ characters).
4. In Xcode console, filter by `LocationPerf` and note the printed timestamps.

**Interpretation**

- **Gap between `init start` and `init end`** = main-thread time in `LocationService` init (including `loadRecentLocations`).
- **Gap between `focus gained` and next event** = delay after tap before our next logged work (e.g. if nothing else logs soon, the stall may be in SwiftUI/keyboard or in something not instrumented).
- **Gap between `searchPlaces query dispatch` and `completerDidUpdateResults received`** = time for MapKit to return results (async; may be main thread or background in MapKit).
- **Gap between `completerDidUpdateResults resuming continuation` and `performSearch applying results to state`** = scheduling + main run loop to run the continuation and the `MainActor.run` block.

---

## 4. Root cause candidates (ranked)

| Rank | Candidate | Evidence / code | Main-thread? |
|------|------------|------------------|--------------|
| 1 | **LocationService init on first use** | Init runs on `@MainActor` and calls `loadRecentLocations()` synchronously (`LocationService.swift` 106–113, 214–224). First access is when the first `LocationAutocompleteField` is created (Form building the route section). | Yes – entire init and UserDefaults read/decode on main. |
| 2 | **MKLocalSearchCompleter first use** | First assignment to `queryFragment` may trigger MapKit one-time setup. We don’t know if that’s on main or background; delegate callbacks are delivered to our `Task { @MainActor in ... }`. | Unknown until measured; delegate runs on main. |
| 3 | **UserDefaults / JSON decode in loadRecentLocations** | Sync read + decode in init. Usually fast; could be slow on first access or with large data. | Yes. |
| 4 | **Re-render when showDropdown becomes true** | `onChange(of: isFocused)` sets `showDropdown`; body re-evaluates and builds dropdown (and reads `recentLocations`). Unlikely to be 2–4 s by itself. | Main. |

**Most likely:** Singleton creation (and thus `loadRecentLocations`) on the main thread when the Create Ride screen (or the first field) is first built. If the delay is perceived specifically on “first tap,” it could still be that SwiftUI builds the form when the section becomes visible, and the tap happens right after – so the user attributes the freeze to the tap.

---

## 5. Minimal fixes (do not implement yet)

### Fix A: Eagerly create LocationService at app launch

- **What:** In `AppDelegate` or early app lifecycle (e.g. after auth/shell is ready), touch `LocationService.shared` on a background queue or off the main thread? No – the type is `@MainActor`, so you’d at least schedule its creation on the main actor at a chosen time, e.g. after the first screen is idle, or on a short delay after launch.
- **Why it helps:** Moves init (and `loadRecentLocations`) off the critical path of “user navigates to Create Ride” or “user taps pickup field.” The 2–4 s cost is paid earlier when the user is not waiting on the field.
- **Risk:** Slightly more work at launch; if init is heavy, could shift the hitch to app start. Ensure creation happens on main (e.g. `Task { @MainActor in _ = LocationService.shared }`).

### Fix B: Defer loadRecentLocations off the critical path

- **What:** In `LocationService.init()`, do not call `loadRecentLocations()`. Instead, kick off a single async task that loads recents and assigns `recentLocations` on the main actor when done. Init stays minimal (completer setup only).
- **Why it helps:** UserDefaults read and JSON decode are no longer in init; first tap no longer waits for that sync work.
- **Risk:** “Recent” list may be empty for one frame after the field appears; usually acceptable. Ensure only one load runs and that `recentLocations` is only written on main.

### Fix C: Debounce or defer dropdown visibility on focus

- **What:** When `isFocused` becomes true, do not immediately set `showDropdown = true`; e.g. set it after a short delay (0.1 s) or on the next run loop, so the keyboard and focus can settle first.
- **Why it helps:** Reduces perceived contention on the main thread right at tap (fewer immediate re-renders). Unlikely to remove 2–4 s by itself but may help if the hitch is “focus + dropdown render.”
- **Risk:** Dropdown could appear slightly later; minimal.

---

## 6. Commit-style summary of instrumentation changes

**Files touched**

- `NaarsCars/Core/Services/LocationService.swift`
  - Added `#if DEBUG` helper `_locationPerfLog` and logs: init start/before loadRecentLocations/end, loadRecentLocations start/end, searchPlaces query dispatch, completerDidUpdateResults received/resuming.
- `NaarsCars/UI/Components/Inputs/LocationAutocompleteField.swift`
  - Added `#if DEBUG` helper `_locationFieldPerfLog` and logs: onAppear, focus gained, performSearch after debounce, first result received, applying results to state.

**How to verify**

Run the app in Debug, open Create Ride, tap pickup field (and optionally type). In console, filter by `[LocationPerf]` and confirm a single ordered timeline. Use the gaps between timestamps to see where the delay occurs before applying Fix A/B/C.

---

## 7. Focus-gained stall fix (post–log analysis)

**Measured:** LocationService init ~4 ms; stall ~13.7 s between “focus gained” and next event; “System gesture gate timed out” in between. Debounce/MapKit return quickly once they run.

**Root cause (inferred):** The main run loop was blocked or starved after the focus handler ran. When `onChange(of: isFocused)` ran with `focused == true`, we did:

1. Read `locationService.recentLocations` on the main thread.
2. Set `showDropdown = true` synchronously, which triggered an immediate body re-evaluation that built the dropdown and again read `locationService.recentLocations` and iterated `ForEach(locationService.recentLocations)`.

That synchronous state update and body work kept the focus handler’s “transaction” open and competed with the system’s gesture/keyboard handling. The system gesture gate then timed out because the run loop didn’t process the gesture in time. So the blocker was **synchronous dropdown visibility + body evaluation (including reading an ObservableObject and building the dropdown) on the main thread in the same run-loop turn as focus**.

**Fix applied**

- **Defer dropdown work:** When focus is gained, we no longer set `showDropdown` or read `recentLocations` synchronously. We schedule `Task { @MainActor in ... }` that reads `locationService.recentLocations`, sets `recentLocationsSnapshot`, and sets `showDropdown`. The focus handler returns immediately so the run loop can process the gesture and keyboard.
- **Snapshot recents in body:** The dropdown now uses `@State recentLocationsSnapshot` instead of reading `locationService.recentLocations` in `body`. That avoids reading an ObservableObject during body evaluation and keeps the dropdown from tying view updates to `LocationService`’s publisher.
- **Instrumentation:** Added `os_signpost` (FocusHandler, DeferredDropdown, DebounceWait), `[LocationPerf]` logs with `main=Y/N` and durations (ms), and a DEBUG watchdog that logs `WARNING: main thread blocked Xms before deferred dropdown ran` if the deferred task runs more than 500 ms after “focus gained.”

**Files changed**

- `NaarsCars/UI/Components/Inputs/LocationAutocompleteField.swift`
  - Import `os`; add PERFORMANCE comment with Time Profiler / Main Thread Checker steps.
  - Add `recentLocationsSnapshot: [SavedLocation]`, use it in dropdown instead of `locationService.recentLocations`.
  - In `onChange(of: isFocused)`: when `focused`, do not set `showDropdown`/read recents synchronously; schedule `Task { @MainActor in recents = locationService.recentLocations; recentLocationsSnapshot = recents; showDropdown = ... }`; when `!focused`, clear `showDropdown` and `recentLocationsSnapshot`.
  - In `selectPrediction` after `saveRecentLocation`, set `recentLocationsSnapshot = locationService.recentLocations`.
  - DEBUG: `os_signpost` for FocusHandler (begin/end), DeferredDropdown (begin/end), DebounceWait (begin/end); `_locationFieldPerfLog` with `main=Y/N` and ms; watchdog when gap focus → deferred task > 500 ms; debounce schedule/fire logs.

**How to validate**

1. Run in Debug, Create Ride, tap pickup field. Console should show “focus gained … entry” then “focus gained handler exit (deferred), 0ms” (or a few ms), then shortly “focus deferred dropdown done …”. No “main thread blocked >500ms” unless something else is still blocking.
2. Time Profiler: Profile → Time Profiler, record, tap pickup field, stop; main thread should show FocusHandler and DeferredDropdown; no long gap between focus and deferred work.
3. Main Thread Checker: Enable in scheme; no violations on the focus path.

**Follow-up hotspots (not changed)**

- If “main thread blocked Xms” still appears, the blocker is outside this view (e.g. Form/ScrollView layout, another observer, or system). Use Time Profiler to see what runs between “focus gained” and “DeferredDropdown.”
- `trackScreen` / CrashReportingService and other `.onAppear` modifiers on the same screen are lightweight; unlikely to explain a 13 s stall but can be checked if needed.
