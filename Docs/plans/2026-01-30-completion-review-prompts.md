# Completion + Review Prompt Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Shift completion confirmation to the claimer and deliver global, non-dismissible completion/review prompts with correct notification and badge handling for rides and favors.

**Architecture:** Introduce a `PromptCoordinator` with a single prompt queue, backed by two data sources: due `completion_reminders` for the claimer and unread `review_request`/`review_reminder` notifications for the requestor. Present prompts as full-screen covers from `MainTabView`, and route notification taps to prompt enqueueing after navigation.

**Tech Stack:** SwiftUI, Combine, Supabase Swift client, XCTest, BackgroundTasks, UserNotifications.

---

### Task 1: Add prompt models + queue (test-first)

**Files:**
- Create: `NaarsCars/Features/Prompts/PromptModels.swift`
- Create: `NaarsCars/Features/Prompts/PromptQueue.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/Prompts/PromptQueueTests.swift`

**Step 1: Write the failing test**
```swift
import XCTest
@testable import NaarsCars

final class PromptQueueTests: XCTestCase {
    func testEnqueueSortsOldestFirst() {
        let older = PromptItem.review(.init(
            id: UUID(), requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Alex",
            createdAt: Date(timeIntervalSince1970: 100)
        ))
        let newer = PromptItem.completion(.init(
            id: UUID(), reminderId: UUID(), requestType: .favor,
            requestId: UUID(), requestTitle: "Favor",
            dueAt: Date(timeIntervalSince1970: 200)
        ))

        var queue = PromptQueue()
        queue.enqueue(newer)
        queue.enqueue(older)

        XCTAssertEqual(queue.dequeue(), older)
        XCTAssertEqual(queue.dequeue(), newer)
    }

    func testEnqueueDedupesById() {
        let id = UUID()
        let prompt = PromptItem.review(.init(
            id: id, requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Alex",
            createdAt: Date()
        ))

        var queue = PromptQueue()
        queue.enqueue(prompt)
        queue.enqueue(prompt)

        XCTAssertEqual(queue.count, 1)
    }
}
```

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/PromptQueueTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: FAIL with “Use of unresolved identifier `PromptQueue`”.

**Step 3: Write minimal implementation**
```swift
// NaarsCars/Features/Prompts/PromptModels.swift
import Foundation

struct CompletionPrompt: Identifiable, Equatable {
    let id: UUID
    let reminderId: UUID
    let requestType: RequestType
    let requestId: UUID
    let requestTitle: String
    let dueAt: Date
}

struct ReviewPrompt: Identifiable, Equatable {
    let id: UUID
    let requestType: RequestType
    let requestId: UUID
    let requestTitle: String
    let fulfillerId: UUID
    let fulfillerName: String
    let createdAt: Date
}

enum PromptItem: Identifiable, Equatable {
    case completion(CompletionPrompt)
    case review(ReviewPrompt)

    var id: UUID {
        switch self {
        case .completion(let prompt): return prompt.id
        case .review(let prompt): return prompt.id
        }
    }

    var sortDate: Date {
        switch self {
        case .completion(let prompt): return prompt.dueAt
        case .review(let prompt): return prompt.createdAt
        }
    }
}
```

```swift
// NaarsCars/Features/Prompts/PromptQueue.swift
import Foundation

struct PromptQueue {
    private(set) var items: [PromptItem] = []

    var count: Int { items.count }

    mutating func enqueue(_ prompt: PromptItem) {
        guard !items.contains(where: { $0.id == prompt.id }) else { return }
        items.append(prompt)
        items.sort { $0.sortDate < $1.sortDate }
    }

    mutating func dequeue() -> PromptItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
}
```

**Step 4: Run test to verify it passes**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/PromptQueueTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: PASS (warnings about extra test files are acceptable).

**Step 5: Commit**
```bash
git add NaarsCars/Features/Prompts/PromptModels.swift NaarsCars/Features/Prompts/PromptQueue.swift NaarsCars/NaarsCarsTests/Features/Prompts/PromptQueueTests.swift
git commit -m "feat: add prompt queue models"
```

---

### Task 2: PromptCoordinator orchestration (test-first)

**Files:**
- Create: `NaarsCars/Features/Prompts/PromptCoordinator.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/Prompts/PromptCoordinatorTests.swift`

**Step 1: Write the failing test**
```swift
import XCTest
@testable import NaarsCars

@MainActor
final class PromptCoordinatorTests: XCTestCase {
    func testCheckForPendingPromptsShowsOldest() async {
        let completion = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: Date(timeIntervalSince1970: 100)
        )
        let review = ReviewPrompt(
            id: UUID(), requestType: .favor, requestId: UUID(),
            requestTitle: "Favor", fulfillerId: UUID(), fulfillerName: "Sam",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: [completion]),
            reviewProvider: StubReviewProvider(prompts: [review]),
            sideEffects: StubPromptSideEffects()
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(coordinator.activePrompt, .completion(completion))
    }

    func testReviewPromptMarksNotificationsOnShow() async {
        let review = ReviewPrompt(
            id: UUID(), requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Sam",
            createdAt: Date()
        )
        let sideEffects = StubPromptSideEffects()
        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: []),
            reviewProvider: StubReviewProvider(prompts: [review]),
            sideEffects: sideEffects
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(sideEffects.reviewReads.count, 1)
    }

    func testCompletionPromptMarksNotificationsAfterAction() async throws {
        let completion = CompletionPrompt(
            id: UUID(), reminderId: UUID(), requestType: .ride,
            requestId: UUID(), requestTitle: "Ride", dueAt: Date()
        )
        let sideEffects = StubPromptSideEffects()
        let coordinator = PromptCoordinator(
            completionProvider: StubCompletionProvider(prompts: [completion]),
            reviewProvider: StubReviewProvider(prompts: []),
            sideEffects: sideEffects
        )

        await coordinator.checkForPendingPrompts(userId: UUID())
        XCTAssertEqual(sideEffects.completionReads.count, 0)
        try await coordinator.handleCompletionResponse(completed: true)
        XCTAssertEqual(sideEffects.completionReads.count, 1)
    }
}

private final class StubCompletionProvider: CompletionPromptProviding {
    let prompts: [CompletionPrompt]
    init(prompts: [CompletionPrompt]) { self.prompts = prompts }
    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt] { prompts }
    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt? {
        prompts.first { $0.requestId == requestId }
    }
}

private final class StubReviewProvider: ReviewPromptProviding {
    let prompts: [ReviewPrompt]
    init(prompts: [ReviewPrompt]) { self.prompts = prompts }
    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt] { prompts }
    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt? {
        prompts.first { $0.requestId == requestId }
    }
}

@MainActor
private final class StubPromptSideEffects: PromptSideEffects {
    var reviewReads: [(RequestType, UUID)] = []
    var completionReads: [(RequestType, UUID)] = []
    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async {
        reviewReads.append((requestType, requestId))
    }
    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async {
        completionReads.append((requestType, requestId))
    }
    func refreshBadges(reason: String) async {}
    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws {}
}
```

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/PromptCoordinatorTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: FAIL with “Cannot find type `PromptCoordinator`”.

**Step 3: Write minimal implementation**
```swift
// NaarsCars/Features/Prompts/PromptCoordinator.swift
import Foundation

protocol CompletionPromptProviding {
    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt]
    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt?
}

protocol ReviewPromptProviding {
    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt]
    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt?
}

@MainActor
protocol PromptSideEffects {
    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async
    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async
    func refreshBadges(reason: String) async
    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws
}

@MainActor
final class PromptCoordinator: ObservableObject {
    static let shared = PromptCoordinator(
        completionProvider: CompletionPromptProvider(),
        reviewProvider: ReviewPromptProvider(),
        sideEffects: DefaultPromptSideEffects()
    )

    @Published var activePrompt: PromptItem?

    private var queue = PromptQueue()
    private let completionProvider: CompletionPromptProviding
    private let reviewProvider: ReviewPromptProviding
    private let sideEffects: PromptSideEffects

    init(
        completionProvider: CompletionPromptProviding,
        reviewProvider: ReviewPromptProviding,
        sideEffects: PromptSideEffects
    ) {
        self.completionProvider = completionProvider
        self.reviewProvider = reviewProvider
        self.sideEffects = sideEffects
    }

    func checkForPendingPrompts(userId: UUID) async {
        do {
            let completion = try await completionProvider.fetchDueCompletionPrompts(userId: userId)
            let reviews = try await reviewProvider.fetchPendingReviewPrompts(userId: userId)
            queue = PromptQueue()
            completion.forEach { queue.enqueue(.completion($0)) }
            reviews.forEach { queue.enqueue(.review($0)) }
            await activateNextPromptIfNeeded()
        } catch {
            print("❌ [PromptCoordinator] Failed to load prompts: \(error.localizedDescription)")
        }
    }

    func enqueueCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async {
        if let prompt = try? await completionProvider.fetchCompletionPrompt(
            requestType: requestType, requestId: requestId, userId: userId
        ) {
            queue.enqueue(.completion(prompt))
            await activateNextPromptIfNeeded()
        }
    }

    func enqueueReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async {
        if let prompt = try? await reviewProvider.fetchReviewPrompt(
            requestType: requestType, requestId: requestId, userId: userId
        ) {
            queue.enqueue(.review(prompt))
            await activateNextPromptIfNeeded()
        }
    }

    func handleCompletionResponse(completed: Bool) async throws {
        guard case .completion(let prompt) = activePrompt else { return }
        try await sideEffects.sendCompletionResponse(reminderId: prompt.reminderId, completed: completed)
        await sideEffects.markCompletionNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
        await sideEffects.refreshBadges(reason: "completionPromptAction")
        activePrompt = nil
        await activateNextPromptIfNeeded()
    }

    func finishReviewPrompt() async {
        activePrompt = nil
        await activateNextPromptIfNeeded()
    }

    private func activateNextPromptIfNeeded() async {
        guard activePrompt == nil else { return }
        guard let next = queue.dequeue() else { return }
        activePrompt = next
        if case .review(let prompt) = next {
            await sideEffects.markReviewNotificationsRead(requestType: prompt.requestType, requestId: prompt.requestId)
            await sideEffects.refreshBadges(reason: "reviewPromptShown")
        }
    }
}
```

**Step 4: Run test to verify it passes**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/PromptCoordinatorTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: PASS.

**Step 5: Commit**
```bash
git add NaarsCars/Features/Prompts/PromptCoordinator.swift NaarsCars/NaarsCarsTests/Features/Prompts/PromptCoordinatorTests.swift
git commit -m "feat: add prompt coordinator"
```

---

### Task 3: Implement providers + side effects (test-first)

**Files:**
- Create: `NaarsCars/Core/Services/CompletionPromptProvider.swift`
- Create: `NaarsCars/Core/Services/ReviewPromptProvider.swift`
- Create: `NaarsCars/Core/Services/PromptSideEffects.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/CompletionPromptProviderTests.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/ReviewPromptProviderTests.swift`

**Step 1: Write the failing tests**
```swift
import XCTest
@testable import NaarsCars

@MainActor
final class CompletionPromptProviderTests: XCTestCase {
    func testFetchDueCompletionPrompts_DoesNotThrow() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        let provider = CompletionPromptProvider()
        let prompts = try await provider.fetchDueCompletionPrompts(userId: userId)
        XCTAssertNotNil(prompts)
    }
}
```

```swift
import XCTest
@testable import NaarsCars

@MainActor
final class ReviewPromptProviderTests: XCTestCase {
    func testFetchPendingReviewPrompts_DoesNotThrow() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        let provider = ReviewPromptProvider()
        let prompts = try await provider.fetchPendingReviewPrompts(userId: userId)
        XCTAssertNotNil(prompts)
    }
}
```

**Step 2: Run tests to verify they fail**
Run each with `-only-testing:` and expect “Cannot find type `CompletionPromptProvider` / `ReviewPromptProvider`”.

**Step 3: Write minimal implementation**
```swift
// NaarsCars/Core/Services/PromptSideEffects.swift
import Foundation

@MainActor
final class DefaultPromptSideEffects: PromptSideEffects {
    private let notificationService = NotificationService.shared
    private let badgeManager = BadgeCountManager.shared
    private let supabase = SupabaseService.shared.client

    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async {
        await notificationService.markReviewRequestAsRead(
            requestType: requestType.rawValue,
            requestId: requestId
        )
    }

    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async {
        _ = await notificationService.markRequestScopedRead(
            requestType: requestType.rawValue,
            requestId: requestId,
            notificationTypes: [.completionReminder]
        )
    }

    func refreshBadges(reason: String) async {
        await badgeManager.refreshAllBadges(reason: reason)
    }

    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws {
        let params: [String: AnyCodable] = [
            "p_reminder_id": AnyCodable(reminderId.uuidString),
            "p_completed": AnyCodable(completed)
        ]
        _ = try await supabase
            .rpc("handle_completion_response", params: params)
            .execute()
    }
}
```

```swift
// NaarsCars/Core/Services/CompletionPromptProvider.swift
import Foundation

@MainActor
final class CompletionPromptProvider: CompletionPromptProviding {
    private let supabase = SupabaseService.shared.client
    private let rideService = RideService.shared
    private let favorService = FavorService.shared

    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt] {
        let response = try await supabase
            .from("completion_reminders")
            .select("*")
            .eq("claimer_user_id", value: userId.uuidString)
            .eq("completed", value: false)
            .lte("scheduled_for", value: ISO8601DateFormatter().string(from: Date()))
            .order("scheduled_for", ascending: true)
            .execute()

        let decoder = ISO8601JSONDecoder()
        let reminders = try decoder.decode([CompletionReminder].self, from: response.data)
        return try await buildPrompts(from: reminders)
    }

    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt? {
        let response = try await supabase
            .from("completion_reminders")
            .select("*")
            .eq("claimer_user_id", value: userId.uuidString)
            .eq("completed", value: false)
            .eq(requestType == .ride ? "ride_id" : "favor_id", value: requestId.uuidString)
            .order("scheduled_for", ascending: true)
            .limit(1)
            .execute()

        let decoder = ISO8601JSONDecoder()
        let reminders = try decoder.decode([CompletionReminder].self, from: response.data)
        return try await buildPrompts(from: reminders).first
    }

    private func buildPrompts(from reminders: [CompletionReminder]) async throws -> [CompletionPrompt] {
        var prompts: [CompletionPrompt] = []
        for reminder in reminders {
            if let rideId = reminder.rideId {
                let ride = try await rideService.fetchRide(id: rideId)
                prompts.append(CompletionPrompt(
                    id: reminder.id,
                    reminderId: reminder.id,
                    requestType: .ride,
                    requestId: rideId,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    dueAt: reminder.scheduledFor
                ))
            } else if let favorId = reminder.favorId {
                let favor = try await favorService.fetchFavor(id: favorId)
                prompts.append(CompletionPrompt(
                    id: reminder.id,
                    reminderId: reminder.id,
                    requestType: .favor,
                    requestId: favorId,
                    requestTitle: favor.title,
                    dueAt: reminder.scheduledFor
                ))
            }
        }
        return prompts
    }
}

private struct CompletionReminder: Decodable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    let scheduledFor: Date

    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case scheduledFor = "scheduled_for"
    }
}
```

```swift
// NaarsCars/Core/Services/ReviewPromptProvider.swift
import Foundation

@MainActor
final class ReviewPromptProvider: ReviewPromptProviding {
    private let notificationService = NotificationService.shared
    private let profileService = ProfileService.shared
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let reviewService = ReviewService.shared

    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt] {
        let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
        let pending = notifications
            .filter { !$0.read && ($0.type == .reviewRequest || $0.type == .reviewReminder) }
            .sorted { $0.createdAt < $1.createdAt }

        var prompts: [ReviewPrompt] = []
        for notification in pending {
            if let prompt = try await buildPrompt(from: notification, userId: userId) {
                prompts.append(prompt)
            }
        }
        return prompts
    }

    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt? {
        let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
        let pending = notifications
            .filter { !$0.read && ($0.type == .reviewRequest || $0.type == .reviewReminder) }
            .sorted { $0.createdAt < $1.createdAt }

        for notification in pending {
            if (requestType == .ride && notification.rideId == requestId) ||
               (requestType == .favor && notification.favorId == requestId) {
                return try await buildPrompt(from: notification, userId: userId)
            }
        }
        return nil
    }

    private func buildPrompt(from notification: AppNotification, userId: UUID) async throws -> ReviewPrompt? {
        if let rideId = notification.rideId {
            let ride = try await rideService.fetchRide(id: rideId)
            guard ride.userId == userId, let fulfillerId = ride.claimedBy else { return nil }
            guard try await reviewService.canStillReview(requestType: "ride", requestId: rideId) else { return nil }
            let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
            return ReviewPrompt(
                id: rideId,
                requestType: .ride,
                requestId: rideId,
                requestTitle: "\(ride.pickup) → \(ride.destination)",
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName,
                createdAt: notification.createdAt
            )
        }
        if let favorId = notification.favorId {
            let favor = try await favorService.fetchFavor(id: favorId)
            guard favor.userId == userId, let fulfillerId = favor.claimedBy else { return nil }
            guard try await reviewService.canStillReview(requestType: "favor", requestId: favorId) else { return nil }
            let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
            return ReviewPrompt(
                id: favorId,
                requestType: .favor,
                requestId: favorId,
                requestTitle: favor.title,
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName,
                createdAt: notification.createdAt
            )
        }
        return nil
    }
}

private final class ISO8601JSONDecoder: JSONDecoder {
    override init() {
        super.init()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatter.date(from: value) { return date }
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(value)")
        }
    }
}
```

**Step 4: Run tests to verify they pass**
Run each `-only-testing:` test target; expected PASS or skip if not authenticated.

**Step 5: Commit**
```bash
git add NaarsCars/Core/Services/CompletionPromptProvider.swift NaarsCars/Core/Services/ReviewPromptProvider.swift NaarsCars/Core/Services/PromptSideEffects.swift NaarsCars/NaarsCarsTests/Core/Services/CompletionPromptProviderTests.swift NaarsCars/NaarsCarsTests/Core/Services/ReviewPromptProviderTests.swift
git commit -m "feat: add prompt providers"
```

---

### Task 4: Update UI prompt presentation (test-first)

**Files:**
- Create: `NaarsCars/Features/Prompts/CompletionPromptView.swift`
- Modify: `NaarsCars/Features/Reviews/Views/ReviewPromptSheet.swift`
- Modify: `NaarsCars/App/MainTabView.swift`
- Test: `NaarsCars/NaarsCarsTests/Features/Prompts/CompletionPromptViewTests.swift`

**Step 1: Write the failing test**
```swift
import XCTest
import SwiftUI
@testable import NaarsCars

final class CompletionPromptViewTests: XCTestCase {
    func testCompletionPromptViewInitializes() {
        let view = CompletionPromptView(
            prompt: CompletionPrompt(
                id: UUID(), reminderId: UUID(), requestType: .ride,
                requestId: UUID(), requestTitle: "Ride", dueAt: Date()
            ),
            onConfirm: {},
            onSnooze: {}
        )
        _ = view.body
        XCTAssertTrue(true)
    }
}
```

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/CompletionPromptViewTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: FAIL with “Cannot find type `CompletionPromptView`”.

**Step 3: Write minimal implementation**
```swift
// NaarsCars/Features/Prompts/CompletionPromptView.swift
import SwiftUI

struct CompletionPromptView: View {
    let prompt: CompletionPrompt
    let onConfirm: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsSuccess)

                Text("Is This Complete?")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)

                Text(prompt.requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                VStack(spacing: 12) {
                    PrimaryButton(title: "Confirm completed") {
                        onConfirm()
                    }
                    SecondaryButton(title: "Not yet") {
                        onSnooze()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Complete Request")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }
}
```

```swift
// NaarsCars/Features/Reviews/Views/ReviewPromptSheet.swift
// Add `.interactiveDismissDisabled(true)` at the root NavigationStack.
```

```swift
// NaarsCars/App/MainTabView.swift
@StateObject private var promptCoordinator = PromptCoordinator.shared

.task {
    // ...
    if let userId = AuthService.shared.currentUserId {
        await promptCoordinator.checkForPendingPrompts(userId: userId)
    }
}

.onChange(of: navigationCoordinator.showReviewPrompt) { _, show in
    guard show else { return }
    Task { @MainActor in
        if let userId = AuthService.shared.currentUserId {
            let rideId = navigationCoordinator.reviewPromptRideId
            let favorId = navigationCoordinator.reviewPromptFavorId
            if let rideId { await promptCoordinator.enqueueReviewPrompt(requestType: .ride, requestId: rideId, userId: userId) }
            if let favorId { await promptCoordinator.enqueueReviewPrompt(requestType: .favor, requestId: favorId, userId: userId) }
        }
        navigationCoordinator.resetReviewPrompt()
    }
}

.fullScreenCover(item: $promptCoordinator.activePrompt) { prompt in
    switch prompt {
    case .completion(let completion):
        CompletionPromptView(
            prompt: completion,
            onConfirm: { Task { try? await promptCoordinator.handleCompletionResponse(completed: true) } },
            onSnooze: { Task { try? await promptCoordinator.handleCompletionResponse(completed: false) } }
        )
    case .review(let review):
        ReviewPromptSheet(
            requestType: review.requestType.rawValue,
            requestId: review.requestId,
            requestTitle: review.requestTitle,
            fulfillerId: review.fulfillerId,
            fulfillerName: review.fulfillerName,
            onReviewSubmitted: { Task { await promptCoordinator.finishReviewPrompt() } },
            onReviewSkipped: { Task { await promptCoordinator.finishReviewPrompt() } }
        )
        .interactiveDismissDisabled(true)
    }
}
```

**Step 4: Run test to verify it passes**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/CompletionPromptViewTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: PASS.

**Step 5: Commit**
```bash
git add NaarsCars/Features/Prompts/CompletionPromptView.swift NaarsCars/Features/Reviews/Views/ReviewPromptSheet.swift NaarsCars/App/MainTabView.swift NaarsCars/NaarsCarsTests/Features/Prompts/CompletionPromptViewTests.swift
git commit -m "feat: present global prompts"
```

---

### Task 5: Notification tap + push handling updates (test-first)

**Files:**
- Modify: `NaarsCars/App/AppDelegate.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift`
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/AppDelegateNotificationHandlingTests.swift`

**Step 1: Write failing tests**
```swift
func testShouldShowCompletionPrompt_ForCompletionReminder() {
    XCTAssertTrue(AppDelegate.shouldShowCompletionPrompt(for: "completion_reminder"))
}

func testShouldSkipAutoRead_ForCompletionReminder() {
    XCTAssertTrue(AppDelegate.shouldSkipAutoRead(for: "completion_reminder"))
}
```

**Step 2: Run tests to verify they fail**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/AppDelegateNotificationHandlingTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: FAIL with missing methods.

**Step 3: Implement minimal changes**
```swift
// AppDelegate.swift
static func shouldShowCompletionPrompt(for notificationType: String?) -> Bool {
    notificationType == "completion_reminder"
}

static func shouldSkipAutoRead(for notificationType: String?) -> Bool {
    guard let notificationType else { return false }
    return notificationType == "review_request" ||
           notificationType == "review_reminder" ||
           notificationType == "completion_reminder"
}

// In didReceive:
if let id = notificationId, !Self.shouldSkipAutoRead(for: notificationType) {
    Task { @MainActor in try? await NotificationService.shared.markAsRead(notificationId: id) }
}

// After deep link handling:
if Self.shouldShowCompletionPrompt(for: notificationType) { postCompletionPrompt(from: userInfo) }
if Self.shouldShowReviewPrompt(for: notificationType) { postReviewPrompt(from: userInfo) }

private func postCompletionPrompt(from userInfo: [AnyHashable: Any]) {
    if let rideIdString = userInfo["ride_id"] as? String,
       let rideId = UUID(uuidString: rideIdString) {
        NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["rideId": rideId])
    } else if let favorIdString = userInfo["favor_id"] as? String,
              let favorId = UUID(uuidString: favorIdString) {
        NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["favorId": favorId])
    }
}
```

```swift
// NotificationsListViewModel.swift
case .completionReminder:
    if let rideId = notification.rideId {
        coordinator.selectedTab = .requests
        coordinator.navigateToRide = rideId
        NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["rideId": rideId])
    } else if let favorId = notification.favorId {
        coordinator.selectedTab = .requests
        coordinator.navigateToFavor = favorId
        NotificationCenter.default.post(name: .showCompletionPrompt, object: nil, userInfo: ["favorId": favorId])
    }

// shouldMarkReadOnTap:
case .completionReminder: return false
```

```swift
// PushNotificationService.swift
extension Notification.Name {
    static let showCompletionPrompt = Notification.Name("showCompletionPrompt")
}
```

**Step 4: Run tests to verify they pass**
Run the same `-only-testing:` target. Expected PASS.

**Step 5: Commit**
```bash
git add NaarsCars/App/AppDelegate.swift NaarsCars/Features/Notifications/ViewModels/NotificationsListViewModel.swift NaarsCars/Core/Services/PushNotificationService.swift NaarsCars/NaarsCarsTests/Core/Utilities/AppDelegateNotificationHandlingTests.swift
git commit -m "feat: prompt triggers for completion reminders"
```

---

### Task 6: Remove requestor mark-complete UI + adjust mapping (test-first)

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`
- Modify: `NaarsCars/Core/Models/RequestNotificationMapping.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/RequestNotificationMappingTests.swift`

**Step 1: Write failing test**
```swift
import XCTest
@testable import NaarsCars

final class RequestNotificationMappingTests: XCTestCase {
    func testCompletionReminderUsesMainTopAnchor() {
        let target = RequestNotificationMapping.target(
            for: .completionReminder,
            rideId: UUID(),
            favorId: nil
        )
        XCTAssertEqual(target?.anchor, .mainTop)
        XCTAssertEqual(target?.shouldAutoClear, false)
    }
}
```

**Step 2: Run test to verify it fails**
Expected: FAIL because anchor is `.completeSheet`.

**Step 3: Implement minimal changes**
```swift
// RequestNotificationMapping.swift
case .completionReminder:
    if let rideId {
        return .init(
            requestType: .ride,
            requestId: rideId,
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: nil,
            shouldAutoClear: false
        )
    }
    if let favorId {
        return .init(
            requestType: .favor,
            requestId: favorId,
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: nil,
            shouldAutoClear: false
        )
    }
```

```swift
// RideDetailView.swift / FavorDetailView.swift
// Remove:
@State private var showCompleteSheet = false
// Remove complete sheet .sheet block
// Remove "Mark Complete" button
// Remove handleRequestNavigation branch that sets showCompleteSheet
```

**Step 4: Run test to verify it passes**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/RequestNotificationMappingTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: PASS.

**Step 5: Commit**
```bash
git add NaarsCars/Features/Rides/Views/RideDetailView.swift NaarsCars/Features/Favors/Views/FavorDetailView.swift NaarsCars/Core/Models/RequestNotificationMapping.swift NaarsCars/NaarsCarsTests/Core/Utilities/RequestNotificationMappingTests.swift
git commit -m "feat: remove requestor mark-complete UI"
```

---

### Task 7: Remove 30-minute delay in review prompts (test-first)

**Files:**
- Modify: `NaarsCars/Core/Services/ReviewService+Prompt.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Services/ReviewPromptEligibilityTests.swift`

**Step 1: Write failing test**
```swift
import XCTest
@testable import NaarsCars

final class ReviewPromptEligibilityTests: XCTestCase {
    func testPromptEligibleImmediatelyAfterEvent() {
        let event = Date()
        let now = event.addingTimeInterval(60) // 1 minute later
        XCTAssertTrue(ReviewService.isReviewPromptEligible(eventTime: event, now: now))
    }
}
```

**Step 2: Run test to verify it fails**
Expected: FAIL with “Type `ReviewService` has no member `isReviewPromptEligible`”.

**Step 3: Implement minimal changes**
```swift
// ReviewService+Prompt.swift
extension ReviewService {
    static func isReviewPromptEligible(eventTime: Date, now: Date) -> Bool {
        return now >= eventTime
    }
}

// In findPendingReviewPrompts:
// Replace the 30-minute guard with:
guard Self.isReviewPromptEligible(eventTime: eventTime, now: now) else { continue }

// For favors, add:
guard try await canStillReview(requestType: "favor", requestId: favor.id) else { continue }
```

**Step 4: Run test to verify it passes**
Run: `xcodebuild test -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -only-testing:NaarsCarsTests/ReviewPromptEligibilityTests -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: PASS.

**Step 5: Commit**
```bash
git add NaarsCars/Core/Services/ReviewService+Prompt.swift NaarsCars/NaarsCarsTests/Core/Services/ReviewPromptEligibilityTests.swift
git commit -m "feat: remove review prompt delay"
```

---

### Task 8: Final build verification

**Step 1: Build**
Run: `xcodebuild build -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: BUILD SUCCEEDED.

**Step 2: Optional focused tests**
Run the most critical `-only-testing:` targets above. Warnings about extra test files are acceptable.

