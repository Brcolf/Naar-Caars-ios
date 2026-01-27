# Town Hall SwiftData Integration Implementation Plan
 
> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
 
**Goal:** Implement SwiftData-backed local-first Town Hall posts/comments with realtime reconciliation and network-first writes.
 
**Architecture:** Add SwiftData models + repository + sync engine. View models read local-first and reconcile from network. Realtime payloads update SwiftData immediately and trigger throttled background refresh. Votes remain network-derived and cached in memory only.
 
**Tech Stack:** Swift, SwiftData, Combine, Supabase Realtime, XCTest
 
---
 
### Task 1: TownHallRepository + SD models (posts)
 
**Files:**
- Create: `NaarsCars/Core/Storage/TownHallRepository.swift`
- Modify: `NaarsCars/Core/Storage/SDModels.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Storage/TownHallRepositoryTests.swift`
 
**Step 1: Write the failing test**
 
```swift
import XCTest
import SwiftData
@testable import NaarsCars

@MainActor
final class TownHallRepositoryTests: XCTestCase {
    func testUpsertPostsPersistsSnapshot() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            SDTownHallComment.self,
            configurations: config
        )
        let context = container.mainContext
        let repository = TownHallRepository()
        repository.setup(modelContext: context)

        let author = Profile(id: UUID(), name: "Alex Doe", email: "alex@example.com", avatarUrl: "https://example.com/a.png")
        let post = TownHallPost(userId: author.id, content: "Hello", title: "Hello", createdAt: Date(), updatedAt: Date(), author: author, commentCount: 2)

        try repository.upsertPosts([post])
        let loaded = try repository.getPosts()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.author?.name, "Alex Doe")
        XCTAssertEqual(loaded.first?.commentCount, 2)
    }
}
```
 
**Step 2: Run test to verify it fails**
 
Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaarsCarsTests/TownHallRepositoryTests/testUpsertPostsPersistsSnapshot`
Expected: FAIL (missing `SDTownHallPost` / `TownHallRepository`).
 
**Step 3: Write minimal implementation**
 
- Add `SDTownHallPost` and `SDTownHallComment` to `SDModels.swift`.
- Implement `TownHallRepository` with `setup`, `getPosts`, `upsertPosts`, and mapping helpers.
 
**Step 4: Run test to verify it passes**
 
Run: same command as Step 2  
Expected: PASS
 
**Step 5: Commit**
 
```bash
git add NaarsCars/Core/Storage/SDModels.swift NaarsCars/Core/Storage/TownHallRepository.swift NaarsCars/NaarsCarsTests/Core/Storage/TownHallRepositoryTests.swift
git commit -m "feat: add SwiftData town hall repository and post mappings"
```
 
---
 
### Task 2: Comment persistence + nesting
 
**Files:**
- Modify: `NaarsCars/Core/Storage/TownHallRepository.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Storage/TownHallRepositoryTests.swift`
 
**Step 1: Write the failing test**
 
```swift
func testGetCommentsBuildsNestedStructure() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: SDTownHallPost.self,
        SDTownHallComment.self,
        configurations: config
    )
    let context = container.mainContext
    let repository = TownHallRepository()
    repository.setup(modelContext: context)

    let postId = UUID()
    let parent = TownHallComment(postId: postId, userId: UUID(), content: "Parent")
    let child = TownHallComment(postId: postId, userId: UUID(), parentCommentId: parent.id, content: "Child")

    try repository.upsertComments([parent, child])
    let comments = try repository.getComments(postId: postId)

    XCTAssertEqual(comments.count, 1)
    XCTAssertEqual(comments.first?.replies?.count, 1)
}
```
 
**Step 2: Run test to verify it fails**
 
Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaarsCarsTests/TownHallRepositoryTests/testGetCommentsBuildsNestedStructure`
Expected: FAIL (no comment upsert/nesting).
 
**Step 3: Write minimal implementation**
 
- Add `upsertComments` and `getComments(postId:)` to `TownHallRepository`.
- Flatten nested inputs and build nested outputs using parent IDs.
 
**Step 4: Run test to verify it passes**
 
Run: same command as Step 2  
Expected: PASS
 
**Step 5: Commit**
 
```bash
git add NaarsCars/Core/Storage/TownHallRepository.swift NaarsCars/NaarsCarsTests/Core/Storage/TownHallRepositoryTests.swift
git commit -m "feat: persist town hall comments and nest replies"
```
 
---
 
### Task 3: TownHallSyncEngine (realtime + reconcile)
 
**Files:**
- Create: `NaarsCars/Core/Storage/TownHallSyncEngine.swift`
- Modify: `NaarsCars/App/NaarsCarsApp.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Storage/TownHallSyncEngineTests.swift`
 
**Step 1: Write the failing test**
 
```swift
import XCTest
import SwiftData
@testable import NaarsCars

@MainActor
final class TownHallSyncEngineTests: XCTestCase {
    func testApplyPostPayloadUpsertsPost() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            SDTownHallComment.self,
            configurations: config
        )
        let repository = TownHallRepository()
        repository.setup(modelContext: container.mainContext)

        let engine = TownHallSyncEngine(repository: repository)
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "user_id": UUID().uuidString,
            "content": "Realtime post",
            "created_at": "2026-01-25T12:00:00Z",
            "updated_at": "2026-01-25T12:00:00Z"
        ]

        try engine.applyPostRecord(payload)
        let posts = try repository.getPosts()
        XCTAssertEqual(posts.count, 1)
    }
}
```
 
**Step 2: Run test to verify it fails**
 
Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaarsCarsTests/TownHallSyncEngineTests/testApplyPostPayloadUpsertsPost`
Expected: FAIL (missing sync engine and payload handler).
 
**Step 3: Write minimal implementation**
 
- Add `TownHallSyncEngine` with:
  - `setup(modelContext:)`, `startSync()`
  - realtime subscriptions for `town_hall_posts`, `town_hall_comments`, `town_hall_votes`
  - `applyPostRecord(_:)` / `applyCommentRecord(_:)` helpers for payloads
  - throttled background refresh using `TownHallService` / `TownHallCommentService`
- Wire engine in `NaarsCarsApp` (setup + start).
 
**Step 4: Run test to verify it passes**
 
Run: same command as Step 2  
Expected: PASS
 
**Step 5: Commit**
 
```bash
git add NaarsCars/Core/Storage/TownHallSyncEngine.swift NaarsCars/App/NaarsCarsApp.swift NaarsCars/NaarsCarsTests/Core/Storage/TownHallSyncEngineTests.swift
git commit -m "feat: add town hall realtime sync engine"
```
 
---
 
### Task 4: TownHallFeedViewModel local-first + vote cache
 
**Files:**
- Modify: `NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift`
 
**Step 1: Write the failing test**
 
```swift
@MainActor
func testLoadPosts_UsesLocalFirst() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: SDTownHallPost.self, SDTownHallComment.self, configurations: config)
    let repository = TownHallRepository()
    repository.setup(modelContext: container.mainContext)
    try repository.upsertPosts([TownHallPost(userId: UUID(), content: "Local")])

    let viewModel = TownHallFeedViewModel(repository: repository)
    await viewModel.loadPosts()

    XCTAssertEqual(viewModel.posts.first?.content, "Local")
}
```
 
**Step 2: Run test to verify it fails**
 
Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaarsCarsTests/TownHallFeedViewModelTests/testLoadPosts_UsesLocalFirst`
Expected: FAIL (no repository injection/local-first).
 
**Step 3: Write minimal implementation**
 
- Inject `TownHallRepository` into view model (default to `.shared`).
- Load local posts first; if empty, fetch from network and persist.
- Cache vote counts in-memory; apply cache to local posts.
- Use throttled refresh for realtime vote notifications.
 
**Step 4: Run test to verify it passes**
 
Run: same command as Step 2  
Expected: PASS
 
**Step 5: Commit**
 
```bash
git add NaarsCars/Features/TownHall/ViewModels/TownHallFeedViewModel.swift NaarsCars/NaarsCarsTests/Features/TownHall/TownHallFeedViewModelTests.swift
git commit -m "feat: load town hall feed from SwiftData first"
```
 
---
 
### Task 5: PostCommentsViewModel local-first
 
**Files:**
- Modify: `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/TownHall/PostCommentsViewModelTests.swift`
 
**Step 1: Write the failing test**
 
```swift
import XCTest
import SwiftData
@testable import NaarsCars

@MainActor
final class PostCommentsViewModelTests: XCTestCase {
    func testLoadComments_UsesLocalFirst() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SDTownHallPost.self, SDTownHallComment.self, configurations: config)
        let repository = TownHallRepository()
        repository.setup(modelContext: container.mainContext)

        let postId = UUID()
        let comment = TownHallComment(postId: postId, userId: UUID(), content: "Local comment")
        try repository.upsertComments([comment])

        let viewModel = PostCommentsViewModel(postId: postId, repository: repository)
        await viewModel.loadComments()

        XCTAssertEqual(viewModel.topLevelComments.first?.content, "Local comment")
    }
}
```
 
**Step 2: Run test to verify it fails**
 
Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaarsCarsTests/PostCommentsViewModelTests/testLoadComments_UsesLocalFirst`
Expected: FAIL (no repository injection/local-first).
 
**Step 3: Write minimal implementation**
 
- Move `PostCommentsViewModel` into its own file if needed for testing.
- Inject `TownHallRepository` (default `.shared`).
- Load local comments first; if empty, fetch from network and persist.
- Update vote cache from network comments and apply to local data.
 
**Step 4: Run test to verify it passes**
 
Run: same command as Step 2  
Expected: PASS
 
**Step 5: Commit**
 
```bash
git add NaarsCars/Features/TownHall/Views/PostCommentsView.swift NaarsCars/NaarsCarsTests/Features/TownHall/PostCommentsViewModelTests.swift
git commit -m "feat: load town hall comments from SwiftData first"
```
 
---
 
### Task 6: Build-only verification (minimal Xcode)
 
**Files:**
- None
 
**Step 1: Build the app**
 
Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `BUILD SUCCEEDED`
 
**Step 2: Commit any remaining changes**
 
```bash
git add -A
git commit -m "feat: integrate town hall SwiftData local-first flow"
```
 
