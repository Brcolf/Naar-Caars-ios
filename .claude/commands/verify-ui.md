---
description: Build, then capture a SwiftUI view in light, dark, and large-text variants (Xcode MCP RenderPreview, or headless simctl fallback) and report layout issues
argument-hint: <ViewName>
---

Visually verify the SwiftUI view `$ARGUMENTS`. Report only; do not edit code in this command.

**Locate.** Find `$ARGUMENTS.swift` under `NaarsCars/` (Features/, UI/Components/). Note whether it has a `#Preview`. UIKit messaging surfaces (`MessagesCollectionView`, `MessageThreadViewController`, `MessagesViewController`) have none; use Lane B for those.

**Lane A — Xcode MCP (use when the `xcode` MCP tools are available):**
1. `XcodeListWindows` → `tabIdentifier` for the NaarsCars window. If none, fall back to Lane B and say why.
2. `BuildProject` with `scheme: "NaarsCars"`; `GetBuildLog` with `severity: "error"`. On errors, stop and list them. Never snapshot an unbuilt view.
3. `RenderPreview` with `filePath` = the view's absolute path (and `previewName` if the file has several). Read `supportedPreviewVariantOverrides` from the result.
4. Render again with `previewVariantOverrides` for: dark appearance; the largest accessibility type size offered; landscape only if the view is a full screen that rotates (not sheets, cards, rows). Use the group and variant names exactly as step 3 returned them.

**Lane B — headless (Xcode closed; use when MCP is unavailable or the view is UIKit):**
1. `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build`. On errors, stop and list them.
2. `xcrun simctl boot 'iPhone 16'`; `xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/NaarsCars.app`; `xcrun simctl launch booted com.NaarsCars`.
3. Navigate to the screen (ask the user for the path if it is behind auth you cannot satisfy), then capture: light → `xcrun simctl io booted screenshot build/ui-light.png`; `xcrun simctl ui booted appearance dark` → screenshot; `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large` → screenshot. Reset with `appearance light` and `content_size large`, then `xcrun simctl shutdown booted`.
4. Read each PNG with the Read tool.

**Inspect every image** for: clipped or truncated text at the large size, overlapping elements, hard-coded colors or poor contrast in dark mode, safe-area violations, and for messaging views reaction badges anywhere other than the top of the bubble.

**Report:**
- Build: pass / fail (error count)
- Lane used and why
- Variants rendered: each with pass / issue
- Issues: one bullet each, naming the variant and the visible problem
- Not verified: anything you could not render and why
