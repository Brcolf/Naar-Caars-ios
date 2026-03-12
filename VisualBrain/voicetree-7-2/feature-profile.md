---
color: teal
position:
  x: 5
  y: -876
isContextNode: false
agent_name: Amy
---

# Feature: Profile

User profile management and settings.

## Views
- **ProfileView.swift** - User's own profile display
- **EditProfileView.swift** - Edit name, bio, avatar, phone
- **SettingsView.swift** - App settings (theme, language, biometrics, notifications)
- **PublicProfileView.swift** - View other users' profiles
- **BlockedUsersView.swift** - Manage blocked users list

## ViewModels
- **ProfileViewModel.swift** - Profile data management
- **EditProfileViewModel.swift** - Profile editing with validation
- **SettingsViewModel.swift** - Settings configuration

## Services
- **ProfileService.swift** - CRUD for user profiles
- **BiometricService.swift** - Biometric settings
- **ThemeManager.swift** - Dark mode configuration
- **LocalizationManager.swift** - Language preferences

## Models
- **Profile.swift** - User profile data (name, avatar, phone, admin status, approval)

## Features

### Profile Management
- Edit name, bio, phone number
- Upload avatar to Supabase Storage
- View reputation/leaderboard stats

### Settings
- **Theme:** Light/Dark/System
- **Language:** English/Spanish/etc.
- **Biometrics:** Enable Face ID/Touch ID app lock
- **Notifications:** Configure push notification preferences
- **Account:** Sign out, delete account

### Privacy
- Block/unblock users
- View blocked users list
- Blocked users can't message or see your posts

## Phone Number Requirement

Phone number is required for:
- Claiming rides/favors (contact info for coordination)
- Certain community features

`ClaimViewModel.checkCanClaim()` validates phone before showing claim sheet.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
