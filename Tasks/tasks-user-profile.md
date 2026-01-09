# Tasks: User Profile

Based on `prd-user-profile.md`

## Affected Flows

- FLOW_PROFILE_001: View Own Profile
- FLOW_PROFILE_002: Edit Profile
- FLOW_PROFILE_003: Upload Avatar

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/ProfileService.swift` - Profile operations service
- `Core/Models/Profile.swift` - User profile data model (extend from foundation)
- `Core/Models/Review.swift` - Review data model
- `Core/Utilities/Validators.swift` - Phone and input validation ⭐ UPDATED
- `Features/Profile/Views/MyProfileView.swift` - Current user's profile screen
- `Features/Profile/Views/PublicProfileView.swift` - Other users' profile screen
- `Features/Profile/Views/EditProfileView.swift` - Profile editing screen
- `Features/Profile/ViewModels/MyProfileViewModel.swift` - My profile view model
- `Features/Profile/ViewModels/EditProfileViewModel.swift` - Edit profile view model
- `Features/Profile/ViewModels/PublicProfileViewModel.swift` - Public profile view model
- `UI/Components/Common/UserAvatarLink.swift` - Avatar component with navigation
- `UI/Components/Common/StarRatingView.swift` - Star rating display component
- `UI/Components/Cards/ReviewCard.swift` - Review display card
- `UI/Components/Cards/InviteCodeCard.swift` - Invite code card with share action

### Test Files
- `NaarsCarsTests/Core/Services/ProfileServiceTests.swift` - ProfileService unit tests
- `NaarsCarsTests/Core/Utilities/ValidatorsTests.swift` - Phone validation tests
- `NaarsCarsTests/Features/Profile/MyProfileViewModelTests.swift` - My profile VM tests
- `NaarsCarsTests/Features/Profile/EditProfileViewModelTests.swift` - Edit profile VM tests
- `NaarsCarsTests/Features/Profile/PublicProfileViewModelTests.swift` - Public profile VM tests
- `NaarsCarsSnapshotTests/Profile/MyProfileViewSnapshots.swift` - Profile UI snapshots
- `NaarsCarsIntegrationTests/Profile/ProfileUpdateTests.swift` - Profile update integration

## Notes

- This feature depends on `prd-foundation-architecture.md` and `prd-authentication.md` being complete
- Profile pictures are stored in Supabase Storage "avatars" bucket
- Uses native PhotosPicker for image selection
- Average rating is calculated from reviews table
- Invite codes can be shared using native share sheet
- ⭐ NEW items are from Senior Developer Security/Performance Review
- 🧪 items are QA tasks - write tests as you implement
- 🔒 CHECKPOINT items are mandatory quality gates - do not skip

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [x] 0.0 Create feature branch
  - [x] 0.1 Create and checkout a new branch for this feature (e.g., `git checkout -b feature/user-profile`)

- [x] 1.0 Implement ProfileService
  - [x] 1.1 Create ProfileService.swift in Core/Services with @MainActor and singleton pattern
  - [x] 1.2 Implement fetchProfile(userId:) method to query profiles table
  - [x] 1.3 ⭐ Check CacheManager before network request
  - [x] 1.4 ⭐ Cache profile after successful fetch
  - [x] 1.5 Implement updateProfile() method with optional parameters for name, phoneNumber, car, avatarUrl
  - [x] 1.6 ⭐ Invalidate cache after profile update
  - [x] 1.7 🧪 Write ProfileServiceTests.testFetchProfile_CacheHit_ReturnsWithoutNetwork
  - [x] 1.8 🧪 Write ProfileServiceTests.testFetchProfile_CacheMiss_FetchesFromNetwork
  - [x] 1.9 🧪 Write ProfileServiceTests.testUpdateProfile_InvalidatesCache
  - [x] 1.10 Implement uploadAvatar() method to upload to Supabase Storage "avatars" bucket
  - [x] 1.11 ⭐ Use ImageCompressor.compress(preset: .avatar) before upload
  - [x] 1.12 ⭐ Avatar compressed to 400x400, max 200KB
  - [x] 1.13 Use upsert option when uploading avatar to replace existing
  - [x] 1.14 ⭐ Append cache-busting query param to avatar URL after upload
  - [x] 1.15 Implement fetchReviews(forUserId:) with join to get reviewer profile info
  - [x] 1.16 Implement fetchInviteCodes(forUserId:) ordered by created_at descending
  - [x] 1.17 ⭐ Use InviteCodeGenerator.generate() for new 8-character codes
  - [x] 1.18 Implement generateInviteCode(userId:) inserting new code
  - [x] 1.19 Implement calculateAverageRating(userId:) from reviews
  - [x] 1.20 Implement fetchFulfilledCount(userId:) counting confirmed/completed rides and favors
  - [x] 1.21 Add error handling for all methods with appropriate AppError types

- [x] 2.0 Extend Profile and create Review models
  - [x] 2.1 Open Profile.swift and add phoneNumber: String? field
  - [x] 2.2 Add avatarUrl: String? field to Profile
  - [x] 2.3 Add notification preference fields (notifyRideUpdates, notifyMessages, etc.)
  - [x] 2.4 Add computed property for initials (first letters of first and last name)
  - [x] 2.5 ⭐ Create Validators.swift in Core/Utilities if not exists
  - [x] 2.6 ⭐ Implement isValidPhoneNumber(_:) accepting 10-15 digits
  - [x] 2.7 ⭐ Implement formatPhoneForStorage(_:) returning E.164 format (+1XXXXXXXXXX)
  - [x] 2.8 ⭐ Implement displayPhoneNumber(_:masked:) for display formatting
  - [x] 2.9 ⭐ Masked format: "(•••) •••-1234" showing last 4 only
  - [x] 2.10 ⭐ Support international numbers (11-15 digits with country code)
  - [x] 2.11 🧪 Write ValidatorsTests.testIsValidPhoneNumber_ValidUS_ReturnsTrue
  - [x] 2.12 🧪 Write ValidatorsTests.testIsValidPhoneNumber_TooShort_ReturnsFalse
  - [x] 2.13 🧪 Write ValidatorsTests.testFormatPhoneForStorage_ReturnsE164
  - [x] 2.14 🧪 Write ValidatorsTests.testDisplayPhoneNumber_Masked_ShowsLastFour
  - [x] 2.15 Add proper CodingKeys for snake_case to camelCase mapping
  - [x] 2.16 Create Review.swift model in Core/Models
  - [x] 2.17 Add Review fields: id, requestId, fulfillerId, reviewerId, rating, summary, createdAt
  - [x] 2.18 Add optional nested reviewer Profile object for display
  - [x] 2.19 Make Review conform to Codable, Identifiable, Equatable

### 🔒 CHECKPOINT: QA-PROFILE-001
> Run: `./QA/Scripts/checkpoint.sh profile-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ProfileService tests pass, Validators tests pass
> Must pass before continuing

- [x] 3.0 Build My Profile View
  - [x] 3.1 Create MyProfileView.swift in Features/Profile/Views
  - [x] 3.2 Add @StateObject for MyProfileViewModel
  - [x] 3.3 Add @EnvironmentObject to access AppState for current user
  - [x] 3.4 Add header section with avatar, name, email
  - [x] 3.5 Make avatar tappable to open image picker (using PhotosPicker)
  - [x] 3.6 Add "Edit Profile" button navigating to EditProfileView
  - [x] 3.7 Add stats section displaying average rating, review count, fulfilled count
  - [x] 3.8 Add invite codes section with list of codes
  - [x] 3.9 Show code status badge (Available in green, Used in gray)
  - [x] 3.10 Add swipe actions on invite codes for Share and Copy
  - [x] 3.11 Add "Generate Code" button that calls viewModel.generateInviteCode()
  - [x] 3.12 ⭐ Add rate limit: 10 seconds between code generation
  - [x] 3.13 Add reviews section with List of ReviewCards
  - [x] 3.14 Show empty state if no reviews exist
  - [x] 3.15 Add admin panel link at bottom if user is admin
  - [x] 3.16 Add "Log Out" button with confirmation alert
  - [x] 3.17 Add .task modifier to load profile data on appear
  - [x] 3.18 Add pull-to-refresh functionality

- [x] 4.0 Implement MyProfileViewModel
  - [x] 4.1 Create MyProfileViewModel.swift in Features/Profile/ViewModels
  - [x] 4.2 Add @Published properties: profile, reviews, inviteCodes, averageRating, fulfilledCount
  - [x] 4.3 Add @Published isLoading and error properties
  - [x] 4.4 Implement loadProfile(userId:) using async let for parallel requests
  - [x] 4.5 Fetch profile, reviews, invite codes, rating, and count concurrently
  - [x] 4.6 Update all @Published properties with fetched data
  - [x] 4.7 Implement generateInviteCode(userId:) method
  - [x] 4.8 ⭐ Check rate limit before generating
  - [x] 4.9 Insert new code at beginning of inviteCodes array
  - [x] 4.10 Implement refreshProfile() method for pull-to-refresh
  - [x] 4.11 Add error handling that sets error property for UI display
  - [x] 4.12 🧪 Write MyProfileViewModelTests.testLoadProfile_Success_SetsAllProperties
  - [x] 4.13 🧪 Write MyProfileViewModelTests.testGenerateInviteCode_RateLimited_ThrowsError

- [x] 5.0 Build Edit Profile View
  - [x] 5.1 Create EditProfileView.swift in Features/Profile/Views
  - [x] 5.2 Add @StateObject for EditProfileViewModel
  - [x] 5.3 Add form with TextField for name
  - [x] 5.4 Add form with TextField for phone number with .keyboardType(.phonePad)
  - [x] 5.5 ⭐ Add real-time phone formatting as user types
  - [x] 5.6 ⭐ Add info text below phone field: "Your phone number will be visible to community members for ride coordination."
  - [x] 5.7 ⭐ Style info text with info.circle icon and secondary color
  - [x] 5.8 Add form with TextField for car description
  - [x] 5.9 Add PhotosPicker for avatar with preview
  - [x] 5.10 ⭐ Handle photo permission denial with alert and Settings deep-link
  - [x] 5.11 Add "Save" button in navigation bar
  - [x] 5.12 Show loading indicator while saving
  - [x] 5.13 Dismiss view after successful save
  - [x] 5.14 Add validation for required fields
  - [x] 5.15 Show inline error messages for validation failures

- [x] 6.0 ⭐ Add Phone Visibility Confirmation
  - [x] 6.1 Track whether user has previously saved a phone number
  - [x] 6.2 In EditProfileViewModel, add hasShownPhoneDisclosure flag
  - [x] 6.3 When saving with new phone number, check if first time
  - [x] 6.4 If first time, show confirmation alert before saving
  - [x] 6.5 Alert title: "Phone Number Visibility"
  - [x] 6.6 Alert message: "Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?"
  - [x] 6.7 Alert actions: "Yes, Save Number", "Cancel"
  - [x] 6.8 Only proceed with save if user confirms
  - [x] 6.9 Store confirmation in UserDefaults so it only shows once

- [x] 7.0 Implement EditProfileViewModel
  - [x] 7.1 Create EditProfileViewModel.swift in Features/Profile/ViewModels
  - [x] 7.2 Add @Published properties for name, phoneNumber, car, avatarImage
  - [x] 7.3 Add @Published isSaving, isUploadingAvatar, error properties
  - [x] 7.4 Initialize with existing profile values
  - [x] 7.5 Implement validateAndSave() method
  - [x] 7.6 Validate name is not empty
  - [x] 7.7 ⭐ Validate phone using Validators.isValidPhoneNumber() if provided
  - [x] 7.8 ⭐ Format phone using Validators.formatPhoneForStorage()
  - [x] 7.9 Call ProfileService.updateProfile()
  - [x] 7.10 ⭐ Invalidate profile cache after save
  - [x] 7.11 Implement uploadAvatar() using PhotosPicker selection
  - [x] 7.12 ⭐ Compress image using ImageCompressor.compress(preset: .avatar)
  - [x] 7.13 Show error if compression fails: "Image too large. Please try a different photo."
  - [x] 7.14 Call ProfileService.uploadAvatar()
  - [x] 7.15 Update profile with new avatar URL
  - [x] 7.16 Handle errors appropriately
  - [x] 7.17 🧪 Write EditProfileViewModelTests.testValidateAndSave_EmptyName_ReturnsError
  - [x] 7.18 🧪 Write EditProfileViewModelTests.testValidateAndSave_InvalidPhone_ReturnsError
  - [x] 7.19 🧪 Write EditProfileViewModelTests.testUploadAvatar_CompressesImage

### 🔒 CHECKPOINT: QA-PROFILE-002
> Run: `./QA/Scripts/checkpoint.sh profile-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_PROFILE_001, FLOW_PROFILE_002, FLOW_PROFILE_003
> Must pass before continuing

- [x] 8.0 Build Public Profile View
  - [x] 8.1 Create PublicProfileView.swift in Features/Profile/Views
  - [x] 8.2 Accept userId as parameter
  - [x] 8.3 Add @StateObject for PublicProfileViewModel
  - [x] 8.4 Display user avatar (large, centered)
  - [x] 8.5 Show user name
  - [x] 8.6 Show user's car if available
  - [x] 8.7 ⭐ Show phone number MASKED by default: "(•••) •••-1234"
  - [x] 8.8 ⭐ Add @State isPhoneRevealed = false
  - [x] 8.9 ⭐ Add "Reveal Number" button below masked phone
  - [x] 8.10 ⭐ Implement shouldAutoReveal computed property
  - [x] 8.11 ⭐ Auto-reveal if viewing own profile
  - [x] 8.12 ⭐ Auto-reveal if in active conversation with user
  - [x] 8.13 ⭐ Auto-reveal if on same request (poster/claimer relationship)
  - [x] 8.14 ⭐ Add light haptic feedback on reveal tap
  - [x] 8.15 Display average rating with stars
  - [x] 8.16 Show fulfilled count badge
  - [x] 8.17 Add "Send Message" button (navigates to messaging)
  - [x] 8.18 Don't show message button if viewing own profile
  - [x] 8.19 Add reviews section with list of reviews
  - [x] 8.20 Add .task modifier to load profile on appear

- [x] 9.0 Implement PublicProfileViewModel
  - [x] 9.1 Create PublicProfileViewModel.swift in Features/Profile/ViewModels
  - [x] 9.2 Add @Published properties: profile, reviews, averageRating, fulfilledCount
  - [x] 9.3 Add @Published isLoading and error properties
  - [x] 9.4 Implement loadProfile(userId:) method
  - [x] 9.5 ⭐ Check cache before fetching
  - [x] 9.6 Fetch profile, reviews, rating, and count
  - [x] 9.7 Update @Published properties
  - [x] 9.8 Add error handling
  - [x] 9.9 🧪 Write PublicProfileViewModelTests.testLoadProfile_UsesCacheWhenAvailable

- [x] 10.0 Build UI Components
  - [x] 10.1 Create UserAvatarLink.swift in UI/Components/Common
  - [x] 10.2 Accept profile parameter
  - [x] 10.3 Display avatar using AvatarView
  - [x] 10.4 Wrap in NavigationLink to PublicProfileView
  - [x] 10.5 Create StarRatingView.swift in UI/Components/Common
  - [x] 10.6 Accept rating (Double) and optional size parameter
  - [x] 10.7 Display 5 stars with partial fill based on rating
  - [x] 10.8 Create ReviewCard.swift in UI/Components/Cards
  - [x] 10.9 Display reviewer avatar and name
  - [x] 10.10 Show star rating
  - [x] 10.11 Display review summary text
  - [x] 10.12 Show relative timestamp
  - [x] 10.13 Create InviteCodeCard.swift in UI/Components/Cards
  - [x] 10.14 Display formatted code (NC7X · 9K2A · BQ)
  - [x] 10.15 Show status badge (Available/Used)
  - [x] 10.16 Add copy and share actions
  - [x] 10.17 Add Xcode previews for all components

- [x] 11.0 ⭐ Handle Photo Permission Denial
  - [x] 11.1 Check PHPhotoLibrary.authorizationStatus before showing picker
  - [x] 11.2 If denied, show alert: "Photo Access Required"
  - [x] 11.3 Alert message: "To change your profile photo, please enable photo access in Settings."
  - [x] 11.4 Add "Open Settings" button that calls openAppSettings()
  - [x] 11.5 Add "Cancel" button
  - [x] 11.6 Implement openAppSettings() using UIApplication.openSettingsURLString

- [ ] 12.0 Test profile functionality
  - [ ] 12.1 Test viewing own profile - verify all sections display (MANUAL TEST)
  - [ ] 12.2 Test editing profile - verify changes save correctly (MANUAL TEST)
  - [ ] 12.3 Test avatar upload - verify image compresses and uploads (MANUAL TEST)
  - [ ] 12.4 ⭐ Test avatar upload with large image - verify compresses to <200KB (MANUAL TEST)
  - [ ] 12.5 Test generating invite code - verify appears in list (MANUAL TEST)
  - [ ] 12.6 ⭐ Test rapid code generation - verify rate limiting (MANUAL TEST)
  - [ ] 12.7 Test sharing invite code - verify share sheet works (MANUAL TEST)
  - [ ] 12.8 Test viewing other user's profile - verify correct data (MANUAL TEST)
  - [ ] 12.9 ⭐ Test phone masking - verify only last 4 digits visible (MANUAL TEST)
  - [ ] 12.10 ⭐ Test phone reveal - verify full number shows on tap (MANUAL TEST)
  - [ ] 12.11 ⭐ Test auto-reveal for conversation partner (MANUAL TEST - requires messaging feature)
  - [ ] 12.12 ⭐ Test first-time phone save - verify confirmation alert (MANUAL TEST)
  - [ ] 12.13 Test reviews display - verify correct formatting (MANUAL TEST)

- [ ] 13.0 Verify profile implementation
  - [x] 13.1 Build project and ensure zero compilation errors (FILES ADDED - VERIFY IN XCODE)
  - [ ] 13.2 Verify my profile displays correctly (MANUAL TEST)
  - [ ] 13.3 Verify edit profile saves changes (MANUAL TEST)
  - [ ] 13.4 Verify avatar upload works with compression (MANUAL TEST)
  - [ ] 13.5 Verify invite codes generate and display (MANUAL TEST)
  - [ ] 13.6 Verify public profile displays correctly (MANUAL TEST)
  - [ ] 13.7 ⭐ Verify phone masking and reveal works (MANUAL TEST)
  - [ ] 13.8 ⭐ Verify phone visibility disclosure shows (MANUAL TEST)
  - [ ] 13.9 Verify reviews display correctly (MANUAL TEST)
  - [ ] 13.10 Verify caching improves navigation speed (MANUAL TEST)
  - [x] 13.11 Code review: verify no force unwrapping ✅
  - [x] 13.12 Code review: verify proper async/await error handling ✅
  - [ ] 13.13 Commit changes with message: "feat: implement user profile with privacy controls"
  - [ ] 13.14 Push feature branch to remote repository

### 🔒 CHECKPOINT: QA-PROFILE-FINAL
> Run: `./QA/Scripts/checkpoint.sh profile-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_PROFILE_001, FLOW_PROFILE_002, FLOW_PROFILE_003
> All profile tests must pass before starting Ride Requests
