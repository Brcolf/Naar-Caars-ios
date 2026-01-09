# Tasks: Town Hall

Based on `prd-town-hall.md`

## Affected Flows

- FLOW_TOWNHALL_001: Post to Town Hall

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/TownHallService.swift` - Town Hall operations
- `Core/Models/TownHallPost.swift` - Post data model
- `Features/TownHall/Views/TownHallFeedView.swift` - Community feed
- `Features/TownHall/Views/TownHallPostRow.swift` - Post display
- `Features/TownHall/Views/CreatePostView.swift` - Post composer
- `Features/TownHall/ViewModels/TownHallFeedViewModel.swift`
- `Features/TownHall/ViewModels/CreatePostViewModel.swift`

### Test Files
- `NaarsCarsTests/Core/Services/TownHallServiceTests.swift`
- `NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift`
- `NaarsCarsTests/Features/TownHall/CreatePostViewModelTests.swift`

## Notes

- Community bulletin board
- Auto-posts for reviews and completions
- ⭐ Rate limit: 30 seconds between posts
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/town-hall`

- [x] 1.0 Create TownHallPost data model
  - [x] 1.1 Create TownHallPost.swift in Core/Models
  - [x] 1.2 Add fields: id, userId, type, content, imageUrl, createdAt
  - [x] 1.3 Create PostType enum (userPost, review, completion)
  - [x] 1.4 Add optional poster Profile
  - [x] 1.5 🧪 Write TownHallPostTests.testCodableDecoding

- [x] 2.0 Implement TownHallService
  - [x] 2.1 Create TownHallService.swift with singleton
  - [x] 2.2 Implement fetchPosts() ordered by createdAt descending
  - [x] 2.3 Add pagination support with limit and offset
  - [x] 2.4 🧪 Write TownHallServiceTests.testFetchPosts_OrderedByDate
  - [x] 2.5 Implement createPost(userId:, content:, imageUrl:)
  - [x] 2.6 ⭐ Add rate limit: 30 seconds between posts
  - [x] 2.7 🧪 Write TownHallServiceTests.testCreatePost_RateLimited
  - [x] 2.8 Implement createSystemPost() for reviews/completions

### 🔒 CHECKPOINT: QA-TOWNHALL-001
> Run: `./QA/Scripts/checkpoint.sh townhall-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: TownHallService tests pass
> Must pass before continuing

- [x] 3.0 Build Town Hall Feed View
  - [x] 3.1 Create TownHallFeedView.swift
  - [x] 3.2 Add @StateObject for TownHallFeedViewModel
  - [x] 3.3 Display LazyVStack of posts
  - [x] 3.4 Add infinite scroll pagination
  - [x] 3.5 Add floating "+" button for new post
  - [x] 3.6 Add pull-to-refresh
  - [x] 3.7 ⭐ Subscribe to posts via RealtimeManager

- [x] 4.0 Implement TownHallFeedViewModel
  - [x] 4.1 Create TownHallFeedViewModel.swift
  - [x] 4.2 Implement loadPosts() with pagination
  - [x] 4.3 Implement loadMore() for infinite scroll
  - [x] 4.4 🧪 Write TownHallFeedViewModelTests.testLoadPosts_Success

- [x] 5.0 Build Create Post View
  - [x] 5.1 Create CreatePostView.swift
  - [x] 5.2 Add TextEditor for content (max 500 chars)
  - [x] 5.3 Show character count
  - [x] 5.4 Add optional image picker
  - [x] 5.5 Add "Post" button
  - [x] 5.6 Dismiss on success

- [x] 6.0 Implement CreatePostViewModel
  - [x] 6.1 Create CreatePostViewModel.swift
  - [x] 6.2 Implement validateAndPost()
  - [x] 6.3 Check rate limit before posting
  - [x] 6.4 🧪 Write CreatePostViewModelTests.testPost_EmptyContent_ReturnsError

- [x] 7.0 Build TownHallPostRow
  - [x] 7.1 Create TownHallPostRow.swift
  - [x] 7.2 Display poster avatar and name
  - [x] 7.3 Show post content
  - [x] 7.4 Show image if present
  - [x] 7.5 Show relative timestamp
  - [x] 7.6 Add Xcode previews

- [ ] 8.0 Verify town hall implementation
  - [ ] 8.1 Test viewing feed
  - [ ] 8.2 Test creating posts
  - [ ] 8.3 Test rate limiting
  - [ ] 8.4 Test infinite scroll
  - [ ] 8.5 Commit: "feat: implement town hall"

### 🔒 CHECKPOINT: QA-TOWNHALL-FINAL
> Run: `./QA/Scripts/checkpoint.sh townhall-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_TOWNHALL_001
> All town hall tests must pass
