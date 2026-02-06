# Naar's Cars Brand Images Setup Guide

This guide explains how to add the brand images to the app and where each is used.

---

## Image Locations and Usage

### 1. Full Logo (Red Car with "Community Ride Sharing")
**Asset Name:** `NaarsLogo`
**Used In:**
- **Login Screen** - Large logo at the top
- **Sign Up Screen** - Logo before invite code entry

**File:** `NaarsCars/NaarsCars/Assets.xcassets/NaarsLogo.imageset/`

### 2. App Icon (Black Car with "Driving People Crazy")
**Asset Name:** `AppIcon`
**Used In:**
- **Home Screen App Icon**
- **Settings → App Icon display**

**File:** `NaarsCars/NaarsCars/Assets.xcassets/AppIcon.appiconset/`

### 3. Supreme Leader (Crowned Businessman Character)
**Asset Name:** `SupremeLeader`
**Used In:**
- **Settings → About Section**
- **Empty States** (optional - can be passed to EmptyStateView)

**File:** `NaarsCars/NaarsCars/Assets.xcassets/SupremeLeader.imageset/`

### 4. Text Logo (Red "NAAR'S CAR'S" text only)
**Asset Name:** `NaarsTextLogo`
**Used In:**
- Reserved for navigation headers, loading screens, or splash screen (optional)

**File:** `NaarsCars/NaarsCars/Assets.xcassets/NaarsTextLogo.imageset/`

---

## How to Add Images

### Step 1: Prepare Image Files

For each image set, you need 3 versions at different scales:

| Scale | Multiplier | Example: 100px base |
|-------|------------|---------------------|
| @1x   | 1x         | 100×100 px          |
| @2x   | 2x         | 200×200 px          |
| @3x   | 3x         | 300×300 px          |

### Step 2: Add to Asset Catalogs

#### For NaarsLogo:
1. Open `NaarsCars/NaarsCars/Assets.xcassets/NaarsLogo.imageset/`
2. Add these files:
   - `naars-logo.png` (1x)
   - `naars-logo@2x.png` (2x)
   - `naars-logo@3x.png` (3x)

Recommended base size: **280×200 px** (so 3x = 840×600 px)

#### For NaarsMascot:
1. Open `NaarsCars/NaarsCars/Assets.xcassets/NaarsMascot.imageset/`
2. Add these files:
   - `naars-mascot.png` (1x)
   - `naars-mascot@2x.png` (2x)
   - `naars-mascot@3x.png` (3x)

Recommended base size: **100×100 px** (so 3x = 300×300 px)

#### For NaarsTextLogo:
1. Open `NaarsCars/NaarsCars/Assets.xcassets/NaarsTextLogo.imageset/`
2. Add these files:
   - `naars-text-logo.png` (1x)
   - `naars-text-logo@2x.png` (2x)
   - `naars-text-logo@3x.png` (3x)

#### For App Icon (Black Car "Driving People Crazy"):
1. Open `NaarsCars/NaarsCars/Assets.xcassets/AppIcon.appiconset/`
2. Add these files (all must be square, no transparency for iOS):

**iOS (Required):**
- `app-icon-1024.png` - 1024×1024 px (main iOS icon)
- `app-icon-1024-dark.png` - 1024×1024 px (dark mode variant)
- `app-icon-1024-tinted.png` - 1024×1024 px (tinted variant)

**macOS (If supporting Mac):**
- `app-icon-16.png` - 16×16 px
- `app-icon-32.png` - 32×32 px
- `app-icon-64.png` - 64×64 px
- `app-icon-128.png` - 128×128 px
- `app-icon-256.png` - 256×256 px
- `app-icon-512.png` - 512×512 px

---

## App Icon Tips

For the "Driving People Crazy" black car design:

1. **Use a solid background** - iOS app icons cannot have transparency. Use the cream/beige background from the original image.

2. **Ensure readability at small sizes** - The car silhouette and text should be clear even at 29×29 pt.

3. **Test in context** - Use iOS Simulator to see how it looks on the home screen.

4. **Consider icon variants:**
   - **Light mode**: Original design on cream background
   - **Dark mode**: Could invert to white car on dark background
   - **Tinted**: Monochrome version for system tinting

---

## Code Usage Examples

### Using the Logo in a View:
```swift
Image("NaarsLogo")
    .resizable()
    .scaledToFit()
    .frame(maxWidth: 280, maxHeight: 200)
```

### Using the Mascot in Empty States:
```swift
EmptyStateView(
    icon: "",
    title: "No Rides Yet",
    message: "Be the first to request a ride!",
    customImage: "NaarsMascot"
)
```

### Using the Text Logo in Navigation:
```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        Image("NaarsTextLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 30)
    }
}
```

---

## Files Modified

The following files were updated to use the new brand images:

1. **`LoginView.swift`** - Added NaarsLogo at top
2. **`SignupInviteCodeView.swift`** - Added NaarsLogo at top
3. **`SettingsView.swift`** - Added About section with NaarsMascot
4. **`EmptyStateView.swift`** - Added optional custom image support
5. **`View+Extensions.swift`** - Added Bundle.appVersion helper

---

## Quick Checklist

- [ ] Export full logo as `naars-logo@1x/2x/3x.png`
- [ ] Export mascot as `naars-mascot@1x/2x/3x.png`
- [ ] Export text logo as `naars-text-logo@1x/2x/3x.png`
- [ ] Export app icon at 1024×1024 with solid background
- [ ] Add all files to respective `.imageset` folders
- [ ] Build and run to verify images appear correctly
- [ ] Test app icon on home screen

---

*Last Updated: January 2026*

