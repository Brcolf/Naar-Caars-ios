# Timezone Migration Fix & Frame Drop Optimization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the SwiftData migration crash caused by missing `timezone` column mapping, and reduce messaging frame drops from 66-100ms to under 33ms.

**Architecture:** Two independent fixes: (1) Remove dead versioned schema files, auto-recover on migration failure, and add 4 missing timezone mapping lines in BackgroundSyncActor; (2) Make cell config recomputation incremental O(1), debounce collection view snapshot applies, and isolate audio player re-renders.

**Tech Stack:** SwiftData, UIKit (UICollectionView + NSDiffableDataSource), SwiftUI, Combine

---

### Task 1: Delete Dead Schema Files

**Files:**
- Delete: `NaarsCars/Core/Storage/SDModelVersions.swift`
- Delete: `NaarsCars/Core/Storage/SDMigrationPlan.swift`

These files define SchemaV1/V2 and a no-op migration plan. The container in `NaarsCarsApp.swift:103` uses `ModelContainer(for:)` without referencing them — they are dead code that creates confusion.

**Step 1: Delete both files**

```bash
git rm NaarsCars/Core/Storage/SDModelVersions.swift
git rm NaarsCars/Core/Storage/SDMigrationPlan.swift
```

**Step 2: Build to verify no compilation errors**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. If anything references these types, fix the import.

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: remove dead schema versioning files (SDModelVersions, SDMigrationPlan)"
```

---

### Task 2: Auto-Recover on Migration Failure

**Files:**
- Modify: `NaarsCars/App/NaarsCarsApp.swift:42-51`

**Step 1: Replace the container init error handling**

In `NaarsCarsApp.init()`, replace the catch block (lines 47-51) so it silently deletes the store and retries before falling back to the alert:

```swift
        // Initialize SwiftData with migration plan
        do {
            let newContainer = try Self.createModelContainer()
            _container = State(initialValue: newContainer)
            Self.setupSyncEngines(with: newContainer)
            containerReady = true
        } catch {
            AppLogger.error("app", "SwiftData container failed, attempting auto-recovery: \(error)")
            // Auto-clear corrupt/incompatible store and retry
            Self.deleteStoreFiles()
            do {
                let recovered = try Self.createModelContainer()
                _container = State(initialValue: recovered)
                Self.setupSyncEngines(with: recovered)
                containerReady = true
                AppLogger.info("app", "SwiftData container recovered after clearing local cache")
            } catch {
                AppLogger.error("app", "Failed to initialize SwiftData container after recovery: \(error)")
                _container = State(initialValue: nil)
                _showDataError = State(initialValue: true)
            }
        }
```

**Step 2: Extract store file deletion into a static helper**

Add this static method to `NaarsCarsApp` (before `clearLocalDataAndRetry()`):

```swift
    /// Deletes the SQLite store files. Safe to call from init (static, no instance state).
    private static func deleteStoreFiles() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for file in ["default.store", "default.store-wal", "default.store-shm"] {
            try? fileManager.removeItem(at: appSupport.appendingPathComponent(file))
        }
    }
```

**Step 3: Update `clearLocalDataAndRetry()` to reuse the static helper**

Replace the file deletion logic in `clearLocalDataAndRetry()` (lines 139-146) with a call to `Self.deleteStoreFiles()`:

```swift
    private func clearLocalDataAndRetry() {
        Self.deleteStoreFiles()

        // Retry container creation
        do {
            let newContainer = try Self.createModelContainer()
            container = newContainer
            Self.setupSyncEngines(with: newContainer)
        } catch {
            AppLogger.error("app", "Failed to reinitialize SwiftData container after clearing data: \(error)")
            showDataError = true
        }
    }
```

**Step 4: Build to verify**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add NaarsCars/App/NaarsCarsApp.swift && git commit -m "fix: auto-recover SwiftData container on migration failure"
```

---

### Task 3: Add Timezone Mapping in BackgroundSyncActor

**Files:**
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift`

Four precise insertions:

**Step 1: Add timezone to SDRide constructor (line 152)**

After `time: ride.time,` add `timezone: ride.timezone,`:

```swift
                let sdRide = SDRide(
                    id: ride.id,
                    userId: ride.userId,
                    type: ride.type,
                    date: ride.date,
                    time: ride.time,
                    timezone: ride.timezone,
                    pickup: ride.pickup,
```

**Step 2: Add timezone to updateSDRide (after line 276 `sd.time = ride.time`)**

```swift
        sd.timezone = ride.timezone
```

**Step 3: Add timezone to SDFavor constructor (line 206)**

After `time: favor.time,` add `timezone: favor.timezone,`:

```swift
                let sdFavor = SDFavor(
                    id: favor.id,
                    userId: favor.userId,
                    title: favor.title,
                    favorDescription: favor.description,
                    location: favor.location,
                    duration: favor.duration.rawValue,
                    requirements: favor.requirements,
                    date: favor.date,
                    time: favor.time,
                    timezone: favor.timezone,
                    gift: favor.gift,
```

**Step 4: Add timezone to updateSDFavor (after line 305 `sd.time = favor.time`)**

```swift
        sd.timezone = favor.timezone
```

**Step 5: Build to verify**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add NaarsCars/Core/Storage/BackgroundSyncActor.swift && git commit -m "fix: map timezone in BackgroundSyncActor for rides and favors"
```

---

### Task 4: Incremental Cell Config Recomputation

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift:16-21, 94-107`

**Step 1: Replace the messages didSet observer**

Change the `messages` property from recomputing all configs to only updating affected ones:

```swift
    @Published var messages: [Message] = [] {
        didSet {
            recomputeCellConfigurationsIncrementally(oldMessages: oldValue)
            recomputeUnreadCount()
        }
    }
```

**Step 2: Replace `recomputeCellConfigurations()` with incremental version**

Replace lines 94-107 with:

```swift
    /// Full recomputation — used only for initial load or major changes.
    private func recomputeAllCellConfigurations() {
        var configs: [UUID: MessageCellConfiguration] = [:]
        for (index, message) in messages.enumerated() {
            configs[message.id] = MessageCellConfiguration(
                messageId: message.id,
                isFirstInSeries: isFirstInSeries(at: index),
                isLastInSeries: isLastInSeries(at: index),
                showDateSeparator: shouldShowDateSeparator(at: index)
            )
        }
        messageCellConfigurations = configs
    }

    /// Incremental recomputation — only update configs for changed/new messages
    /// and their immediate neighbors whose series flags may have changed.
    private func recomputeCellConfigurationsIncrementally(oldMessages: [Message]) {
        // Fall back to full recompute if the change is complex
        let oldIds = oldMessages.map { $0.id }
        let newIds = messages.map { $0.id }

        // If more than a few messages changed, full recompute is simpler
        if abs(newIds.count - oldIds.count) > 3 || oldIds.isEmpty {
            recomputeAllCellConfigurations()
            return
        }

        // Find indices that need recomputation
        var indicesToRecompute = Set<Int>()

        // Find new message IDs not in old set
        let oldIdSet = Set(oldIds)
        for (index, id) in newIds.enumerated() {
            if !oldIdSet.contains(id) {
                // New message + neighbors
                indicesToRecompute.insert(index)
                if index > 0 { indicesToRecompute.insert(index - 1) }
                if index < newIds.count - 1 { indicesToRecompute.insert(index + 1) }
            }
        }

        // If no new messages but count/order changed, full recompute
        if indicesToRecompute.isEmpty && oldIds != newIds {
            recomputeAllCellConfigurations()
            return
        }

        // If truly nothing changed, skip entirely
        if indicesToRecompute.isEmpty { return }

        // Update only affected configs
        var configs = messageCellConfigurations
        for index in indicesToRecompute where index < messages.count {
            let message = messages[index]
            configs[message.id] = MessageCellConfiguration(
                messageId: message.id,
                isFirstInSeries: isFirstInSeries(at: index),
                isLastInSeries: isLastInSeries(at: index),
                showDateSeparator: shouldShowDateSeparator(at: index)
            )
        }

        // Remove configs for messages no longer present
        let newIdSet = Set(newIds)
        for id in configs.keys where !newIdSet.contains(id) {
            configs.removeValue(forKey: id)
        }

        messageCellConfigurations = configs
    }
```

**Step 3: Build to verify**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift && git commit -m "perf: incremental cell config recomputation O(1) for single new messages"
```

---

### Task 5: Debounce Collection View Snapshot Applies

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift:70-112, 135-141`

**Step 1: Add debounce state to Coordinator**

Add these properties to the `Coordinator` class (after `lastSnapshotCount` on line 141):

```swift
        private var pendingSnapshot: NSDiffableDataSourceSnapshot<Int, UUID>?
        private var pendingAnimating: Bool = false
        private var debounceWorkItem: DispatchWorkItem?
```

**Step 2: Add applySnapshotDebounced method to Coordinator**

Add this method inside the Coordinator class:

```swift
        func applySnapshotDebounced(_ snapshot: NSDiffableDataSourceSnapshot<Int, UUID>, animating: Bool, collectionView: UICollectionView) {
            // Cancel any pending apply
            debounceWorkItem?.cancel()

            // If animating (single new message), apply immediately for responsiveness
            if animating {
                dataSource?.apply(snapshot, animatingDifferences: true)
                return
            }

            // For non-animated applies (pagination, bulk), debounce to coalesce rapid updates
            pendingSnapshot = snapshot
            pendingAnimating = false

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pendingSnapshot else { return }
                self.dataSource?.apply(pending, animatingDifferences: false)
                self.pendingSnapshot = nil
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }
```

**Step 3: Update updateUIView to use debounced apply**

Replace the snapshot application logic in `updateUIView` (lines 91-99) with:

```swift
        if isInitialLoad {
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        } else if isSingleNewMessage {
            // Single new message — apply immediately with animation
            coordinator.applySnapshotDebounced(snapshot, animating: true, collectionView: collectionView)
        } else {
            // Pagination, bulk update, or metadata change — debounce
            coordinator.applySnapshotDebounced(snapshot, animating: false, collectionView: collectionView)
        }
```

**Step 4: Build to verify**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift && git commit -m "perf: debounce non-animated snapshot applies to coalesce rapid updates"
```

---

### Task 6: Isolate Audio Player Re-renders

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift:995-1012`

The `AudioMessageContentView` already exists as an isolated struct. The issue is that `@StateObject private var audioPlayer = MessageAudioPlayer.shared` causes the view to re-render on **every** `@Published` change from the shared player — even when this message isn't the one playing.

**Step 1: Add a lightweight observation wrapper**

Add this struct just above `AudioMessageContentView` in `MessageBubble.swift`:

```swift
/// Lightweight observer that only publishes changes when the given audio URL is the active one.
/// Prevents non-playing audio message bubbles from re-rendering on every timer tick.
@MainActor
private final class AudioPlaybackState: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0

    private let audioUrl: String
    private var cancellables = Set<AnyCancellable>()

    init(audioUrl: String) {
        self.audioUrl = audioUrl
        let player = MessageAudioPlayer.shared

        // Only publish when this URL is the active one
        player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let isCurrent = player.currentUrl?.absoluteString == self.audioUrl
                let newPlaying = isCurrent && player.isPlaying
                let newProgress = isCurrent ? player.progress : 0
                let newDuration = isCurrent ? player.duration : self.duration

                // Only trigger view update if values actually changed for this URL
                if newPlaying != self.isPlaying || abs(newProgress - self.progress) >= 0.01 || newDuration != self.duration {
                    self.isPlaying = newPlaying
                    self.progress = newProgress
                    self.duration = newDuration
                }
            }
            .store(in: &cancellables)
    }
}
```

**Step 2: Update AudioMessageContentView to use AudioPlaybackState**

Replace the `@StateObject` and computed properties at the top of `AudioMessageContentView`:

Change from:
```swift
    @StateObject private var audioPlayer = MessageAudioPlayer.shared

    var body: some View {
        let isCurrent = audioPlayer.currentUrl?.absoluteString == audioUrl
        let isPlaying = isCurrent && audioPlayer.isPlaying
        let progress = isCurrent ? audioPlayer.progress : 0
        let totalDuration = duration > 0 ? duration : (isCurrent ? audioPlayer.duration : 0)
```

To:
```swift
    @StateObject private var playbackState: AudioPlaybackState

    init(audioUrl: String, duration: Double, isFromCurrentUser: Bool, waveformHeights: [CGFloat]) {
        self.audioUrl = audioUrl
        self.duration = duration
        self.isFromCurrentUser = isFromCurrentUser
        self.waveformHeights = waveformHeights
        self._playbackState = StateObject(wrappedValue: AudioPlaybackState(audioUrl: audioUrl))
    }

    var body: some View {
        let isPlaying = playbackState.isPlaying
        let progress = playbackState.progress
        let totalDuration = duration > 0 ? duration : playbackState.duration
```

And update the play button action from:
```swift
                audioPlayer.togglePlayback(urlString: audioUrl)
```
To:
```swift
                MessageAudioPlayer.shared.togglePlayback(urlString: audioUrl)
```

**Step 3: Build to verify**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageBubble.swift && git commit -m "perf: isolate audio player re-renders to only the actively playing message"
```

---

### Task 7: Final Verification

**Step 1: Clean build**

```bash
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' clean build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED with no warnings from our files.

**Step 2: Verify no references to deleted files**

```bash
grep -r "SDModelVersions\|SDMigrationPlan\|NaarsCarsModelMigrationPlan\|SchemaV1\|SchemaV2" --include="*.swift" NaarsCars/
```

Expected: No results (if any remain, remove the references).

**Step 3: Commit if any cleanup was needed, otherwise done**
