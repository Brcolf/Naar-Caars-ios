# Town Hall SwiftData Integration Design

## Summary
Implement a SwiftData-backed, local-first data layer for Town Hall posts, comments, and votes. The UI loads local data immediately, uses realtime payloads to update SwiftData in place, and performs background reconciliation with the network for accuracy. Writes remain network-first.

## Goals
- Local-first feed rendering for Town Hall posts.
- SwiftData persistence for posts and comments.
- Realtime events update local store immediately and reconcile in background.
- Network-first create/delete/vote actions.
- Author snapshot cached in SwiftData; vote counts computed on demand.

## Non-goals
- Offline-first creation of posts, comments, or votes.
- Persisting vote aggregates in SwiftData.
- Large-scale refactors outside Town Hall.

## Decisions
- Scope: posts + comments + votes.
- Local-first: show SwiftData first when available; otherwise fetch network and persist.
- Realtime: apply payload immediately, then background refresh.
- Writes: network-first only.
- Joined fields: store author snapshot, compute votes on demand.

## Architecture
### SwiftData Models
Add SwiftData models to `SDModels.swift`:
- `SDTownHallPost`: persisted post fields plus cached author snapshot (name, avatar URL), comment count, and created/updated timestamps.
- `SDTownHallComment`: persisted comment fields plus cached author snapshot and parent relationship metadata.

### Repository Layer
Introduce `TownHallRepository` to encapsulate SwiftData access:
- Read APIs: `getPosts()`, `getPostsPublisher()`, `getComments(postId:)`.
- Write APIs: `upsertPosts(_:)`, `upsertComments(_:)`, `deletePost(id:)`, `deleteComment(id:)`.
- Mapping helpers between network models and SwiftData models.

### Sync + Realtime
Create `TownHallSyncEngine` (or extend repository responsibilities) to:
- Subscribe to realtime channels for `town_hall_posts` and `town_hall_comments`.
- Apply realtime insert/update/delete payloads directly into SwiftData.
- Trigger a throttled background refresh for reconciliation.
- Treat vote realtime as a trigger to refresh vote aggregates in memory.

## Data Flow
### Feed Load
1. Fetch local posts from SwiftData.
2. If local is empty, fetch from network and persist.
3. If local exists, render immediately and sync in background.

### Pagination
Use network pagination to fetch more posts and persist them into SwiftData.

### Comments
Load comments local-first for a post, then refresh in background. Store comments in SwiftData keyed by `postId`.

### Votes
Vote actions are network-first. On success, refresh vote aggregates for the affected post/comment in memory. Vote counts are not persisted.

## Error Handling
- Repository throws `AppError.processingError` for UI handling.
- Realtime parsing failures are logged and ignored.
- Background sync errors are logged without wiping local data.

## Testing
- Repository mapping tests: SwiftData <-> network model round-trip.
- View model tests: local-first rendering and background refresh.
- Realtime tests: direct handler calls update SwiftData and publisher outputs.

## Rollout
- Add SwiftData models and repository.
- Update Town Hall view models to load from SwiftData first.
- Wire realtime handlers to SwiftData updates.
- Validate vote refresh behavior remains correct.
