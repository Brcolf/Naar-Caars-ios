# App Issues & Broken Functionality Report

During the exhaustive review of the messaging and notification system, several unrelated or peripheral issues were identified that could impact the overall stability and user experience of the app.

## 1. Database & Network Efficiency
- **N+1 Query Pattern in `MessageService`:**
  - `fetchConversations` performs multiple parallel requests per conversation to fetch last messages, unread counts, and participants. While parallelized via `TaskGroup`, this is still highly inefficient for users with many conversations and will likely hit rate limits or cause slow load times on poor connections.
- **Sequential Read Receipt Updates:**
  - `markAsRead` in `MessageService` iterates through unread messages and performs a separate update request for each. This should be a single batch update using an `.in()` filter.

## 2. Navigation & UI Consistency
- **Highlight State Persistence:**
  - In `RideDetailView` and `FavorDetailView`, the `highlightedAnchor` is cleared via a `Task.sleep` timer. If the user navigates away from the view and returns before the timer expires, the highlight might still be active or behave unexpectedly because the task is not tied to the view's lifecycle properly (though it is cancelled in `highlightSection`, it isn't cancelled on `onDisappear`).
- **Navigation Coordinator Reset:**
  - `NavigationCoordinator.resetNavigation()` clears all navigation states. If a deep link is processed while the user is in the middle of a multi-step flow (like editing a ride), they will lose their progress as the tab and view state are forcefully reset.

## 3. Realtime & Caching
- **Realtime Enrichment Flicker:**
  - When a new message arrives via realtime, the payload does not contain the sender's profile or reply context. The app then calls `fetchMessageById`. This results in a "flicker" where the message bubble appears with a placeholder avatar or name, which then "pops" into the correct data a moment later.
- **Cache Invalidation Thrashing:**
  - Realtime listeners call `invalidateNotifications` or `invalidateConversations` immediately upon receiving an event. In a busy group chat or during a burst of notifications, this causes the app to wipe its cache and re-fetch from the network dozens of times per second.

## 4. Potential Logic Errors
- **`MessageService.getOrCreateDirectConversation`:**
  - The logic to find an existing DM iterates through *all* of a user's conversations and then performs *another* query for participants for each one. This is an `O(N^2)` network operation that will become unusable as a user's conversation list grows.
- **Admin Permission Check in `MessageService`:**
  - `addParticipantsToConversation` checks if a user is a participant by querying `conversation_participants`. However, it doesn't account for the `left_at` column in all check paths, potentially allowing a user who has left a conversation to still add others to it.

## 5. UI/UX "Papercuts"
- **"Mark All Read" UI Lag:**
  - Tapping "Mark All Read" in the notifications list sends a network request but does not optimistically clear the unread dots in the UI. The user sees the dots persist for 1-2 seconds until the network request completes and the list reloads.
- **Missing Block Flow:**
  - In `ReportMessageSheet`, there is a "Block this user" button marked with a `TODO`. This means users currently have no way to immediately block someone they are reporting for harassment.


