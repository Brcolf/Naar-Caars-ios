# Message Reply Threading (iMessage-Style) Design
Date: 2026-01-30  
Status: Draft  
Owner: Messaging

## Goals
- iMessage-style reply threading with a subtle main-thread spine.
- Reply preview tap opens a full-screen thread view.
- Thread view shows a pinned parent message and a replies list.
- Preserve sender-name header rules from the main thread.
- Clear input on send regardless of delivery; retry happens in-message.

## Non-Goals
- Schema changes (reply support already exists).
- Nested message blocks in the main thread.
- Replacing the current optimistic send / retry handling.

## UX Summary
Main thread stays flat. Replied messages render the existing reply preview plus a subtle vertical spine linking consecutive replies to the same parent. Tapping the reply preview opens a full-screen thread view with a blurred background, a pinned parent bubble at the top, and a scrollable list of replies below.

Nested replies are handled by sub-threads: if a reply itself has replies, tapping its reply preview opens that sub-thread (full-screen) and focuses only on that branch.

## Interaction Details
- Tap reply preview on a message to open thread view for its parent.
- Thread view includes a close button and optional title.
- Replying from the thread view always uses `reply_to_id = parentId`.
- Input clears immediately on send; failures are retried from the message row.

## Data Flow
1) Fetch parent via `fetchMessageById(parentId)` (includes sender join).  
2) Fetch replies via `fetchReplies(conversationId, parentId)`:
   - `reply_to_id = parentId`
   - ordered by `created_at` ascending
3) Attach reactions and reply contexts the same way `fetchMessages` does.
4) Seed from locally loaded conversation messages when available, then refresh from network.

## UI Components
- **ThreadSpineView**: thin, rounded vertical line aligned to the reply preview edge.
- **MessageThreadView** (new): full-screen modal with blur background.
  - Header with close button.
  - Pinned parent bubble (uses `MessageBubble` to keep sender-name behavior).
  - Replies list (uses `MessageBubble` and series rules).

## Main Thread Spine Rules
For each message with `reply_to_id`:
- If previous message has the same `reply_to_id`, extend the spine upward.
- If next message has the same `reply_to_id`, extend the spine downward.
- Align to the reply preview edge (leading for received, trailing for sent).

## Error Handling
- Parent missing/unavailable: show banner and disable reply input.
- Replies fetch fails: show retry button, keep parent visible.
- Send failure: input stays cleared; optimistic row shows retry state.

## Testing
- UITest: tap reply preview opens thread view.
- UITest: thread view shows pinned parent + replies.
- Unit: `fetchReplies` returns only matching `reply_to_id` sorted by time.
- Visual QA: spine alignment (sent/received), group sender names.

## Accessibility
- Reply preview is a button with label "Open thread".
- Thread view close button labeled "Close thread".
