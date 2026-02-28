# First-tap text field stall — evidence-based investigation

**Symptom:** 2–4 s stall the first time the user taps into a text field (most reproducible on “Pickup location” address autocomplete; may also occur on first login).

**Goals:** Determine whether the stall is **our code** (synchronous work on focus/tap) or **system** (UIKit/RTI/TextInput/keyboard warm-up). Then apply minimal, evidence-based fixes.

---

## 1. Code paths that run on first focus

### 1.A Login (simplest text field)

| Step | File | Symbol / line | What runs |
|------|------|----------------|-----------|
| View appears | `LoginView.swift` | `body` | `@StateObject LoginViewModel`, plain `TextField`/`SecureField`, no `.focused` binding in release. `.trackScreen("Login")` → `ScreenTrackingModifier.onAppear` → `CrashReportingService.shared.logScreenView(screenName)` (lightweight). |
| First tap (email field) | SwiftUI / UIKit | TextField becomes first responder | **No app code** runs on focus for login in release; the email field has no `onChange(of: focus)` or custom focus handler. Binding is `$viewModel.email` only. |
| After tap | System | — | Keyboard/RTI/TextInput first-time initialization; no app handlers. |

**Conclusion:** Login first-tap runs **no focus-triggered app code**. Any stall is either system (keyboard/RTI warm-up) or layout/rendering triggered indirectly by first responder change.

**DEBUG-only:** `LoginView` can emit a signpost when the email field gains focus (see §4) so Time Profiler can align the “focus seen by app” point for Scenario A.

---

### 1.B Pickup location (Create Ride → address autocomplete)

| Step | File | Symbol / line | What runs |
|------|------|---------------|-----------|
| Create Ride appears | `CreateRideView.swift` | `onAppear` (126–132) | `Task { @MainActor in _ = LocationService.shared; locationServiceReady = true }`. So **LocationService** is created on main thread when the route section is about to be shown (init includes `loadRecentLocations()`: UserDefaults read + JSON decode). |
| Route section visible | `CreateRideView.swift` | `if locationServiceReady` (38–64) | Two `LocationAutocompleteField` views are built. Each has `private let locationService = LocationService.shared` (reference only; singleton already exists). |
| First tap into Pickup field | `LocationAutocompleteField.swift` | `TextField` with `.focused($isFocused)` (61–62) | SwiftUI sets `isFocused = true` → `onChange(of: isFocused)` (141–193) runs **synchronously** on main thread. |
| Focus handler (focused == true) | `LocationAutocompleteField.swift` | 141–193 | **Sync:** signpost begin, log, create `Task { @MainActor in ... }`, signpost end / log exit. **No** read of `recentLocations` or `showDropdown` in the sync path; dropdown work is **deferred** inside the Task. |
| Deferred work (async) | Same | Task body (160–187) | After ~100 ms sleep (`Constants.Timing.locationDropdownAfterFocusNanoseconds`): read `locationService.recentLocations`, set `recentLocationsSnapshot`, set `showDropdown`. Then signpost end. |
| User types (optional) | `LocationAutocompleteField.swift` | `onChange(of: text)` (63–65) → `performSearch` (201–262) | 300 ms debounce → `locationService.searchPlaces(query)` (MapKit); results in `completerDidUpdateResults`; we set `predictions` on main. |

**Conclusion:** On first tap into the pickup field, **synchronous** app work is: focus handler entry (signposts + spawning one Task). The 2–4 s stall is either (1) **before** our handler runs (system: hit-testing, focus change, keyboard start) or (2) **after** our handler returns, before the deferred Task runs (main thread blocked by something else) or (3) **system** keyboard/RTI initialization. The existing “gesture gate timed out” fix moved dropdown work off the critical path; if the stall remains, Time Profiler will show whether the long slice is in our code or in system frameworks.

---

### 1.C Other places that could run on “first text input”

- **CreateRideView:** `@StateObject CreateRideViewModel` — init is lightweight (no LocationService). `trackScreen("CreateRide")` on appear (lightweight).
- **LocationService.init** (when first used): `loadRecentLocations()` is synchronous (UserDefaults + JSON decode). That runs when CreateRideView’s `onAppear` Task touches `LocationService.shared`, **not** on first tap into the field (by then the singleton already exists).
- **Validation / analytics / formatting:** No `onChange(of: focus)` or tap handlers on login fields; no synchronous validation or analytics on first focus for pickup (dropdown is deferred).
- **MessageInputBar** (ConversationDetailView): holds `LocationService.shared`; if the user never opened Create Ride, first use of LocationService could be there, but that’s not the “first tap into Pickup” path.

---

## 2. Time Profiler capture plan

Use **Xcode → Product → Profile → Time Profiler** (or Instruments → Time Profiler). Record only the main thread during the tap; use call tree to find the dominant stack.

### Scenario A — General “first text input / keyboard warm-up”

**Goal:** See if the first-ever tap into any text field (e.g. login email) stalls due to system or app.

1. **Setup:** Cold launch (kill app, launch from Xcode or Profile). Use **Debug** build so signposts are present.
2. **Optional — Points of Interest:** In Time Profiler, enable **Points of Interest** (or add the “Signpost” template). Filter by your app’s subsystem (e.g. `com.naarscars`) to see “LoginEmailFocus” (DEBUG) or system events.
3. **Sequence:**  
   - Start recording.  
   - Wait for login (or first screen with a simple text field).  
   - **Tap once** into the email (or first) text field.  
   - Wait until keyboard is fully up and you can type.  
   - Stop recording.
4. **Call tree (main thread):**  
   - **Separate by thread:** yes; select **Main** thread.  
   - **Invert call tree:** yes (so the leaf/time-heavy frames are at top).  
   - **Focus on main thread:** use the thread selector; hide other threads if needed.  
   - **Hide system libraries:** first run **with** system libs to see if the long slice is in UIKit/TextInput/RTI/Keyboard; then toggle **Hide System Libraries** to see if any app code appears in the hot path.  
5. **Interpretation:**  
   - If the **long slice** (2–4 s) is in **UIKit, TextInput, RTI, Keyboard**, or other system frameworks → treat as **system warm-up**.  
   - If the long slice is in **our code** (e.g. `LocationService`, `LoginView`, view body, `onChange`) → treat as **our code** and fix the specific function.

---

### Scenario B — Pickup location (Create Ride)

**Goal:** Isolate stall when tapping “Pickup location” (address autocomplete).

1. **Setup:** Cold launch, **Debug** build.
2. **Sequence:**  
   - Start recording.  
   - Navigate to **Create Ride** (tab or deep link).  
   - Wait until the route section is visible (pickup/destination fields shown).  
   - **Tap once** into **Pickup location**.  
   - Wait until keyboard and (if applicable) dropdown are ready.  
   - Stop recording.
3. **Call tree:** Same as Scenario A (main thread, invert, hide system libs to compare).
4. **Signposts (DEBUG):** In the timeline you should see, in order:  
   - **FocusHandler** (begin) and **FocusGained** (event) when our focus handler runs.  
   - **DeferredDropdown** (begin/end) after ~100 ms when we set `showDropdown`.  
   - If the user types: **DebounceWait**, then **AutocompleteSearch** (begin/end) around `searchPlaces` → first results.
5. **Interpretation:**  
   - **Long gap before FocusHandler begin** → stall is **before** our code (hit-test, focus, keyboard start); likely system.  
   - **Long gap after FocusHandler end, before DeferredDropdown** → main thread blocked by something else (our code or system) before the deferred Task runs; check for “main thread blocked Xms” in console.  
   - **Long slice inside FocusHandler or DeferredDropdown** → our code; identify the stack (e.g. `recentLocations`, layout, Form).

---

## 3. Investigation checklist (answer with trace evidence)

- **A) Is there a consistent main-thread “long slice” starting at the tap?**  
  Yes → note start/end time and whether it aligns with “FocusGained” / “FocusHandler” or is entirely before/after.

- **B) What stack frames dominate that slice?**  
  - If **UIKit / TextInput / RTI / Keyboard**: confirm system warm-up; consider mitigations (§5.B).  
  - If **our functions**: note file and function (e.g. `LocationAutocompleteField.body`, `LocationService.loadRecentLocations`, `onChange(of: isFocused)`); explain why they run on focus.

- **C) Extra synchronous work at first focus?**  
  Check for: layout thrash, geocoding, disk I/O, DB reads, JSON decode, network waits, locks, `@MainActor` work, observers/subscriptions. From code: we **do not** do recents read or dropdown update synchronously in the focus handler; we **do** touch LocationService on Create Ride **onAppear** (init + loadRecentLocations). If the stall is on **first tap** and not on **screen appear**, the trace will show whether the long slice is in init or in the focus path.

- **D) “Gesture gate timed out” vs our work vs system:**  
  If the console shows “gesture gate timed out,” correlate with the trace: is the main thread busy in **our** code (e.g. Form layout, dropdown body) at that time, or in **system** (keyboard/RTI)? Our fix already defers dropdown; if the timeout persists, the blocker is either system or another app path (e.g. Form re-render).

---

## 4. Instrumentation (DEBUG-only)

Lightweight signposts to correlate the tap window in Time Profiler:

| Location | Signpost / log | Purpose |
|----------|----------------|---------|
| Login email focus | `os_signpost(.event, "LoginEmailFocus")` | Mark “app saw focus” for Scenario A. Implemented in `LoginView.swift` (DEBUG). |
| LocationAutocompleteField focus | `os_signpost(.begin/end, "FocusHandler")`, `os_signpost(.event, "FocusGained")` | Align “focus handler entry” and “focus gained” point. Implemented in `LocationAutocompleteField.swift`. |
| LocationAutocompleteField deferred dropdown | `os_signpost(.begin/end, "DeferredDropdown")` | See when deferred work runs; gap vs FocusHandler = main-thread blockage. |
| LocationAutocompleteField search | `os_signpost(.begin/end, "AutocompleteSearch")` | Interval for “query dispatched” → “first results applied.” Implemented in `performSearch`. |
| Console | `[LocationPerf]` logs, “main thread blocked Xms” | Correlate with timeline; confirm if deferred task is delayed. |

All behind `#if DEBUG`; no behavior change in Release.

---

## 5. Fix plan

### 5.A If the stall is OUR code

- **LocationService.init / loadRecentLocations on main:**  
  - Move `loadRecentLocations()` off the sync init: e.g. start a single async task that loads recents and assigns `recentLocations` on the main actor. Init only sets up `MKLocalSearchCompleter`.  
  - **Risk:** Recents may be empty for one frame after first use.  
  - **Where:** `LocationService.swift` init: remove the `loadRecentLocations()` call; kick off a `Task { @MainActor in loadRecentLocations() }` (or equivalent) once.  
  - **Minimal change (snippet):** In `LocationService.init()`, replace the synchronous `loadRecentLocations()` call with:
    ```swift
    // In init(), after searchCompleter.region = seattleRegion:
    Task { @MainActor in
        loadRecentLocations()
    }
    ```
    and ensure `loadRecentLocations()` is only invoked once (it already just reads UserDefaults and sets `recentLocations`).

- **Heavy work in focus handler or body:**  
  - If the trace shows layout or body evaluation (e.g. Form, dropdown) in the hot path, reduce work: avoid reading `ObservableObject` in body (we already use `recentLocationsSnapshot`), or further defer non-critical updates.

- **CreateRideView onAppear:**  
  - We already defer LocationService touch to a Task; if the trace shows init still blocks the first frame, consider touching `LocationService.shared` even earlier (e.g. after auth, idle) so that by the time the user opens Create Ride, init is done.

### 5.B If the stall is SYSTEM (keyboard / RTI / TextInput warm-up)

Two safe mitigation options:

**Option 1 — Pre-warm text input at a non-invasive moment**  
- **What:** Once the app is idle (e.g. after main tab is visible), create a hidden text field, make it first responder, then resign (or present/dismiss a tiny VC with a text field). This warms the keyboard/RTI so the “first” tap is not the real first.  
- **Pros:** Can remove most of the 2–4 s on the user’s first real tap.  
- **Cons:** Slightly more work at launch; must be done at a moment that doesn’t steal focus from the user (e.g. short delay after first screen).  
- **Risk:** Low if done off the critical path and hidden.

**Option 2 — Defer expensive UI until after keyboard is active**  
- **What:** Avoid presenting heavy UI (e.g. large lists, complex layout) in the same run-loop turn as first focus. We already defer the dropdown by 100 ms; ensure no other heavy work runs synchronously in the focus path.  
- **Pros:** Reduces contention; no pre-warm needed.  
- **Cons:** May not remove the full 2–4 s if the cost is purely system warm-up.  
- **Risk:** Low.

**Tunables:**  
- `Constants.Timing.locationDropdownAfterFocusNanoseconds` (100 ms): keep as-is unless “gesture gate timed out” returns; then consider increasing slightly. Do not decrease without measuring (could bring back gesture timeout).

---

## 6. Verification plan

- **Before/after metrics:**  
  - Time from **tap** to **keyboard visible and responsive** (manual or automated).  
  - Time from **tap** to **dropdown visible** (pickup scenario); already logged as “focus deferred dropdown done, … ms” in DEBUG.

- **Signposts to compare:**  
  - **FocusGained** (or LoginEmailFocus) → **DeferredDropdown** end: should stay &lt; ~200 ms (our 100 ms sleep + small overhead) if main thread is not blocked.  
  - **FocusGained** → keyboard usable: if this drops after a pre-warm (Option 1), system warm-up is confirmed.

- **Success:**  
  - **Our-code fix:** Long slice in Time Profiler no longer in our code; “main thread blocked Xms” (if any) disappears or is &lt; 100 ms.  
  - **System mitigations:** First-tap-to-keyboard time reduced (e.g. &lt; 500 ms) without regressing gesture gate or dropdown behavior.

---

## 7. Summary

| Scenario | First-focus code path | Likely stall source |
|----------|------------------------|----------------------|
| Login | None (no focus handler) | System keyboard/RTI |
| Pickup (Create Ride) | Focus handler (sync: signpost + spawn Task); dropdown deferred | System or main-thread blockage before deferred Task |

Use Time Profiler with the steps in §2 and the checklist in §3 to assign the dominant stack to “our code” vs “system,” then apply §5.A or §5.B and verify with §6.
