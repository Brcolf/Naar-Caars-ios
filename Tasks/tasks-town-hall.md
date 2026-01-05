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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/town-hall`

- [ ] 1.0 Create TownHallPost data model
  - [ ] 1.1 Create TownHallPost.swift in Core/Models
  - [ ] 1.2 Add fields: id, userId, type, content, imageUrl, createdAt
  - [ ] 1.3 Create PostType enum (userPost, review, completion)
  - [ ] 1.4 Add optional poster Profile
  - [ ] 1.5 🧪 Write TownHallPostTests.testCodableDecoding

- [ ] 2.0 Implement TownHallService
  - [ ] 2.1 Create TownHallService.swift with singleton
  - [ ] 2.2 Implement fetchPosts() ordered by createdAt descending
  - [ ] 2.3 Add pagination support with limit and offset
  - [ ] 2.4 🧪 Write TownHallServiceTests.testFetchPosts_OrderedByDate
  - [ ] 2.5 Implement createPost(userId:, content:, imageUrl:)
  - [ ] 2.6 ⭐ Add rate limit: 30 seconds between posts
  - [ ] 2.7 🧪 Write TownHallServiceTests.testCreatePost_RateLimited
  - [ ] 2.8 Implement createSystemPost() for reviews/completions

### 🔒 CHECKPOINT: QA-TOWNHALL-001
> Run: `./QA/Scripts/checkpoint.sh townhall-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: TownHallService tests pass
> Must pass before continuing

- [ ] 3.0 Build Town Hall Feed View
  - [ ] 3.1 Create TownHallFeedView.swift
  - [ ] 3.2 Add @StateObject for TownHallFeedViewModel
  - [ ] 3.3 Display LazyVStack of posts
  - [ ] 3.4 Add infinite scroll pagination
  - [ ] 3.5 Add floating "+" button for new post
  - [ ] 3.6 Add pull-to-refresh
  - [ ] 3.7 ⭐ Subscribe to posts via RealtimeManager

- [ ] 4.0 Implement TownHallFeedViewModel
  - [ ] 4.1 Create TownHallFeedViewModel.swift
  - [ ] 4.2 Implement loadPosts() with pagination
  - [ ] 4.3 Implement loadMore() for infinite scroll
  - [ ] 4.4 🧪 Write TownHallFeedViewModelTests.testLoadPosts_Success

- [ ] 5.0 Build Create Post View
  - [ ] 5.1 Create CreatePostView.swift
  - [ ] 5.2 Add TextEditor for content (max 500 chars)
  - [ ] 5.3 Show character count
  - [ ] 5.4 Add optional image picker
  - [ ] 5.5 Add "Post" button
  - [ ] 5.6 Dismiss on success

- [ ] 6.0 Implement CreatePostViewModel
  - [ ] 6.1 Create CreatePostViewModel.swift
  - [ ] 6.2 Implement validateAndPost()
  - [ ] 6.3 Check rate limit before posting
  - [ ] 6.4 🧪 Write CreatePostViewModelTests.testPost_EmptyContent_ReturnsError

- [ ] 7.0 Build TownHallPostRow
  - [ ] 7.1 Create TownHallPostRow.swift
  - [ ] 7.2 Display poster avatar and name
  - [ ] 7.3 Show post content
  - [ ] 7.4 Show image if present
  - [ ] 7.5 Show relative timestamp
  - [ ] 7.6 Add Xcode previews

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
