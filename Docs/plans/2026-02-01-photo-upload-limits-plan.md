# Photo Upload Limits Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Accept high-quality iPhone photos for Town Hall posts and avatars while still resizing and compressing before storage.

**Architecture:** Keep the existing compression pipeline (resize + iterative JPEG quality) and raise preset limits. Align Town Hall pre-check with the updated preset. Update tests to enforce new limits.

**Tech Stack:** Swift, XCTest, Supabase Storage

---

### Task 1: Update ImageCompressor tests

**Files:**
- Modify: `NaarsCars/NaarsCarsTests/Core/Utilities/ImageCompressorTests.swift`

**Step 1: Write the failing test**
```swift
func testAvatarPresetOutputSizeIsUnderMaxBytes() {
    XCTAssertEqual(ImagePreset.avatar.maxDimension, 1024)
    XCTAssertEqual(ImagePreset.avatar.maxBytes, 1 * 1024 * 1024)
}
```

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project "NaarsCars/NaarsCars.xcodeproj" -scheme "NaarsCars" -destination "platform=iOS Simulator,name=iPhone 15" -only-testing:NaarsCarsTests/ImageCompressorTests`
Expected: FAIL with assertion showing current preset values (e.g., 400px / 500KB).

**Step 3: Commit**
```bash
git add NaarsCars/NaarsCarsTests/Core/Utilities/ImageCompressorTests.swift
git commit -m "test: update image compressor preset expectations"
```

---

### Task 2: Update ImageCompressor preset limits

**Files:**
- Modify: `NaarsCars/Core/Utilities/ImageCompressor.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Utilities/ImageCompressorTests.swift`

**Step 1: Write minimal implementation**
```swift
case .avatar: return 1024
case .messageImage: return 2048
```

**Step 2: Run tests**
Run: `xcodebuild test -project "NaarsCars/NaarsCars.xcodeproj" -scheme "NaarsCars" -destination "platform=iOS Simulator,name=iPhone 15" -only-testing:NaarsCarsTests/ImageCompressorTests`
Expected: PASS

**Step 3: Commit**
```bash
git add NaarsCars/Core/Utilities/ImageCompressor.swift
git commit -m "fix: allow higher quality image compression presets"
```

---

### Task 3: Align Town Hall pre-check with preset

**Files:**
- Modify: `NaarsCars/Features/TownHall/ViewModels/CreatePostViewModel.swift`

**Step 1: Update pre-check to use preset**
```swift
let maxDimension: CGFloat = ImagePreset.messageImage.maxDimension
if imageMaxDimension > maxDimension * 2 {
    let maxAllowed = Int(maxDimension * 2)
    throw AppError.invalidInput("Image is too large. Please select a smaller image (max \(maxAllowed)px on longest side).")
}
```

**Step 2: Run tests**
Run: `xcodebuild test -project "NaarsCars/NaarsCars.xcodeproj" -scheme "NaarsCars" -destination "platform=iOS Simulator,name=iPhone 15" -only-testing:NaarsCarsTests/ImageCompressorTests`
Expected: PASS

**Step 3: Commit**
```bash
git add NaarsCars/Features/TownHall/ViewModels/CreatePostViewModel.swift
git commit -m "fix: relax Town Hall image pre-check limits"
```

