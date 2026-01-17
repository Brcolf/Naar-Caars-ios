# Profile Feature - Files to Add to Xcode Project

This document lists all files created for the User Profile feature that need to be added to the Xcode project.

## Core Services
- [ ] `Core/Services/ProfileService.swift`

## Core Utilities
- [ ] `Core/Utilities/Validators.swift`

## Core Models
- [x] `Core/Models/Profile.swift` (already exists, was extended)
- [x] `Core/Models/Review.swift` (already exists)

## Features/Profile/ViewModels
- [ ] `Features/Profile/ViewModels/MyProfileViewModel.swift`
- [ ] `Features/Profile/ViewModels/EditProfileViewModel.swift`
- [ ] `Features/Profile/ViewModels/PublicProfileViewModel.swift`

## Features/Profile/Views
- [ ] `Features/Profile/Views/MyProfileView.swift`
- [ ] `Features/Profile/Views/EditProfileView.swift`
- [ ] `Features/Profile/Views/PublicProfileView.swift`

## UI Components
- [ ] `UI/Components/Common/UserAvatarLink.swift`
- [ ] `UI/Components/Common/StarRatingView.swift`
- [ ] `UI/Components/Cards/ReviewCard.swift`
- [ ] `UI/Components/Cards/InviteCodeCard.swift`

## Test Files
- [ ] `NaarsCarsTests/Core/Services/ProfileServiceTests.swift`
- [ ] `NaarsCarsTests/Core/Utilities/ValidatorsTests.swift`
- [ ] `NaarsCarsTests/Features/Profile/MyProfileViewModelTests.swift`
- [ ] `NaarsCarsTests/Features/Profile/EditProfileViewModelTests.swift`
- [ ] `NaarsCarsTests/Features/Profile/PublicProfileViewModelTests.swift`

## Instructions

1. Open Xcode with `NaarsCars.xcodeproj`
2. For each file listed above:
   - Right-click on the appropriate folder group in Project Navigator
   - Select "Add Files to 'NaarsCars'..."
   - Navigate to the file
   - Make sure:
     - ✅ "Add to targets: NaarsCars" is CHECKED (or "NaarsCarsTests" for test files)
     - ❌ "Copy items if needed" is UNCHECKED
   - Click "Add"
3. Verify all files appear in Project Navigator
4. Build the project (⌘B) to ensure everything compiles

## Quick Add Script

Alternatively, you can use the Python script to add files programmatically (similar to `add-models-to-xcode.py`).





