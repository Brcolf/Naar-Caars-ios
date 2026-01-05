# PRD: Dark Mode

## Document Information
- **Feature Name**: Dark Mode
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines dark mode support for the Naar's Cars iOS app. Dark mode provides an alternative color scheme optimized for low-light environments.

### Why does this matter?
- **User preference**: Many users prefer dark mode
- **Battery life**: OLED screens use less power with dark UI
- **Eye strain**: Reduces eye strain in low-light conditions
- **System integration**: iOS users expect apps to respect system appearance
- **Modern expectation**: Dark mode is standard in modern apps

### What problem does it solve?
- Bright screens uncomfortable at night
- Inconsistent experience when system is in dark mode
- Battery drain on OLED devices
- Accessibility for light-sensitive users

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Support system appearance | App follows iOS dark/light setting |
| Manual override | Users can force light/dark |
| Consistent theming | All screens properly themed |
| Brand consistency | Colors work in both modes |
| Smooth transitions | No flash when switching |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| DARK-01 | User | Have the app follow my system setting | I don't need to configure each app |
| DARK-02 | User | Override the system setting | I can use dark mode even if system is light |
| DARK-03 | User | See smooth transitions | Theme changes aren't jarring |
| DARK-04 | User | Have readable text always | Content is accessible in any mode |
| DARK-05 | User | See the brand colors preserved | The app still feels like Naar's Cars |

---

## 4. Functional Requirements

### 4.1 Color System

**Requirement DARK-FR-001**: Define adaptive colors that work in both modes:

```swift
// UI/Styles/ColorTheme.swift
import SwiftUI

extension Color {
    // MARK: - Brand Colors (static - same in both modes)
    
    /// Primary brand color (terracotta/rust)
    static let naarsPrimary = Color(hex: "B5634B")
    
    /// Accent color (warm amber)
    static let naarsAccent = Color(hex: "D4A574")
    
    // MARK: - Adaptive Colors (change with appearance)
    
    /// Primary background
    static let naarsBackground = Color("Background")
    
    /// Secondary background (cards, sections)
    static let naarsSecondaryBackground = Color("SecondaryBackground")
    
    /// Tertiary background (nested elements)
    static let naarsTertiaryBackground = Color("TertiaryBackground")
    
    /// Primary text
    static let naarsText = Color("TextPrimary")
    
    /// Secondary text
    static let naarsTextSecondary = Color("TextSecondary")
    
    /// Muted/disabled text
    static let naarsTextMuted = Color("TextMuted")
    
    /// Border/separator color
    static let naarsBorder = Color("Border")
    
    /// Success color
    static let naarsSuccess = Color("Success")
    
    /// Warning color
    static let naarsWarning = Color("Warning")
    
    /// Error color
    static let naarsError = Color("Error")
    
    // MARK: - Gradient Backgrounds
    
    /// Main app background gradient
    static func naarsGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(hex: "1C1917"),  // Dark warm gray
                    Color(hex: "1C1917")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(hex: "FEF7ED"),  // Light amber
                    Color(hex: "FEF2F2")   // Light red/pink
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
```

### 4.2 Asset Catalog Colors

**Requirement DARK-FR-002**: Define colors in Assets.xcassets:

Create Color Sets for each adaptive color:

| Color Name | Light Mode | Dark Mode |
|------------|------------|-----------|
| Background | #FFFFFF | #1C1917 |
| SecondaryBackground | #F5F5F4 | #292524 |
| TertiaryBackground | #E7E5E4 | #3D3A38 |
| TextPrimary | #1C1917 | #FAFAF9 |
| TextSecondary | #57534E | #A8A29E |
| TextMuted | #A8A29E | #78716C |
| Border | #E7E5E4 | #3D3A38 |
| Success | #22C55E | #4ADE80 |
| Warning | #F59E0B | #FBBF24 |
| Error | #EF4444 | #F87171 |

### 4.3 Appearance Settings

**Requirement DARK-FR-003**: Appearance options:

```swift
// Core/Utilities/AppearanceManager.swift
import SwiftUI

/// Manages app appearance (light/dark mode)
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    
    @AppStorage("appearance_mode") var appearanceMode: AppearanceMode = .system
    
    private init() {}
    
    /// Apply the current appearance setting
    func applyAppearance() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        
        window.overrideUserInterfaceStyle = appearanceMode.userInterfaceStyle
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
```

### 4.4 Settings UI

**Requirement DARK-FR-004**: Appearance settings view:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â† Appearance                      â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   THEME                             â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ â—‰ System                    â”‚   â”‚
â”‚   â”‚   Match device settings     â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ Light                     â”‚   â”‚
â”‚   â”‚   Always use light mode     â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ Dark                      â”‚   â”‚
â”‚   â”‚   Always use dark mode      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   PREVIEW                           â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚   [Preview card showing     â”‚   â”‚
â”‚   â”‚    current theme]           â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

```swift
// Features/Profile/Views/AppearanceSettingsView.swift
struct AppearanceSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Form {
            Section("Theme") {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearanceManager.appearanceMode = mode
                        appearanceManager.applyAppearance()
                    } label: {
                        HStack {
                            Image(systemName: mode.iconName)
                                .foregroundColor(mode == appearanceManager.appearanceMode ? .accentColor : .secondary)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                                    .foregroundColor(.primary)
                                Text(descriptionFor(mode))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if mode == appearanceManager.appearanceMode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            
            Section("Preview") {
                ThemePreviewCard()
            }
        }
        .navigationTitle("Appearance")
    }
    
    private func descriptionFor(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "Match device settings"
        case .light: return "Always use light mode"
        case .dark: return "Always use dark mode"
        }
    }
}

struct ThemePreviewCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.naarsPrimary)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text("John Smith")
                        .font(.headline)
                    Text("Capitol Hill â†’ SEA")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Open")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.naarsSuccess.opacity(0.2))
                    .foregroundColor(.naarsSuccess)
                    .cornerRadius(4)
            }
            
            Text("Mon, Jan 6 â€¢ 8:00 AM")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.naarsSecondaryBackground)
        .cornerRadius(12)
    }
}
```

### 4.5 App Integration

**Requirement DARK-FR-005**: Apply appearance on app launch:

```swift
// App/NaarsCarsApp.swift
@main
struct NaarsCarsApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appearanceManager = AppearanceManager.shared
    
    init() {
        // Apply saved appearance setting on launch
        AppearanceManager.shared.applyAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appearanceManager)
        }
    }
}
```

### 4.6 Component Updates

**Requirement DARK-FR-006**: Update all components to use adaptive colors:

```swift
// Example: RideCard updated for dark mode
struct RideCard: View {
    let ride: Ride
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                AvatarView(url: ride.poster?.avatarUrl, name: ride.poster?.name ?? "")
                
                VStack(alignment: .leading) {
                    Text(ride.poster?.name ?? "Unknown")
                        .font(.headline)
                        .foregroundColor(.naarsText)
                    
                    Text("\(ride.pickup) â†’ \(ride.destination)")
                        .font(.subheadline)
                        .foregroundColor(.naarsTextSecondary)
                }
                
                Spacer()
                
                StatusBadge(status: ride.status)
            }
            
            // Date/Time
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.naarsTextMuted)
                Text(ride.date.shortDateString)
                    .foregroundColor(.naarsTextSecondary)
                
                Image(systemName: "clock")
                    .foregroundColor(.naarsTextMuted)
                Text(ride.time.timeString)
                    .foregroundColor(.naarsTextSecondary)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.naarsSecondaryBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.naarsBorder, lineWidth: 1)
        )
    }
}
```

### 4.7 Image Assets

**Requirement DARK-FR-007**: Provide dark mode variants for images:

| Asset | Light Mode | Dark Mode |
|-------|------------|-----------|
| AppLogo | Standard logo | Inverted/bright logo |
| EmptyStateIcons | Dark icons | Light icons |
| OnboardingImages | Standard | Adjusted for dark |

Configure in Assets.xcassets:
1. Select image asset
2. In Attributes Inspector, set "Appearances" to "Any, Dark"
3. Add dark mode variant

### 4.8 Status Bar

**Requirement DARK-FR-008**: Status bar adapts automatically with SwiftUI.

For any custom handling:
```swift
.preferredColorScheme(appearanceManager.appearanceMode == .dark ? .dark : 
                      appearanceManager.appearanceMode == .light ? .light : nil)
```

---

## 5. Color Specifications

### 5.1 Light Mode Palette

| Element | Color | Hex |
|---------|-------|-----|
| Background | White | #FFFFFF |
| Secondary BG | Stone 100 | #F5F5F4 |
| Tertiary BG | Stone 200 | #E7E5E4 |
| Text Primary | Stone 900 | #1C1917 |
| Text Secondary | Stone 600 | #57534E |
| Text Muted | Stone 400 | #A8A29E |
| Border | Stone 200 | #E7E5E4 |
| Primary | Terracotta | #B5634B |
| Accent | Amber | #D4A574 |
| Success | Green 500 | #22C55E |
| Warning | Amber 500 | #F59E0B |
| Error | Red 500 | #EF4444 |

### 5.2 Dark Mode Palette

| Element | Color | Hex |
|---------|-------|-----|
| Background | Stone 900 | #1C1917 |
| Secondary BG | Stone 800 | #292524 |
| Tertiary BG | Stone 700 | #3D3A38 |
| Text Primary | Stone 50 | #FAFAF9 |
| Text Secondary | Stone 400 | #A8A29E |
| Text Muted | Stone 500 | #78716C |
| Border | Stone 700 | #3D3A38 |
| Primary | Terracotta (same) | #B5634B |
| Accent | Amber (same) | #D4A574 |
| Success | Green 400 | #4ADE80 |
| Warning | Amber 400 | #FBBF24 |
| Error | Red 400 | #F87171 |

---

## 6. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Custom themes | Light/Dark/System is sufficient |
| Scheduled dark mode | iOS handles this at system level |
| Per-screen themes | Consistent throughout app |
| Animated theme transitions | System handles smoothly |

---

## 7. Design Considerations

### iOS Guidelines

- Use semantic colors when possible (`.primary`, `.secondary`)
- Use system backgrounds (`.background`, `.secondarySystemBackground`)
- Don't use pure black (#000000) - use dark gray for depth
- Maintain minimum contrast ratios (4.5:1 for text)

### Brand Preservation

- Primary brand color stays consistent
- Accent colors may need slight adjustment for visibility
- Logo should have both variants

---

## 8. Technical Considerations

### SwiftUI Automatic Support

SwiftUI handles many things automatically:
- System colors adapt automatically
- `.primary` and `.secondary` text colors
- `.background` modifier

### Testing

- Test all screens in both modes
- Test transitions between modes
- Test with "Increase Contrast" accessibility setting
- Test with "Reduce Transparency"

---

## 9. Dependencies

### Depends On
- `prd-foundation-architecture.md`

### Affects
- All UI components
- All views

---

## 10. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| System mode | Follows device setting | Toggle in Settings |
| Manual override | Respects user choice | Set to dark, verify |
| All screens themed | No bright flashes | Navigate full app |
| Text readable | Passes contrast check | Accessibility audit |
| Persists across launches | Setting remembered | Relaunch app |

---

## 11. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| True black option for OLED? | **No** | Dark gray is better UX |
| Separate icon for dark mode? | **Optional** | Can add later |
| Widget dark mode? | **Future** | Not in scope now |

---

*End of PRD: Dark Mode*
