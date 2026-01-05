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

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch
  - [ ] 0.1 Create and checkout a new branch for this feature (e.g., `git checkout -b feature/user-profile`)

- [ ] 1.0 Implement ProfileService
  - [ ] 1.1 Create ProfileService.swift in Core/Services with @MainActor and singleton pattern
  - [ ] 1.2 Implement fetchProfile(userId:) method to query profiles table
  - [ ] 1.3 ⭐ Check CacheManager before network request
  - [ ] 1.4 ⭐ Cache profile after successful fetch
  - [ ] 1.5 Implement updateProfile() method with optional parameters for name, phoneNumber, car, avatarUrl
  - [ ] 1.6 ⭐ Invalidate cache after profile update
  - [ ] 1.7 🧪 Write ProfileServiceTests.testFetchProfile_CacheHit_ReturnsWithoutNetwork
  - [ ] 1.8 🧪 Write ProfileServiceTests.testFetchProfile_CacheMiss_FetchesFromNetwork
  - [ ] 1.9 🧪 Write ProfileServiceTests.testUpdateProfile_InvalidatesCache
  - [ ] 1.10 Implement uploadAvatar() method to upload to Supabase Storage "avatars" bucket
  - [ ] 1.11 ⭐ Use ImageCompressor.compress(preset: .avatar) before upload
  - [ ] 1.12 ⭐ Avatar compressed to 400x400, max 200KB
  - [ ] 1.13 Use upsert option when uploading avatar to replace existing
  - [ ] 1.14 ⭐ Append cache-busting query param to avatar URL after upload
  - [ ] 1.15 Implement fetchReviews(forUserId:) with join to get reviewer profile info
  - [ ] 1.16 Implement fetchInviteCodes(forUserId:) ordered by created_at descending
  - [ ] 1.17 ⭐ Use InviteCodeGenerator.generate() for new 8-character codes
  - [ ] 1.18 Implement generateInviteCode(userId:) inserting new code
  - [ ] 1.19 Implement calculateAverageRating(userId:) from reviews
  - [ ] 1.20 Implement fetchFulfilledCount(userId:) counting confirmed/completed rides and favors
  - [ ] 1.21 Add error handling for all methods with appropriate AppError types

- [ ] 2.0 Extend Profile and create Review models
  - [ ] 2.1 Open Profile.swift and add phoneNumber: String? field
  - [ ] 2.2 Add avatarUrl: String? field to Profile
  - [ ] 2.3 Add notification preference fields (notifyRideUpdates, notifyMessages, etc.)
  - [ ] 2.4 Add computed property for initials (first letters of first and last name)
  - [ ] 2.5 ⭐ Create Validators.swift in Core/Utilities if not exists
  - [ ] 2.6 ⭐ Implement isValidPhoneNumber(_:) accepting 10-15 digits
  - [ ] 2.7 ⭐ Implement formatPhoneForStorage(_:) returning E.164 format (+1XXXXXXXXXX)
  - [ ] 2.8 ⭐ Implement displayPhoneNumber(_:masked:) for display formatting
  - [ ] 2.9 ⭐ Masked format: "(•••) •••-1234" showing last 4 only
  - [ ] 2.10 ⭐ Support international numbers (11-15 digits with country code)
  - [ ] 2.11 🧪 Write ValidatorsTests.testIsValidPhoneNumber_ValidUS_ReturnsTrue
  - [ ] 2.12 🧪 Write ValidatorsTests.testIsValidPhoneNumber_TooShort_ReturnsFalse
  - [ ] 2.13 🧪 Write ValidatorsTests.testFormatPhoneForStorage_ReturnsE164
  - [ ] 2.14 🧪 Write ValidatorsTests.testDisplayPhoneNumber_Masked_ShowsLastFour
  - [ ] 2.15 Add proper CodingKeys for snake_case to camelCase mapping
  - [ ] 2.16 Create Review.swift model in Core/Models
  - [ ] 2.17 Add Review fields: id, requestId, fulfillerId, reviewerId, rating, summary, createdAt
  - [ ] 2.18 Add optional nested reviewer Profile object for display
  - [ ] 2.19 Make Review conform to Codable, Identifiable, Equatable

### 🔒 CHECKPOINT: QA-PROFILE-001
> Run: `./QA/Scripts/checkpoint.sh profile-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ProfileService tests pass, Validators tests pass
> Must pass before continuing

- [ ] 3.0 Build My Profile View
  - [ ] 3.1 Create MyProfileView.swift in Features/Profile/Views
  - [ ] 3.2 Add @StateObject for MyProfileViewModel
  - [ ] 3.3 Add @EnvironmentObject to access AppState for current user
  - [ ] 3.4 Add header section with avatar, name, email
  - [ ] 3.5 Make avatar tappable to open image picker (using PhotosPicker)
  - [ ] 3.6 Add "Edit Profile" button navigating to EditProfileView
  - [ ] 3.7 Add stats section displaying average rating, review count, fulfilled count
  - [ ] 3.8 Add invite codes section with list of codes
  - [ ] 3.9 Show code status badge (Available in green, Used in gray)
  - [ ] 3.10 Add swipe actions on invite codes for Share and Copy
  - [ ] 3.11 Add "Generate Code" button that calls viewModel.generateInviteCode()
  - [ ] 3.12 ⭐ Add rate limit: 10 seconds between code generation
  - [ ] 3.13 Add reviews section with List of ReviewCards
  - [ ] 3.14 Show empty state if no reviews exist
  - [ ] 3.15 Add admin panel link at bottom if user is admin
  - [ ] 3.16 Add "Log Out" button with confirmation alert
  - [ ] 3.17 Add .task modifier to load profile data on appear
  - [ ] 3.18 Add pull-to-refresh functionality

- [ ] 4.0 Implement MyProfileViewModel
  - [ ] 4.1 Create MyProfileViewModel.swift in Features/Profile/ViewModels
  - [ ] 4.2 Add @Published properties: profile, reviews, inviteCodes, averageRating, fulfilledCount
  - [ ] 4.3 Add @Published isLoading and error properties
  - [ ] 4.4 Implement loadProfile(userId:) using async let for parallel requests
  - [ ] 4.5 Fetch profile, reviews, invite codes, rating, and count concurrently
  - [ ] 4.6 Update all @Published properties with fetched data
  - [ ] 4.7 Implement generateInviteCode(userId:) method
  - [ ] 4.8 ⭐ Check rate limit before generating
  - [ ] 4.9 Insert new code at beginning of inviteCodes array
  - [ ] 4.10 Implement refreshProfile() method for pull-to-refresh
  - [ ] 4.11 Add error handling that sets error property for UI display
  - [ ] 4.12 🧪 Write MyProfileViewModelTests.testLoadProfile_Success_SetsAllProperties
  - [ ] 4.13 🧪 Write MyProfileViewModelTests.testGenerateInviteCode_RateLimited_ThrowsError

- [ ] 5.0 Build Edit Profile View
  - [ ] 5.1 Create EditProfileView.swift in Features/Profile/Views
  - [ ] 5.2 Add @StateObject for EditProfileViewModel
  - [ ] 5.3 Add form with TextField for name
  - [ ] 5.4 Add form with TextField for phone number with .keyboardType(.phonePad)
  - [ ] 5.5 ⭐ Add real-time phone formatting as user types
  - [ ] 5.6 ⭐ Add info text below phone field: "Your phone number will be visible to community members for ride coordination."
  - [ ] 5.7 ⭐ Style info text with info.circle icon and secondary color
  - [ ] 5.8 Add form with TextField for car description
  - [ ] 5.9 Add PhotosPicker for avatar with preview
  - [ ] 5.10 ⭐ Handle photo permission denial with alert and Settings deep-link
  - [ ] 5.11 Add "Save" button in navigation bar
  - [ ] 5.12 Show loading indicator while saving
  - [ ] 5.13 Dismiss view after successful save
  - [ ] 5.14 Add validation for required fields
  - [ ] 5.15 Show inline error messages for validation failures

- [ ] 6.0 ⭐ Add Phone Visibility Confirmation
  - [ ] 6.1 Track whether user has previously saved a phone number
  - [ ] 6.2 In EditProfileViewModel, add hasShownPhoneDisclosure flag
  - [ ] 6.3 When saving with new phone number, check if first time
  - [ ] 6.4 If first time, show confirmation alert before saving
  - [ ] 6.5 Alert title: "Phone Number Visibility"
  - [ ] 6.6 Alert message: "Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?"
  - [ ] 6.7 Alert actions: "Yes, Save Number", "Cancel"
  - [ ] 6.8 Only proceed with save if user confirms
  - [ ] 6.9 Store confirmation in UserDefaults so it only shows once

- [ ] 7.0 Implement EditProfileViewModel
  - [ ] 7.1 Create EditProfileViewModel.swift in Features/Profile/ViewModels
  - [ ] 7.2 Add @Published properties for name, phoneNumber, car, avatarImage
  - [ ] 7.3 Add @Published isSaving, isUploadingAvatar, error properties
  - [ ] 7.4 Initialize with existing profile values
  - [ ] 7.5 Implement validateAndSave() method
  - [ ] 7.6 Validate name is not empty
  - [ ] 7.7 ⭐ Validate phone using Validators.isValidPhoneNumber() if provided
  - [ ] 7.8 ⭐ Format phone using Validators.formatPhoneForStorage()
  - [ ] 7.9 Call ProfileService.updateProfile()
  - [ ] 7.10 ⭐ Invalidate profile cache after save
  - [ ] 7.11 Implement uploadAvatar() using PhotosPicker selection
  - [ ] 7.12 ⭐ Compress image using ImageCompressor.compress(preset: .avatar)
  - [ ] 7.13 Show error if compression fails: "Image too large. Please try a different photo."
  - [ ] 7.14 Call ProfileService.uploadAvatar()
  - [ ] 7.15 Update profile with new avatar URL
  - [ ] 7.16 Handle errors appropriately
  - [ ] 7.17 🧪 Write EditProfileViewModelTests.testValidateAndSave_EmptyName_ReturnsError
  - [ ] 7.18 🧪 Write EditProfileViewModelTests.testValidateAndSave_InvalidPhone_ReturnsError
  - [ ] 7.19 🧪 Write EditProfileViewModelTests.testUploadAvatar_CompressesImage

### 🔒 CHECKPOINT: QA-PROFILE-002
> Run: `./QA/Scripts/checkpoint.sh profile-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_PROFILE_001, FLOW_PROFILE_002, FLOW_PROFILE_003
> Must pass before continuing

- [ ] 8.0 Build Public Profile View
  - [ ] 8.1 Create PublicProfileView.swift in Features/Profile/Views
  - [ ] 8.2 Accept userId as parameter
  - [ ] 8.3 Add @StateObject for PublicProfileViewModel
  - [ ] 8.4 Display user avatar (large, centered)
  - [ ] 8.5 Show user name
  - [ ] 8.6 Show user's car if available
  - [ ] 8.7 ⭐ Show phone number MASKED by default: "(•••) •••-1234"
  - [ ] 8.8 ⭐ Add @State isPhoneRevealed = false
  - [ ] 8.9 ⭐ Add "Reveal Number" button below masked phone
  - [ ] 8.10 ⭐ Implement shouldAutoReveal computed property
  - [ ] 8.11 ⭐ Auto-reveal if viewing own profile
  - [ ] 8.12 ⭐ Auto-reveal if in active conversation with user
  - [ ] 8.13 ⭐ Auto-reveal if on same request (poster/claimer relationship)
  - [ ] 8.14 ⭐ Add light haptic feedback on reveal tap
  - [ ] 8.15 Display average rating with stars
  - [ ] 8.16 Show fulfilled count badge
  - [ ] 8.17 Add "Send Message" button (navigates to messaging)
  - [ ] 8.18 Don't show message button if viewing own profile
  - [ ] 8.19 Add reviews section with list of reviews
  - [ ] 8.20 Add .task modifier to load profile on appear

- [ ] 9.0 Implement PublicProfileViewModel
  - [ ] 9.1 Create PublicProfileViewModel.swift in Features/Profile/ViewModels
  - [ ] 9.2 Add @Published properties: profile, reviews, averageRating, fulfilledCount
  - [ ] 9.3 Add @Published isLoading and error properties
  - [ ] 9.4 Implement loadProfile(userId:) method
  - [ ] 9.5 ⭐ Check cache before fetching
  - [ ] 9.6 Fetch profile, reviews, rating, and count
  - [ ] 9.7 Update @Published properties
  - [ ] 9.8 Add error handling
  - [ ] 9.9 🧪 Write PublicProfileViewModelTests.testLoadProfile_UsesCacheWhenAvailable

- [ ] 10.0 Build UI Components
  - [ ] 10.1 Create UserAvatarLink.swift in UI/Components/Common
  - [ ] 10.2 Accept profile parameter
  - [ ] 10.3 Display avatar using AvatarView
  - [ ] 10.4 Wrap in NavigationLink to PublicProfileView
  - [ ] 10.5 Create StarRatingView.swift in UI/Components/Common
  - [ ] 10.6 Accept rating (Double) and optional size parameter
  - [ ] 10.7 Display 5 stars with partial fill based on rating
  - [ ] 10.8 Create ReviewCard.swift in UI/Components/Cards
  - [ ] 10.9 Display reviewer avatar and name
  - [ ] 10.10 Show star rating
  - [ ] 10.11 Display review summary text
  - [ ] 10.12 Show relative timestamp
  - [ ] 10.13 Create InviteCodeCard.swift in UI/Components/Cards
  - [ ] 10.14 Display formatted code (NC7X · 9K2A · BQ)
  - [ ] 10.15 Show status badge (Available/Used)
  - [ ] 10.16 Add copy and share actions
  - [ ] 10.17 Add Xcode previews for all components

- [ ] 11.0 ⭐ Handle Photo Permission Denial
  - [ ] 11.1 Check PHPhotoLibrary.authorizationStatus before showing picker
  - [ ] 11.2 If denied, show alert: "Photo Access Required"
  - [ ] 11.3 Alert message: "To change your profile photo, please enable photo access in Settings."
  - [ ] 11.4 Add "Open Settings" button that calls openAppSettings()
  - [ ] 11.5 Add "Cancel" button
  - [ ] 11.6 Implement openAppSettings() using UIApplication.openSettingsURLString

- [ ] 12.0 Test profile functionality
  - [ ] 12.1 Test viewing own profile - verify all sections display
  - [ ] 12.2 Test editing profile - verify changes save correctly
  - [ ] 12.3 Test avatar upload - verify image compresses and uploads
  - [ ] 12.4 ⭐ Test avatar upload with large image - verify compresses to <200KB
  - [ ] 12.5 Test generating invite code - verify appears in list
  - [ ] 12.6 ⭐ Test rapid code generation - verify rate limiting
  - [ ] 12.7 Test sharing invite code - verify share sheet works
  - [ ] 12.8 Test viewing other user's profile - verify correct data
  - [ ] 12.9 ⭐ Test phone masking - verify only last 4 digits visible
  - [ ] 12.10 ⭐ Test phone reveal - verify full number shows on tap
  - [ ] 12.11 ⭐ Test auto-reveal for conversation partner
  - [ ] 12.12 ⭐ Test first-time phone save - verify confirmation alert
  - [ ] 12.13 Test reviews display - verify correct formatting

- [ ] 13.0 Verify profile implementation
  - [ ] 13.1 Build project and ensure zero compilation errors
  - [ ] 13.2 Verify my profile displays correctly
  - [ ] 13.3 Verify edit profile saves changes
  - [ ] 13.4 Verify avatar upload works with compression
  - [ ] 13.5 Verify invite codes generate and display
  - [ ] 13.6 Verify public profile displays correctly
  - [ ] 13.7 ⭐ Verify phone masking and reveal works
  - [ ] 13.8 ⭐ Verify phone visibility disclosure shows
  - [ ] 13.9 Verify reviews display correctly
  - [ ] 13.10 Verify caching improves navigation speed
  - [ ] 13.11 Code review: verify no force unwrapping
  - [ ] 13.12 Code review: verify proper async/await error handling
  - [ ] 13.13 Commit changes with message: "feat: implement user profile with privacy controls"
  - [ ] 13.14 Push feature branch to remote repository

### 🔒 CHECKPOINT: QA-PROFILE-FINAL
> Run: `./QA/Scripts/checkpoint.sh profile-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_PROFILE_001, FLOW_PROFILE_002, FLOW_PROFILE_003
> All profile tests must pass before starting Ride Requests
