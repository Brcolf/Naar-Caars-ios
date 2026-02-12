# Message View: Scroll & Keyboard UX Fix Plan

**Goal:** Make opening a conversation and using the keyboard feel like iMessage/WhatsApp: no jumpy scroll, latest message in view at the bottom, keyboard pushing content up so messages stay visible above the keyboard.

**Date:** February 6, 2026

---

## 1. Current Behavior vs Desired (iMessage/WhatsApp)

| Scenario | Current | Desired |
|----------|--------|--------|
| **Open conversation** | Messages jump up/down until settling; latest message often not in view at bottom | Scroll is stable; view opens with latest message at the bottom, no visible jump |
| **Keyboard opens** | Keyboard appears above existing messages, covering content; input bar may sit in middle of screen | Keyboard appears; scroll content is inset so messages sit above the keyboard and input bar stays at top of keyboard |
| **Focus input** | Scroll-to-bottom runs after 300ms delay; layout can still jump | Content area simply shrinks (inset); no competing scroll animations |
| **Bottom detection** | 1pt spacer `onAppear`/`onDisappear`; can be unreliable | Same or improved via ScrollView behavior |

---

## 2. Root Causes

### 2.1 Jumpiness on open

- **Layout race:** `.task { loadMessages() }` populates `messages`; `onChange(of: viewModel.messages.count)` fires and calls `proxy.scrollTo(..., anchor: .bottom)`. The scroll runs before `LazyVStack` has finished laying out the full list, so:
  - First scroll goes to a not-yet-correct bottom.
  - Later layout passes change content size and scroll position, causing visible jumps.
- **LazyVStack + variable height:** SwiftUI has known issues with variable-height content in `LazyVStack` inside `ScrollView` (stuttering/jumping). Relying on multiple `scrollTo` calls makes this worse.
- **No single “initial anchor”:** There is no use of iOS 17’s `defaultScrollAnchor`, so the scroll view doesn’t start or stay anchored to the bottom by default.
- **Multiple count changes:** Local load then network merge can change `messages.count` more than once, triggering multiple `scrollTo` and “new message” logic (e.g. initial batch incorrectly treated as “new messages” for animation).

### 2.2 Keyboard over content

- **Layout structure:** The screen is a `VStack`: `messagesListView` (ScrollView) then typing indicator then `MessageInputBar`. The input bar is **below** the scroll view, not applied as a bottom inset to the scroll content.
- **Effect:** When the keyboard appears, the system shrinks the window’s safe area. The whole `VStack` is compressed; the keyboard effectively covers the bottom of the scroll view. The scroll view’s content does **not** get a bottom inset, so messages don’t move up; the input bar doesn’t stay pinned to the top of the keyboard.
- **Current “fix”:** `onChange(of: isInputFocused)` scrolls to bottom after 300ms. That doesn’t fix the layout: the scroll view still doesn’t reserve space for the keyboard, so the experience is wrong and can feel jumpy.

---

## 3. Research: Optimal Behavior

- **Keyboard:** Use **`.safeAreaInset(edge: .bottom)`** for the input area (typing indicator + input bar). The scroll view then gets a bottom inset equal to that view’s height. When the keyboard appears, the system increases the bottom safe-area inset, so the scroll content is further inset and stays above the keyboard; the input bar stays above the keyboard. No manual keyboard height or scroll hacks needed.
- **Initial scroll:** On iOS 17+, use **`.defaultScrollAnchor(.bottom)`** so the scroll view starts at the bottom and keeps that anchor when content or size changes (e.g. keyboard). This reduces or removes the need for an explicit `scrollTo` on first load and reduces jumpiness.
- **Scroll-to-bottom on focus:** With `safeAreaInset`, the content area shrinks when the keyboard appears; if we’re already at bottom, we stay at bottom. A single, optional scroll-to-bottom when focusing the field (when `isAtBottom`) can stay, but the 300ms delay can be reduced or removed if we rely on `defaultScrollAnchor` and insets.
- **New messages:** Only treat messages as “new” for animation when `oldCount > 0` and `newCount > oldCount` (i.e. not on initial load from 0→N).

---

## 4. Implementation Plan

### Phase A: Keyboard and layout (iMessage/WhatsApp-like)

**A1. Move input area into `safeAreaInset(edge: .bottom)`**

- **File:** `ConversationDetailView.swift`
- **Change:** Restructure the main body so that:
  - The **scroll view** (messages list) is the main content.
  - The **typing indicator** and **MessageInputBar** are placed in a **single** `VStack` and passed to `.safeAreaInset(edge: .bottom) { ... }` on the scroll view (or on the view that contains the scroll view so the inset applies to the scroll content).
- **Result:** Scroll view content is inset by the height of typing + input bar. When the keyboard appears, the system adjusts the safe area and the same inset grows, so messages stay above the keyboard and the input bar stays above the keyboard. No manual keyboard observers or padding hacks.

**A2. Apply `defaultScrollAnchor(.bottom)` (iOS 17+)**

- **File:** `ConversationDetailView.swift`
- **Change:** On the `ScrollView` that contains the messages, add `.defaultScrollAnchor(.bottom)`.
- **Result:** The scroll view starts at the bottom and maintains bottom anchor when content or size changes (e.g. keyboard), reducing jumpiness and making “open conversation” and “keyboard appears” feel stable.

**A3. Optional: soften scroll-to-bottom on focus**

- **File:** `ConversationDetailView.swift`
- **Change:** In `onChange(of: isInputFocused)`, when `isFocused && isAtBottom`, either:
  - Keep a single `scrollTo(threadBottomAnchorId, anchor: .bottom)` but consider removing or shortening the 300ms delay (e.g. `DispatchQueue.main.async { ... }` or very short delay) so it doesn’t fight with `defaultScrollAnchor`, or
  - Rely entirely on `defaultScrollAnchor` and remove this scroll when keyboard appears if behavior is already correct.
- **Result:** No double-scroll or delayed jump when focusing the field.

### Phase B: Reduce jumpiness on first load

**B1. One-time initial scroll (if needed)**

- **File:** `ConversationDetailView.swift`
- **Change:**
  - If `defaultScrollAnchor` is enough, no extra logic.
  - If we still want an explicit first scroll (e.g. for edge cases), do it **once** when we have messages and the view has appeared: e.g. `onAppear` + `DispatchQueue.main.async { proxy.scrollTo(threadBottomAnchorId, anchor: .bottom) }` when `!viewModel.messages.isEmpty`, guarded by a `@State private var hasPerformedInitialScroll = false` and set to `true` after running.
- **Result:** At most one programmatic scroll on open; no repeated scrolls as messages stream in.

**B2. Don’t treat initial load as “new messages”**

- **File:** `ConversationDetailView.swift`
- **Change:** In `onChange(of: viewModel.messages.count)`:
  - For “track truly new messages” (entrance animation): only add to `newMessageIds` when `oldCount > 0` and `newCount > oldCount` (so we don’t animate the first batch of 25 as “new”).
  - For “auto-scroll to bottom”: on initial load (e.g. `oldCount == 0`), avoid multiple scrollTo; rely on `defaultScrollAnchor` or the one-time initial scroll from B1.
- **Result:** No flash of “new” animation on first load and no competing scrolls.

**B3. Pagination**

- **Keep:** Existing `anchorMessageId` and scroll-back-to-anchor after loading more; no change needed if behavior is correct.

### Phase C: Polish and edge cases

**C1. Scroll-to-bottom button**

- **File:** `ConversationDetailView.swift`
- **Change:** Ensure the “scroll to bottom” overlay is positioned above the input bar (it’s in an overlay on the scroll view; with `safeAreaInset` the scroll view’s frame is already above the input bar, so the button should remain visible). Verify padding (e.g. `.padding(.bottom, 8)`) still looks good above the inset area.

**C2. Reaction picker and other overlays**

- **File:** `ConversationDetailView.swift`
- **Change:** Confirm overlays (reaction picker, etc.) are still laid out correctly when the keyboard is visible and the main content is in the new inset layout. Adjust any hardcoded `.padding(.bottom, 100)` if the keyboard changes the layout.

**C3. Thread view (MessageThreadView)**

- **File:** Same file or `MessageThreadView` if it exists.
- **Change:** If the thread view has the same VStack + ScrollView + input structure, apply the same pattern: `defaultScrollAnchor(.bottom)` and input in `safeAreaInset(edge: .bottom)` so thread chats behave like the main conversation.

---

## 5. Files to Touch

| File | Changes |
|------|--------|
| `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` | Restructure body with `safeAreaInset(edge: .bottom)` for typing + input bar; add `defaultScrollAnchor(.bottom)`; refine `onChange(messages.count)` (new-message animation + initial scroll); optionally refine/remove delayed scroll on focus; one-time initial scroll if needed; verify overlays. |
| `NaarsCars/Features/Messaging/Views/MessageThreadView` (if present) | Same layout and scroll anchor as above for consistency. |

---

## 6. Testing Checklist

- [ ] Open a conversation with many messages: list opens with latest at bottom, no visible jump.
- [ ] Open a conversation with one or few messages: same stable behavior.
- [ ] Tap input: keyboard appears; messages and input bar move up so messages stay visible and input bar is at top of keyboard (iMessage/WhatsApp-like).
- [ ] Dismiss keyboard: content returns to normal without jump.
- [ ] Send a message: new message appears at bottom and stays in view.
- [ ] Load older messages (scroll to top): scroll position preserved (existing anchor logic).
- [ ] Scroll to bottom button: still visible and tappable; scrolls to bottom correctly.
- [ ] Search and “scroll to result”: still works.
- [ ] Thread view: same keyboard and scroll behavior if applicable.

---

## 7. Summary

- **Keyboard:** Use **`.safeAreaInset(edge: .bottom)`** for typing indicator + input bar so the scroll view is inset and the keyboard pushes content up instead of covering it.
- **Stability:** Use **`.defaultScrollAnchor(.bottom)`** (iOS 17+) so the conversation opens at the bottom and stays anchored, reducing jumpiness.
- **Initial load:** Avoid multiple `scrollTo` and “new message” animation for the first batch; rely on default anchor or one-time scroll.
- **Focus:** Optionally keep a single scroll when focusing the field if needed; avoid long delays so it doesn’t fight the new layout.

This plan aligns the message view with iMessage/WhatsApp-style scroll and keyboard behavior and addresses the jumpiness and “keyboard over messages” issues in one coherent change set.
