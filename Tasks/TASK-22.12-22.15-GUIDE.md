# Task 22.12-22.15: Performance Tests Guide

This guide helps you complete the remaining performance tests (PERF-CLI-001 through PERF-CLI-004).

## Overview

These are **manual performance tests** that verify the app meets performance targets. They should be run after the app is built and can launch successfully.

## Prerequisites

- App builds without errors
- App launches in simulator
- All unit tests pass
- Foundation infrastructure complete

## Test Execution

### PERF-CLI-001: App Cold Launch <1 Second

**Target:** App cold launch to main screen completes in <1 second

**How to Test:**
1. **Quit the app completely** (swipe up in simulator or stop in Xcode)
2. **Clear app data** (optional but recommended for true cold launch):
   - Simulator → Device → Erase All Content and Settings
   - Or delete app and reinstall
3. **Start timing** when you tap the app icon
4. **Stop timing** when the main screen (MainTabView) is fully visible
5. **Record the time**

**Using Xcode Instruments (Recommended):**
1. Open Xcode
2. Product → Profile (Cmd+I)
3. Select "Time Profiler"
4. Click Record
5. Launch app
6. Check "Time to First Frame" or measure manually
7. Look for AppLaunchManager completion time

**Manual Method:**
1. Use a stopwatch or screen recording
2. Start when app icon is tapped
3. Stop when MainTabView is visible
4. Record time

**Expected Result:** < 1 second

**Documentation:**
```markdown
- [x] 22.12 🧪 PERF-CLI-001: App cold launch - ✅ 0.8s (<1s target)
```

**If Too Slow:**
- Check AppLaunchManager is only doing critical path
- Verify deferred loading is working
- Check for blocking network calls
- Review launch time profiler for bottlenecks

---

### PERF-CLI-002: Cache Hit Returns <10ms

**Target:** Cache hit returns data in <10ms

**How to Test:**
1. **Add timing code** to CacheManager or create a test:
```swift
// In a test or debug code
let startTime = CFAbsoluteTimeGetCurrent()
let cached = await CacheManager.shared.getCachedProfile(id: testProfileId)
let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
print("Cache hit duration: \(duration)ms")
```

2. **Ensure cache is populated:**
```swift
// First, cache a profile
await CacheManager.shared.cacheProfile(testProfile)
```

3. **Measure cache retrieval:**
```swift
// Then immediately get it (should be cached)
let start = CFAbsoluteTimeGetCurrent()
let profile = await CacheManager.shared.getCachedProfile(id: testProfile.id)
let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
```

**Using Unit Test:**
Create a test in `CacheManagerTests.swift`:
```swift
func testCacheHitPerformance() async {
    let profile = Profile(/* test data */)
    await CacheManager.shared.cacheProfile(profile)
    
    let start = CFAbsoluteTimeGetCurrent()
    let cached = await CacheManager.shared.getCachedProfile(id: profile.id)
    let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
    
    XCTAssertNotNil(cached)
    XCTAssertLessThan(duration, 10.0, "Cache hit should be <10ms, was \(duration)ms")
}
```

**Expected Result:** < 10ms

**Documentation:**
```markdown
- [x] 22.13 🧪 PERF-CLI-002: Cache hit returns immediately - ✅ 2.3ms (<10ms target)
```

**If Too Slow:**
- Check CacheManager is using actor efficiently
- Verify no unnecessary async overhead
- Review implementation for bottlenecks

---

### PERF-CLI-003: Rate Limiter Blocks Rapid Taps

**Target:** Rate limiter blocks second tap when tapped rapidly

**How to Test:**
1. **Create a test button** or use existing button with rate limiting
2. **Add rate limiting** to button action:
```swift
Button("Test") {
    Task {
        let allowed = await RateLimiter.shared.checkAndRecord(
            action: "test_button",
            minimumInterval: 1.0 // 1 second minimum
        )
        if allowed {
            print("Button tapped - action allowed")
        } else {
            print("Button tapped - rate limited")
        }
    }
}
```

3. **Tap button twice rapidly** (within 1 second)
4. **Verify:**
   - First tap: Action allowed
   - Second tap: Action blocked (rate limited)

**Using Unit Test:**
Add to `RateLimiterTests.swift`:
```swift
func testRateLimiterBlocksRapidTaps() async {
    let limiter = RateLimiter.shared
    
    // First tap should be allowed
    let first = await limiter.checkAndRecord(action: "test", minimumInterval: 1.0)
    XCTAssertTrue(first, "First tap should be allowed")
    
    // Immediate second tap should be blocked
    let second = await limiter.checkAndRecord(action: "test", minimumInterval: 1.0)
    XCTAssertFalse(second, "Second tap should be blocked")
    
    // Wait for interval to pass
    try? await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
    
    // Third tap should be allowed again
    let third = await limiter.checkAndRecord(action: "test", minimumInterval: 1.0)
    XCTAssertTrue(third, "Third tap should be allowed after interval")
}
```

**Expected Result:** Second tap is blocked

**Documentation:**
```markdown
- [x] 22.14 🧪 PERF-CLI-003: Rate limiter blocks rapid taps - ✅ Verified (second tap blocked)
```

**If Not Working:**
- Check RateLimiter implementation
- Verify minimumInterval is being respected
- Check timing logic

---

### PERF-CLI-004: Image Compression Meets Size Limits

**Target:** Compressed images meet preset size limits

**How to Test:**
1. **Get a test image** (large photo, e.g., 5MB+)
2. **Compress with each preset:**
```swift
import UIKit

// Load test image
guard let testImage = UIImage(named: "test-large-photo") else { return }

// Test avatar preset (max 200KB)
if let compressed = await ImageCompressor.compress(testImage, preset: .avatar) {
    let sizeKB = compressed.count / 1024
    print("Avatar preset: \(sizeKB)KB (target: <200KB)")
    XCTAssertLessThan(sizeKB, 200, "Avatar should be <200KB")
}

// Test messageImage preset (max 500KB)
if let compressed = await ImageCompressor.compress(testImage, preset: .messageImage) {
    let sizeKB = compressed.count / 1024
    print("MessageImage preset: \(sizeKB)KB (target: <500KB)")
    XCTAssertLessThan(sizeKB, 500, "MessageImage should be <500KB")
}

// Test fullSize preset (max 1MB)
if let compressed = await ImageCompressor.compress(testImage, preset: .fullSize) {
    let sizeKB = compressed.count / 1024
    print("FullSize preset: \(sizeKB)KB (target: <1MB)")
    XCTAssertLessThan(sizeKB, 1024, "FullSize should be <1MB")
}
```

**Using Unit Test:**
Add to `ImageCompressorTests.swift`:
```swift
func testImageCompressionMeetsSizeLimits() async throws {
    // Create a large test image (2000x2000)
    let largeImage = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 2000))
        .image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 2000, height: 2000))
        }
    
    // Test avatar preset
    if let compressed = await ImageCompressor.compress(largeImage, preset: .avatar) {
        let sizeKB = compressed.count / 1024
        XCTAssertLessThan(sizeKB, 200, "Avatar should be <200KB, was \(sizeKB)KB")
    }
    
    // Test messageImage preset
    if let compressed = await ImageCompressor.compress(largeImage, preset: .messageImage) {
        let sizeKB = compressed.count / 1024
        XCTAssertLessThan(sizeKB, 500, "MessageImage should be <500KB, was \(sizeKB)KB")
    }
    
    // Test fullSize preset
    if let compressed = await ImageCompressor.compress(largeImage, preset: .fullSize) {
        let sizeKB = compressed.count / 1024
        XCTAssertLessThan(sizeKB, 1024, "FullSize should be <1MB, was \(sizeKB)KB")
    }
}
```

**Expected Results:**
- Avatar preset: < 200KB
- MessageImage preset: < 500KB
- FullSize preset: < 1MB

**Documentation:**
```markdown
- [x] 22.15 🧪 PERF-CLI-004: Image compression meets size limits - ✅ Verified
  - Avatar: 145KB (<200KB)
  - MessageImage: 387KB (<500KB)
  - FullSize: 892KB (<1MB)
```

**If Too Large:**
- Check ImageCompressor quality reduction loop
- Verify maxBytes limits are enforced
- Review compression algorithm

---

## Running All Tests

You can run all performance tests together:

1. **Open Xcode**
2. **Run unit tests** for performance-related tests:
   ```bash
   xcodebuild test \
     -project NaarsCars.xcodeproj \
     -scheme NaarsCars \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     -only-testing:NaarsCarsTests/Core/Utilities/CacheManagerTests \
     -only-testing:NaarsCarsTests/Core/Utilities/RateLimiterTests \
     -only-testing:NaarsCarsTests/Core/Utilities/ImageCompressorTests
   ```

3. **Manually test** PERF-CLI-001 (app launch)

## Documentation Template

After completing all tests, update `Tasks/tasks-foundation-architecture.md`:

```markdown
- [x] 22.12 🧪 PERF-CLI-001: App cold launch - ✅ 0.8s (<1s target)
- [x] 22.13 🧪 PERF-CLI-002: Cache hit returns immediately - ✅ 2.3ms (<10ms target)
- [x] 22.14 🧪 PERF-CLI-003: Rate limiter blocks rapid taps - ✅ Verified
- [x] 22.15 🧪 PERF-CLI-004: Image compression meets size limits - ✅ Verified
  - Avatar: 145KB, MessageImage: 387KB, FullSize: 892KB
```

## Troubleshooting

### App Launch Too Slow
- Use Instruments Time Profiler to find bottlenecks
- Check AppLaunchManager is only doing critical path
- Verify no blocking network calls
- Review deferred loading implementation

### Cache Too Slow
- Check actor overhead
- Verify no unnecessary async operations
- Review CacheManager implementation

### Rate Limiter Not Working
- Check timing logic
- Verify minimumInterval enforcement
- Review RateLimiter implementation

### Image Compression Too Large
- Check quality reduction loop
- Verify maxBytes enforcement
- Review compression algorithm

## Next Steps

After completing all performance tests:
1. Mark tasks 22.12-22.15 as complete
2. Proceed to Task 22.21 (final commit)
3. Run foundation-final checkpoint

