# NaarsCars File Structure - Main App Files (171 files)

This document shows the complete file structure of the 171 main app Swift files that should be in the main NaarsCars target (excluding Tests/UITests/Scripts).

## Complete Directory Tree

```
NaarsCars/
│
├── Total: 171 main app Swift files
│
├── App/ (7 files)
│   ├── AppDelegate.swift
│   ├── AppLaunchManager.swift
│   ├── AppState.swift
│   ├── ContentView.swift
│   ├── MainTabView.swift
│   ├── NaarsCarsApp.swift
│   └── NavigationCoordinator.swift
│
├── Core/ (58 files)
│   ├── Extensions/ (5 files)
│   │   ├── Date+Extensions.swift
│   │   ├── Date+Localization.swift
│   │   ├── Number+Localization.swift
│   │   ├── String+Localization.swift
│   │   └── View+Extensions.swift
│   │
│   ├── Models/ (17 files)
│   │   ├── AppNotification.swift
│   │   ├── Conversation.swift
│   │   ├── Favor.swift
│   │   ├── InviteCode.swift
│   │   ├── LeaderboardEntry.swift
│   │   ├── MapModels.swift
│   │   ├── Message.swift
│   │   ├── Profile.swift
│   │   ├── RequestFilter.swift
│   │   ├── RequestItem.swift
│   │   ├── RequestQA.swift
│   │   ├── Review.swift
│   │   ├── Ride.swift
│   │   ├── TownHallComment.swift
│   │   ├── TownHallPost.swift
│   │   └── TownHallVote.swift
│   │
│   ├── Services/ (23 files)
│   │   ├── AdminService.swift
│   │   ├── AuthService+AppleSignIn.swift
│   │   ├── AuthService.swift
│   │   ├── BiometricService.swift
│   │   ├── ClaimService.swift
│   │   ├── ConversationService.swift
│   │   ├── EmailService.swift
│   │   ├── FavorService.swift
│   │   ├── InviteService.swift
│   │   ├── LeaderboardService.swift
│   │   ├── LocationService.swift
│   │   ├── MapService.swift
│   │   ├── MessageService.swift
│   │   ├── NotificationService.swift
│   │   ├── ProfileService.swift
│   │   ├── PushNotificationService.swift
│   │   ├── RealtimeManager.swift
│   │   ├── RideService.swift
│   │   ├── SupabaseService.swift
│   │   ├── TownHallCommentService.swift
│   │   ├── TownHallService.swift
│   │   └── TownHallVoteService.swift
│   │
│   └── Utilities/ (13 files)
│       ├── AnyCodable.swift
│       ├── AppError.swift
│       ├── BiometricPreferences.swift
│       ├── CacheManager.swift
│       ├── Constants.swift
│       ├── DeepLinkParser.swift
│       ├── DeviceIdentifier.swift
│       ├── ImageCompressor.swift
│       ├── InviteCodeGenerator.swift
│       ├── LocalizationManager.swift
│       ├── Logger.swift
│       ├── PostTitleExtractor.swift
│       ├── RateLimiter.swift
│       ├── Secrets.swift
│       └── Validators.swift
│
├── Features/ (76 files)
│   ├── Admin/ViewModels/ (4 files)
│   │   ├── AdminPanelViewModel.swift
│   │   ├── BroadcastViewModel.swift
│   │   ├── PendingUsersViewModel.swift
│   │   └── UserManagementViewModel.swift
│   │
│   ├── Admin/Views/ (6 files)
│   │   ├── AdminInviteView.swift
│   │   ├── AdminPanelView.swift
│   │   ├── BroadcastView.swift
│   │   ├── PendingUserDetailView.swift
│   │   ├── PendingUsersView.swift
│   │   └── UserManagementView.swift
│   │
│   ├── Authentication/ViewModels/ (4 files)
│   │   ├── AppleSignInViewModel.swift
│   │   ├── LoginViewModel.swift
│   │   ├── PasswordResetViewModel.swift
│   │   └── SignupViewModel.swift
│   │
│   ├── Authentication/Views/ (9 files)
│   │   ├── AppLockView.swift
│   │   ├── AppleSignInButton.swift
│   │   ├── AppleSignInLinkView.swift
│   │   ├── LoginView.swift
│   │   ├── PasswordResetView.swift
│   │   ├── PendingApprovalView.swift
│   │   ├── SignupDetailsView.swift
│   │   ├── SignupInviteCodeView.swift
│   │   └── SignupMethodChoiceView.swift
│   │
│   ├── Claiming/ViewModels/ (1 file)
│   │   └── ClaimViewModel.swift
│   │
│   ├── Claiming/Views/ (5 files)
│   │   ├── ClaimSheet.swift
│   │   ├── CompleteSheet.swift
│   │   ├── PhoneRequiredSheet.swift
│   │   ├── PushPermissionPromptView.swift
│   │   └── UnclaimSheet.swift
│   │
│   ├── Community/Views/ (1 file)
│   │   └── CommunityTabView.swift
│   │
│   ├── Favors/ViewModels/ (3 files)
│   │   ├── CreateFavorViewModel.swift
│   │   ├── FavorDetailViewModel.swift
│   │   └── FavorsDashboardViewModel.swift
│   │
│   ├── Favors/Views/ (4 files)
│   │   ├── CreateFavorView.swift
│   │   ├── EditFavorView.swift
│   │   ├── FavorDetailView.swift
│   │   └── FavorsDashboardView.swift
│   │
│   ├── Leaderboards/ViewModels/ (1 file)
│   │   └── LeaderboardViewModel.swift
│   │
│   ├── Leaderboards/Views/ (2 files)
│   │   ├── LeaderboardRow.swift
│   │   └── LeaderboardView.swift
│   │
│   ├── Messaging/ViewModels/ (2 files)
│   │   ├── ConversationDetailViewModel.swift
│   │   └── ConversationsListViewModel.swift
│   │
│   ├── Messaging/Views/ (3 files)
│   │   ├── ConversationDetailView.swift
│   │   ├── ConversationsListView.swift
│   │   └── MessagesListView.swift
│   │
│   ├── Notifications/ViewModels/ (1 file)
│   │   └── NotificationsListViewModel.swift
│   │
│   ├── Notifications/Views/ (2 files)
│   │   ├── NotificationRow.swift
│   │   └── NotificationsListView.swift
│   │
│   ├── Profile/ViewModels/ (3 files)
│   │   ├── EditProfileViewModel.swift
│   │   ├── MyProfileViewModel.swift
│   │   └── PublicProfileViewModel.swift
│   │
│   ├── Profile/Views/ (7 files)
│   │   ├── EditProfileView.swift
│   │   ├── InvitationWorkflowView.swift
│   │   ├── LanguageSettingsView.swift
│   │   ├── MyProfileView.swift
│   │   ├── ProfileView.swift
│   │   ├── PublicProfileView.swift
│   │   └── SettingsView.swift
│   │
│   ├── Requests/ViewModels/ (1 file)
│   │   └── RequestsDashboardViewModel.swift
│   │
│   ├── Requests/Views/ (1 file)
│   │   └── RequestsDashboardView.swift
│   │
│   ├── Rides/ViewModels/ (3 files)
│   │   ├── CreateRideViewModel.swift
│   │   ├── RideDetailViewModel.swift
│   │   └── RidesDashboardViewModel.swift
│   │
│   ├── Rides/Views/ (6 files)
│   │   ├── CreateRideView.swift
│   │   ├── DashboardView.swift
│   │   ├── EditRideView.swift
│   │   ├── RequestMapView.swift
│   │   ├── RideDetailView.swift
│   │   └── RidesDashboardView.swift
│   │
│   ├── TownHall/ViewModels/ (2 files)
│   │   ├── CreatePostViewModel.swift
│   │   └── TownHallFeedViewModel.swift
│   │
│   └── TownHall/Views/ (5 files)
│       ├── CreatePostView.swift
│       ├── PostCommentsView.swift
│       ├── TownHallFeedView.swift
│       ├── TownHallPostCard.swift
│       └── TownHallPostRow.swift
│
└── UI/ (30 files)
    ├── Components/Buttons/ (3 files)
    │   ├── ClaimButton.swift
    │   ├── PrimaryButton.swift
    │   └── SecondaryButton.swift
    │
    ├── Components/Cards/ (4 files)
    │   ├── FavorCard.swift
    │   ├── InviteCodeCard.swift
    │   ├── ReviewCard.swift
    │   └── RideCard.swift
    │
    ├── Components/Common/ (5 files)
    │   ├── AvatarView.swift
    │   ├── NotificationBadge.swift
    │   ├── RequestQAView.swift
    │   ├── StarRatingView.swift
    │   └── UserAvatarLink.swift
    │
    ├── Components/Feedback/ (9 files)
    │   ├── EmptyStateView.swift
    │   ├── ErrorView.swift
    │   ├── LoadingView.swift
    │   ├── SkeletonConversationRow.swift
    │   ├── SkeletonFavorCard.swift
    │   ├── SkeletonLeaderboardRow.swift
    │   ├── SkeletonMessageRow.swift
    │   ├── SkeletonRideCard.swift
    │   └── SkeletonView.swift
    │
    ├── Components/Inputs/ (1 file)
    │   └── LocationAutocompleteField.swift
    │
    ├── Components/Map/ (3 files)
    │   ├── FilterBar.swift
    │   ├── RequestPin.swift
    │   └── RequestPreviewCard.swift
    │
    ├── Components/Messaging/ (3 files)
    │   ├── MessageBubble.swift
    │   ├── MessageInputBar.swift
    │   └── UserSearchView.swift
    │
    └── Styles/ (2 files)
        ├── ColorTheme.swift
        └── Typography.swift
```

## Breakdown by Top-Level Directory

| Directory | File Count | Description |
|-----------|------------|-------------|
| **App/** | 7 | Application entry point, app lifecycle, navigation, and main views |
| **Core/** | 58 | Core functionality: models, services, utilities, and extensions |
| **Features/** | 76 | Feature modules organized by domain (Admin, Auth, Rides, Favors, etc.) |
| **UI/** | 30 | Reusable UI components, styles, and shared visual elements |
| **Total** | **171** | All main app Swift files (excluding Tests/UITests/Scripts) |

## Breakdown by Feature (Features/ directory)

| Feature | ViewModels | Views | Total |
|---------|-----------|-------|-------|
| Admin | 4 | 6 | 10 |
| Authentication | 4 | 9 | 13 |
| Claiming | 1 | 5 | 6 |
| Community | 0 | 1 | 1 |
| Favors | 3 | 4 | 7 |
| Leaderboards | 1 | 2 | 3 |
| Messaging | 2 | 3 | 5 |
| Notifications | 1 | 2 | 3 |
| Profile | 3 | 7 | 10 |
| Requests | 1 | 1 | 2 |
| Rides | 3 | 6 | 9 |
| TownHall | 2 | 5 | 7 |
| **Subtotal** | **25** | **51** | **76** |

## Notes

1. **fileSystemSynchronizedGroups**: These 171 files are automatically included in the main NaarsCars target via `fileSystemSynchronizedGroups`, which discovers all `.swift` files in the `NaarsCars/` directory.

2. **Exclusions**: This structure excludes:
   - Test files (NaarsCarsTests/)
   - UI Test files (NaarsCarsUITests/)
   - Script files (e.g., `obfuscate.swift`)

3. **Current Issue**: The main target currently has **219 files** instead of **171**, meaning **48 extra files** (test files, UI test files, script files, or duplicates) need to be removed or moved to the correct targets.

4. **Organization**: The project follows a clean architecture with:
   - **Core/** for shared infrastructure
   - **Features/** for domain-specific functionality (MVVM pattern)
   - **UI/** for reusable components
   - **App/** for application-level code
