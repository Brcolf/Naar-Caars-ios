# Completion + Review Prompt Flow Design

## Goals
- Move completion acknowledgement to the claimer, not the requestor.
- Show completion and review prompts as global, non-dismissible modals.
- Trigger completion prompts 1 hour after scheduled request time.
- Trigger review prompts immediately after claimer confirmation.
- Clear completion notifications only after claimer action; clear review notifications on prompt display.
- Support rides and favors, and handle multiple prompts one at a time, oldest first.

## Architecture
- **PromptCoordinator (singleton, @MainActor)** owns a prompt queue and the currently active prompt. It fetches prompt candidates on app entry and reacts to notification-driven triggers.
- **CompletionReminderService** fetches due completion reminders for the current claimer from `completion_reminders` and resolves request titles.
- **ReviewPromptSource** uses unread `review_request`/`review_reminder` notifications as the source of truth and resolves request details (title, fulfiller).
- **MainTabView** presents prompts with a `fullScreenCover(item:)` driven by `PromptCoordinator.activePrompt`.
- **CompletionPromptView** and **ReviewPromptSheet** are non-dismissible and are the only way to resolve prompts.

## Data Flow
1. **App entry** → `PromptCoordinator.checkForPendingPrompts()`:
   - Fetch due completion reminders for the claimer (`scheduled_for <= now`, `completed = false`).
   - Fetch unread review notifications and filter by the 7-day review window.
   - Merge into one queue, sorted by `scheduled_for` / `created_at` (oldest first).
2. **Push/in-app notification tap**:
   - Navigate to request detail first.
   - Enqueue the appropriate prompt (completion or review) and show it on top.
3. **Foreground push arrival**:
   - Enqueue prompt immediately without navigation (modal overlays current screen).

## Notification + Badge Handling
- **Completion prompts**:
  - Do not mark `completion_reminder` notifications read on display.
  - After user taps **Confirm** or **Not yet**, call `handle_completion_response`.
  - Then mark related `completion_reminder` notifications read and refresh badges.
- **Review prompts**:
  - Mark related `review_request`/`review_reminder` notifications read as soon as the modal is shown.
  - Refresh badges immediately after marking read.

## Error Handling
- If prompt fetch fails, log and keep any existing queue intact.
- If review is outside the 7-day window, mark review notifications read and skip the prompt.
- If a completion reminder cannot be resolved to a request, drop it and continue.

## Testing
- Prompt queue ordering and de-duplication (oldest-first across types).
- Completion prompt action marks notifications read only after response.
- Review prompt marks notifications read on display.
- Review prompt eligibility uses 7-day window and no 30-minute delay.
- Build verification via `xcodebuild build` (tests may be flaky due to extra test files).

