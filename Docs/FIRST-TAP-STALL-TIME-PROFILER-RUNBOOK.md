# First-tap stall — Time Profiler runbook and report template

**Context (trusted):** Login = plain TextField/SecureField, no focus handler in release. Pickup = LocationAutocompleteField defers dropdown to a ~100ms Task; no heavy sync work on focus. LocationService init ~4ms. Logs show large gap after “focus gained” + “System gesture gate timed out” → main thread blocked by system text-input warm-up or other sync work.

**Note:** I cannot run Xcode Instruments from this environment. You run the two traces below and fill the report (§3). Use this runbook for exact steps and classification rules.

---

## 1. How to capture the traces

### Build and target
- **Scheme:** NaarsCars, **Debug** (so DEBUG signposts are present).
- **Run:** Product → Profile → choose **Time Profiler** (or Instruments → Time Profiler).
- **Target:** Simulator or device; **cold launch** for each scenario (quit app fully, then start recording and launch).

### Scenario A — Login email (first tap into any text field)
1. Start recording in Time Profiler.
2. Launch app (cold). Reach **login** (unauthenticated).
3. **Tap once** into the **email** text field.
4. Wait until the **keyboard is visible and you can type** (or ~5s if it hangs).
5. Stop recording.

### Scenario B — Pickup location (Create Ride)
1. Start recording in Time Profiler.
2. Launch app (cold). Sign in if needed, then **navigate to Create Ride** (tab/deeplink).
3. Wait until the **route section is visible** (Pickup location + Destination fields).
4. **Tap once** into the **Pickup location** field.
5. Wait until **keyboard + dropdown** are usable (or 5s), then stop recording.

### Call tree (both scenarios)
- **Display:** Call Tree.
- **Separate by thread:** Yes.
- **Select:** **Main** thread only (click the main thread row so the call tree is for that thread).
- **Invert Call Tree:** Yes (heaviest leaves at top).
- **Do NOT hide system libraries at first.** Inspect the **top (dominant) stacks** and note whether they are in system frameworks or app code.
- **Then** toggle **Hide System Libraries** and note whether any **app** (NaarsCars) frames remain at the top of the list. If they do, those are our-code hotspots.

### Finding the “stall” window
- In the timeline, locate the **2–4 s period** where the main thread is busy (solid bar) and the UI is unresponsive.
- **Option A:** Use the range selector to select that interval; the call tree will show only that range.
- **Option B:** Note the approximate start time (e.g. “right after tap”). The “stall” is the contiguous main-thread busy segment that starts at tap and lasts 2–4 s.
- The **dominant stack** for that segment is what you report as “top main-thread stacks during the stall.”

---

## 2. Correlating with DEBUG signposts

In Time Profiler, enable **Points of Interest** (or the Signpost instrument) so you see our events. Subsystem filter: `com.naarscars` (or `com.naarscars.app` / `com.naarscars.location`).

| Signpost / event | When it fires |
|------------------|----------------|
| **LoginEmailFocus** | App saw focus on login email (Scenario A). |
| **FocusGained** (event) | App saw focus on LocationAutocompleteField (Scenario B). |
| **FocusHandler** (interval begin/end) | Sync focus handler in LocationAutocompleteField. |
| **DeferredDropdown** (interval begin/end) | Deferred Task: after ~100ms, read recents + show dropdown. |
| **AutocompleteSearch** (interval begin/end) | From query dispatch to first results applied (only if user typed). |

**Answer for the report:**
- Does the **long main-thread slice start BEFORE or AFTER** the **FocusGained** (or LoginEmailFocus) event?
  - **Before** → stall is in system (hit-test, first responder, keyboard/RTI) or in SwiftUI before our handler.
  - **After** → stall overlaps our handler or runs after it (e.g. layout/observers).
- Does the long slice **overlap** **AutocompleteSearch**? (Only relevant in Scenario B if you typed.) If yes, MapKit/search may be contributing; if no, the stall is not the autocomplete query.

---

## 3. Report template (fill after each trace)

### Scenario A — Login email

| Item | Your result |
|------|-------------|
| **Top main-thread stacks during stall** (copy 5–10 frames, heaviest first) | _Paste or list_ |
| **Classification** | [ ] **SYSTEM** (UIKit / TextInput / RTI / Keyboard / etc.) \| [ ] **APP** (NaarsCars / SwiftUI body / our types) |
| **Long slice vs LoginEmailFocus** | Long slice starts [ ] before \| [ ] after LoginEmailFocus |
| **Recommended next step** | _One line_ |

---

### Scenario B — Pickup location

| Item | Your result |
|------|-------------|
| **Top main-thread stacks during stall** | _Paste or list_ |
| **Classification** | [ ] **SYSTEM** \| [ ] **APP** |
| **Long slice vs FocusGained** | Long slice starts [ ] before \| [ ] after FocusGained |
| **Overlap with AutocompleteSearch?** | [ ] Yes (user typed) \| [ ] No / N/A |
| **Recommended next step** | _One line_ |

---

## 4. If the stall is SYSTEM-dominated

Apply these only if the trace shows the dominant stack in system frameworks (e.g. UIKit, TextInput, RTI, keyboard).

### (a) Pre-warm text input (non-invasive)

- **Idea:** Warm the text-input path once when the app is idle so the “first” tap is not the real first.
- **Where:** One-time, after main UI is visible and idle (e.g. **MainTabView** when the tab view first appears, or **ContentView** when `authState == .authenticated` and a short delay has passed). Do **not** run on login screen (would steal focus).
- **How:** Use a tiny, invisible text field that becomes first responder then resigns immediately (e.g. in a hidden overlay or a 0x0 frame), or use a single `UITextField` in a UIKit bridge that you make first responder then resign. Run once per process (e.g. `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)` with a `hasWarmed` flag).
- **Measurement:** Compare tap → keyboard usable **before** vs **after** pre-warm (same scenario, cold launch). Target: first real tap &lt; ~500 ms.
- **Risks:** Slight extra work at launch; if done too early or visibly, could briefly affect UX. Keep it off the critical path and invisible.

**Optional pre-warm code sketch (use only if trace is SYSTEM):** In **MainTabView**, run once after a delay (e.g. 1.5 s) when the tab view is on screen. One approach: add a hidden `TextField` in a `.background()` or overlay, with `@FocusState private var prewarmFocused`. In `.onAppear` (or `.task`), after `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)` and a `hasTextInputWarmed` flag, set `prewarmFocused = true` then immediately (e.g. 50 ms later) `prewarmFocused = false`. **Risk:** Keyboard may briefly flash; prefer doing this only in DEBUG or behind a feature flag until validated. A more invisible option is a one-off UIKit bridge: create a `UITextField`, add to the window, `makeFirstResponder`, then `resignFirstResponder` and remove (e.g. from a small helper called from MainTabView after delay).

### (b) Avoid competing UI work at first focus

- **Idea:** Don’t present heavy UI or run heavy layout/animations in the same run-loop turn as first focus.
- **What we already do:** LocationAutocompleteField defers dropdown (Task + 100 ms); no sync recents read in focus handler; dropdown uses a snapshot so body doesn’t read `LocationService.recentLocations`. CreateRideView doesn’t present sheets or push new VCs on focus.
- **Check:** Ensure no other observers (e.g. `onChange`, `onReceive`) fire synchronously when the text field gains focus and do heavy work. Time Profiler will show if any app code dominates; if it’s Form/body or a view update, we reduce work there.
- **Risk:** Low; mostly an audit.

### (c) Dropdown deferral timing

- **Current:** `Constants.Timing.locationDropdownAfterFocusNanoseconds` = 100 ms.
- **Only change with measurement:** If “gesture gate timed out” returns, consider **increasing** slightly (e.g. 150 ms). Do **not** decrease without measuring (can bring back timeouts).
- **Risk:** Slightly later dropdown; tune only if needed.

---

## 5. If the stall is APP-dominated

If the **top stacks** are in our code (NaarsCars, SwiftUI view bodies, Form, etc.), identify the **exact function/file** from the call tree. Common suspects:

- **SwiftUI Form / body** recompute when focus changes (layout, list diffing).
- **Expensive computed properties** in view body (e.g. reading large state or doing work in a getter).
- **@Published storms** (many observers updating on one state change).
- **Synchronous reads** in property wrappers or in body (e.g. reading a singleton or UserDefaults).
- **Geocoding / network** kicked off by a state change that coincides with focus (e.g. `onChange(of: text)` or similar).
- **Locks** on shared singletons (main thread waiting on a lock held by another thread).

**Minimal fix pattern:** Once you have the **top stack frame** (e.g. `LocationService.loadRecentLocations`, or `CreateRideView.body`, or `LocationAutocompleteField.body`):

- **If LocationService.init / loadRecentLocations:** Defer loading off init (see FIRST-TAP-STALL-INVESTIGATION.md §5.A). Snippet:

```swift
// LocationService.init(), after searchCompleter.region = seattleRegion:
Task { @MainActor in
    loadRecentLocations()
}
// Remove the direct loadRecentLocations() call from init.
```

- **If Form/body or view body:** Reduce work in that body (e.g. avoid reading ObservableObject in body for the dropdown; we already use a snapshot). If a specific subview is hot, break it out or cache so it doesn’t recompute on focus.
- **If another specific function:** Move the work off the sync path (e.g. defer to next run loop or a short-delay Task) or off the main thread if safe.

---

## 6. Verification plan

- **Signpost intervals to compare before/after fix:**
  - **FocusGained** (or LoginEmailFocus) → **DeferredDropdown** end: should stay on the order of ~100–200 ms (our deferral + small overhead). If it’s &gt;500 ms, main thread was blocked before the deferred Task ran.
  - **FocusGained** → keyboard usable (manual or automated): target **&lt; 500 ms** after mitigations if the cause was system warm-up; for app fixes, target “no long slice in our code” and same or better tap-to-keyboard.

- **Success criteria:**
  - **SYSTEM:** First tap → keyboard usable in **&lt; 500 ms** (with pre-warm or no competing work), no “gesture gate timed out.”
  - **APP:** Time Profiler shows **no** 2–4 s main-thread slice in app code; FocusGained → DeferredDropdown end **&lt; 200 ms**; tap-to-keyboard improved or unchanged.

- **How to measure tap → keyboard:** Manual stopwatch, or a simple test that records timestamp at tap (e.g. in a DEBUG tap gesture) and when keyboard window is visible (or when first key input is accepted), then compare before/after.

---

## 7. Quick classification rules

| Observation | Classification | Next step |
|-------------|----------------|-----------|
| Top stacks are UIKit, TextInput, RTI, Keyboard, CoreGraphics, etc. | **SYSTEM** | Apply §4 (pre-warm and/or no competing UI); measure tap→keyboard. |
| Top stacks are in NaarsCars (e.g. LocationService, CreateRideView, LocationAutocompleteField, Form) | **APP** | Apply §5; fix the specific function (defer or reduce work). |
| Long slice **starts before** FocusGained / LoginEmailFocus | **SYSTEM** (or SwiftUI/UIKit before our handler) | Pre-warm and avoid competing UI. |
| Long slice **starts after** FocusGained and is in our code | **APP** | Fix the hot function. |

After you run Scenario A and B and fill §3, you can paste the “Top main-thread stacks” and classification here (or in a follow-up); then the exact fix (file + snippet) can be chosen from §4 or §5.
