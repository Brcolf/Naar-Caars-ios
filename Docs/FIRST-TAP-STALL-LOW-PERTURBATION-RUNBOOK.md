# First-tap stall — low-perturbation diagnosis runbook

When the 2–4 s first-tap text-input stall **disappears with Time Profiler attached** (Heisenbug), use these approaches that avoid attaching the full profiler.

---

## 1. Investigation approaches (no Time Profiler)

| Approach | Perturbation | What you get |
|----------|--------------|--------------|
| **DEBUG timing logs** | Minimal (one print per event) | Deltas: focus_delivered → deferred_dropdown_done → keyboard_visible. Confirms whether the stall is before focus, between focus and dropdown, or between focus and keyboard. |
| **Instruments Points of Interest only** | Low (signpost instrumentation only) | Timeline of FocusGained, FocusHandler, DeferredDropdown, LoginEmailFocus. May still warm the system; try if stall persists. |
| **MetricKit hang diagnostics** | None (OS delivers after the fact) | If the main thread is blocked >~1 s, the OS may deliver an MXHangDiagnostic with call stack. Check logs after reproducing (see §4). |
| **Spindump / Pause** | Low (single snapshot) | Main-thread backtrace at the moment you pause or signal. Shows what’s blocking **right then** (system vs app). |

---

## 2. DEBUG instrumentation (implemented)

**What was added (DEBUG only, no behavior change):**

- **FirstTapPerfLogger** (in `AppDelegate.swift`, `#if DEBUG`): Session starts at first `focus_delivered`; logs one line per event with `delta_ms` from session start.
- **Events logged:**
  - `focus_delivered source=login|pickup delta_ms=0` — when our focus handler runs (earliest “focus delivered” we can log).
  - `deferred_dropdown_done ... delta_ms=X` — when LocationAutocompleteField’s deferred Task finishes (~100 ms later).
  - `keyboard_visible source=... delta_ms=X` — when `UIResponder.keyboardDidShowNotification` fires; then session clears.

**How to read the logs:**

- **Large delta_ms on `keyboard_visible`** (e.g. 2000–4000 ms) → the stall is **between** focus_delivered and keyboard visible (system keyboard/RTI or something blocking the run loop before the keyboard appears).
- **Large gap before `focus_delivered`** → we can’t timestamp “tap” directly; the stall could be before our handler (hit-test, first responder, system).
- **`deferred_dropdown_done`** should appear at ~100–200 ms delta; if it appears much later, the main thread was blocked before the deferred Task ran (check for “main thread blocked Xms” in `[LocationPerf]` logs).

**Files touched:**

- `AppDelegate.swift`: `FirstTapPerfLogger` enum (DEBUG block at bottom); `FirstTapPerfLogger.startKeyboardObserver()` in DEBUG; MetricKit hang logging in `logHangDiagnosticsIfPresent`.
- `LoginView.swift`: call `FirstTapPerfLogger.logFocusDelivered(source: "login")` when email gains focus (DEBUG).
- `LocationAutocompleteField.swift`: call `logFocusDelivered(source: "pickup")` and `logDeferredDropdownDone(deltaMs:)` (DEBUG).

---

## 3. Step-by-step runbook

### 3.1 Reproduce without Instruments

1. **Build:** Debug scheme, run on **simulator or device** from Xcode (or Archive and run the built app without attaching a debugger if you want even lower perturbation).
2. **Cold launch:** Force-quit the app, then launch.
3. **Scenario A (login):** Tap once into the **email** field. Wait until the keyboard is usable (or 5 s).
4. **Scenario B (pickup):** Navigate to **Create Ride**, tap once into **Pickup location**. Wait for keyboard + dropdown or 5 s.
5. **Console:** In Xcode console (or device logs), filter by `[FirstTapPerf]` and `[LocationPerf]`. Copy the sequence of lines for that run.

**What to note:** The `delta_ms` on `keyboard_visible` is your “focus_delivered → keyboard visible” time. If it’s 2–4 s, the stall is between those two events (and our sync focus handler is already known to be ~2 ms).

---

### 3.2 Points of Interest trace (if the stall still occurs)

If the stall is reproducible **without** Time Profiler, you can try a **Points of Interest** or **Signpost** trace (lighter than full Time Profiler):

1. **Instruments:** Product → Profile → choose **Signpost** or a template that includes **Points of Interest**.
2. Start recording, then reproduce (cold launch → tap into login or pickup).
3. Stop when the keyboard is up.
4. In the timeline, filter by subsystem `com.naarscars` (or `com.naarscars.app` / `com.naarscars.location`). You should see **LoginEmailFocus**, **FocusGained**, **FocusHandler**, **DeferredDropdown**.
5. **Interpretation:** If there’s a long **gap** on the main thread between the tap and **FocusGained**, the stall is before our code. If the gap is between **FocusGained** and the next system event (e.g. keyboard), the stall is in system text-input/keyboard.

---

### 3.3 Spindump / main-thread backtrace when the stall happens

**Option A — Xcode Pause (simulator or device)**

1. Run the app from Xcode (Debug, no Instruments).
2. Reproduce the stall (tap into the text field and leave it frozen).
3. **While the UI is stuck,** click **Debug → Debug Workflow → Pause** (or the Pause button in the debug bar).
4. In the **Debug Navigator** (left), select the **Main** thread.
5. The **call stack** in the editor is the main-thread backtrace at freeze. **Copy the full stack** (right-click → Copy).
5. Resume and stop the run; copy the **`[FirstTapPerf]`** and relevant **`[LocationPerf]`** lines from the console.

**Option B — Simulator: SIGQUIT spindump from host**

1. Reproduce the stall in the Simulator (app appears frozen).
2. On the **Mac**, in Terminal, find the Simulator process for your app:
   - `pgrep -fl "YourAppName"` or list Simulator processes and find the one whose name matches your app.
   - Or use Activity Monitor: find the Simulator app, then the child process that is your app (e.g. `NaarsCars`).
3. Send SIGQUIT to get a spindump on stdout (if the process is attached to Xcode, this may not work; run the app **without** Xcode attached if possible):
   - `kill -QUIT <pid>`
4. The spindump prints in the Terminal (or in Xcode console if the process is debugged). Find the **main thread** section and copy it.

**Option C — Device (no Xcode attached)**

1. Run the app on device (e.g. from home screen), reproduce the stall.
2. Connect the device and capture logs: **Xcode → Window → Devices and Simulators → select device → Open Console**, or use `log stream` / Console.app with the device selected.
3. To get a **main-thread snapshot** you can either:
   - Attach Xcode to the running process (Debug → Attach to Process → pick your app), then **Pause** and copy the main-thread stack, or
   - Rely on **MetricKit hang diagnostics** (see §4) if the hang is long enough and the OS reports it.

---

### 3.4 What to paste back (for diagnosis)

When asking for help or interpreting results, paste:

1. **Main-thread stack** from Pause or spindump (full backtrace).
2. **Timing logs** for that run:
   - All lines containing `[FirstTapPerf]` (focus_delivered, deferred_dropdown_done, keyboard_visible with deltas).
   - Any `[LocationPerf]` lines around the same time (focus gained, deferred dropdown done, “main thread blocked Xms” if present).

---

## 4. MetricKit hang diagnostics — where to look

- **When:** The OS may deliver **MXHangDiagnostic** payloads when the main thread was blocked for a significant time (e.g. >1 s). Delivery is **after the fact** (next launch or when the system sends diagnostics).
- **Where we log:** In **AppDelegate**, `didReceive(_ payloads: [MXDiagnosticPayload])` calls `logHangDiagnosticsIfPresent`. For each `payload.hangDiagnostics` we log:
  - **Tag:** `"performance"` (or the logger you use for MetricKit).
  - **Message:** `"MetricKit HANG[i] duration=X.XXs callStackTree(N bytes): <json preview>..."`.
- **Where to look:** In Xcode console filter by **MetricKit** or **HANG** or your **performance** category. On device, use Console.app or `log stream` and filter by your app and “performance” / “HANG”.
- **Call stack:** The logged payload includes a **callStackTree** JSON preview (first 3000 chars). Full symbolication requires the dSYM and the JSON; you can paste the JSON and the main-thread part into a symbolication workflow. For a quick read, look for **framework names**: e.g. **UIKit, TextInput, RTI, Keyboard** → system; **NaarsCars, SwiftUI** (our code paths) → app.

---

## 5. Interpreting results

| Observation | Likely cause | Next step |
|-------------|--------------|-----------|
| **keyboard_visible delta_ms** is 2000–4000 ms; **focus_delivered** and **deferred_dropdown_done** are ~0 and ~100 ms | Stall is **after** our handler, **before** keyboard visible → **system** (keyboard/RTI/TextInput warm-up). | Pre-warm text input when app is idle; avoid competing UI at first focus (see FIRST-TAP-STALL-TIME-PROFILER-RUNBOOK.md §4). |
| Main-thread stack is mostly **UIKit, TextInput, RTI, Keyboard**, CoreGraphics, etc. | **System** text-input/keyboard path. | Same mitigations as above. |
| Main-thread stack shows **NaarsCars**, **SwiftUI** (e.g. Form, body, layout), or our types | **Our code** in the hot path. | Identify the top frame (file/function) and apply the minimal fix from FIRST-TAP-STALL-INVESTIGATION.md §5 (e.g. defer work, reduce body work). |
| **“main thread blocked Xms before deferred dropdown ran”** in [LocationPerf] | Something blocked the main thread **after** focus_delivered, **before** our deferred Task ran. | Use Pause/spindump at freeze to capture the main-thread stack; then classify system vs app and fix accordingly. |

---

## 6. Quick reference

**FirstTapPerfLogger** is defined in `AppDelegate.swift` inside `#if DEBUG`, so it has no effect in Release. No separate file or Xcode target change is required.
