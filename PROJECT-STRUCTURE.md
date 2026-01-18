# NaarsCars Project Structure

## Full Project Directory Structure

```
.
├── Root Documentation Files (35+ .md files)
├── NaarsCars/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── AppLaunchManager.swift
│   │   ├── AppState.swift
│   │   ├── ContentView.swift
│   │   ├── MainTabView.swift
│   │   ├── NaarsCarsApp.swift
│   │   └── NavigationCoordinator.swift
│   │
│   ├── Core/
│   │   ├── Extensions/
│   │   │   ├── Date+Extensions.swift
│   │   │   ├── Date+Localization.swift
│   │   │   ├── MKPolyline+Extensions.swift
│   │   │   ├── Number+Localization.swift
│   │   │   ├── String+Localization.swift
│   │   │   └── View+Extensions.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── AppNotification.swift
│   │   │   ├── Conversation.swift
│   │   │   ├── Favor.swift
│   │   │   ├── InviteCode.swift
│   │   │   ├── LeaderboardEntry.swift
│   │   │   ├── MapModels.swift
│   │   │   ├── Message.swift
│   │   │   ├── MessageReaction.swift
│   │   │   ├── Profile.swift
│   │   │   ├── RequestFilter.swift
│   │   │   ├── RequestItem.swift
│   │   │   ├── RequestQA.swift
│   │   │   ├── Review.swift
│   │   │   ├── Ride.swift
│   │   │   ├── TownHallComment.swift
│   │   │   ├── TownHallPost.swift
│   │   │   └── TownHallVote.swift
│   │   │
│   │   ├── Services/
│   │   │   ├── AdminService.swift
│   │   │   ├── AppLogger.swift
│   │   │   ├── AuthService.swift
│   │   │   ├── AuthService+AppleSignIn.swift
│   │   │   ├── BadgeCountManager.swift
│   │   │   ├── BiometricService.swift
│   │   │   ├── ClaimService.swift
│   │   │   ├── EmailService.swift
│   │   │   ├── FavorService.swift
│   │   │   ├── InviteService.swift
│   │   │   ├── JSONDecoderFactory.swift
│   │   │   ├── LeaderboardService.swift
│   │   │   ├── LocationService.swift
│   │   │   ├── MapService.swift
│   │   │   ├── MessageService.swift
│   │   │   ├── MessagingDebugView.swift
│   │   │   ├── MessagingLogger.swift
│   │   │   ├── NetworkRetryHelper.swift
│   │   │   ├── NotificationService.swift
│   │   │   ├── PaginatedResponse.swift
│   │   │   ├── PerformanceImprovementsTests.swift
│   │   │   ├── PerformanceMonitor.swift
│   │   │   ├── ProfileService.swift
│   │   │   ├── PushNotificationService.swift
│   │   │   ├── RealtimeManager.swift
│   │   │   ├── RequestDeduplicator.swift
│   │   │   ├── ReviewService.swift
│   │   │   ├── ReviewService+Prompt.swift
│   │   │   ├── RideService.swift
│   │   │   ├── SupabaseService.swift
│   │   │   ├── TownHallCommentService.swift
│   │   │   ├── TownHallService.swift
│   │   │   └── TownHallVoteService.swift
│   │   │
│   │   └── Utilities/
│   │       ├── AnyCodable.swift
│   │       ├── AppError.swift
│   │       ├── BiometricPreferences.swift
│   │       ├── CacheManager.swift
│   │       ├── Constants.swift
│   │       ├── DeepLinkParser.swift
│   │       ├── DeviceIdentifier.swift
│   │       ├── ImageCompressor.swift
│   │       ├── InviteCodeGenerator.swift
│   │       ├── LocalizationManager.swift
│   │       ├── Logger.swift
│   │       ├── PostTitleExtractor.swift
│   │       ├── RateLimiter.swift
│   │       ├── RideCostEstimator.swift
│   │       ├── Secrets.swift (not in git)
│   │       └── Validators.swift
│   │
│   ├── Features/
│   │   ├── Admin/
│   │   │   ├── ViewModels/
│   │   │   │   ├── AdminPanelViewModel.swift
│   │   │   │   ├── BroadcastViewModel.swift
│   │   │   │   ├── PendingUsersViewModel.swift
│   │   │   │   └── UserManagementViewModel.swift
│   │   │   └── Views/
│   │   │       ├── AdminInviteView.swift
│   │   │       ├── AdminPanelView.swift
│   │   │       ├── BroadcastView.swift
│   │   │       ├── PendingUserDetailView.swift
│   │   │       ├── PendingUsersView.swift
│   │   │       └── UserManagementView.swift
│   │   │
│   │   ├── Authentication/
│   │   │   ├── ViewModels/
│   │   │   │   ├── AppleSignInViewModel.swift
│   │   │   │   ├── LoginViewModel.swift
│   │   │   │   ├── PasswordResetViewModel.swift
│   │   │   │   └── SignupViewModel.swift
│   │   │   └── Views/
│   │   │       ├── AppLockView.swift
│   │   │       ├── AppleSignInButton.swift
│   │   │       ├── AppleSignInLinkView.swift
│   │   │       ├── LoginView.swift
│   │   │       ├── PasswordResetView.swift
│   │   │       ├── PendingApprovalView.swift
│   │   │       ├── SignupDetailsView.swift
│   │   │       ├── SignupInviteCodeView.swift
│   │   │       └── SignupMethodChoiceView.swift
│   │   │
│   │   ├── Claiming/
│   │   │   ├── ViewModels/
│   │   │   │   └── ClaimViewModel.swift
│   │   │   └── Views/
│   │   │       ├── ClaimSheet.swift
│   │   │       ├── CompleteSheet.swift
│   │   │       ├── PhoneRequiredSheet.swift
│   │   │       ├── PushPermissionPromptView.swift
│   │   │       └── UnclaimSheet.swift
│   │   │
│   │   ├── Community/
│   │   │   └── Views/
│   │   │       └── CommunityTabView.swift
│   │   │
│   │   ├── Favors/
│   │   │   ├── ViewModels/
│   │   │   │   ├── CreateFavorViewModel.swift
│   │   │   │   ├── FavorDetailViewModel.swift
│   │   │   │   └── FavorsDashboardViewModel.swift
│   │   │   └── Views/
│   │   │       ├── CreateFavorView.swift
│   │   │       ├── EditFavorView.swift
│   │   │       ├── FavorDetailView.swift
│   │   │       └── FavorsDashboardView.swift
│   │   │
│   │   ├── Leaderboards/
│   │   │   ├── ViewModels/
│   │   │   │   └── LeaderboardViewModel.swift
│   │   │   └── Views/
│   │   │       ├── LeaderboardRow.swift
│   │   │       └── LeaderboardView.swift
│   │   │
│   │   ├── Messaging/
│   │   │   ├── ViewModels/
│   │   │   │   ├── ConversationDetailViewModel.swift
│   │   │   │   └── ConversationsListViewModel.swift
│   │   │   └── Views/
│   │   │       ├── ConversationDetailView.swift
│   │   │       ├── ConversationsListView.swift
│   │   │       ├── MessageDetailsPopup.swift
│   │   │       └── MessagesListView.swift
│   │   │
│   │   ├── Notifications/
│   │   │   ├── ViewModels/
│   │   │   │   └── NotificationsListViewModel.swift
│   │   │   └── Views/
│   │   │       ├── NotificationRow.swift
│   │   │       └── NotificationsListView.swift
│   │   │
│   │   ├── Profile/
│   │   │   ├── ViewModels/
│   │   │   │   ├── EditProfileViewModel.swift
│   │   │   │   ├── MyProfileViewModel.swift
│   │   │   │   └── PublicProfileViewModel.swift
│   │   │   └── Views/
│   │   │       ├── EditProfileView.swift
│   │   │       ├── InvitationWorkflowView.swift
│   │   │       ├── LanguageSettingsView.swift
│   │   │       ├── MyProfileView.swift
│   │   │       ├── ProfileView.swift
│   │   │       ├── PublicProfileView.swift
│   │   │       └── SettingsView.swift
│   │   │
│   │   ├── Requests/
│   │   │   ├── ViewModels/
│   │   │   │   ├── PastRequestsViewModel.swift
│   │   │   │   └── RequestsDashboardViewModel.swift
│   │   │   └── Views/
│   │   │       ├── PastRequestsView.swift
│   │   │       └── RequestsDashboardView.swift
│   │   │
│   │   ├── Reviews/
│   │   │   ├── ViewModels/
│   │   │   │   ├── LeaveReviewViewModel.swift
│   │   │   │   └── ReviewPromptManager.swift
│   │   │   └── Views/
│   │   │       ├── LeaveReviewView.swift
│   │   │       └── ReviewPromptSheet.swift
│   │   │
│   │   ├── Rides/
│   │   │   ├── ViewModels/
│   │   │   │   ├── CreateRideViewModel.swift
│   │   │   │   ├── RideDetailViewModel.swift
│   │   │   │   └── RidesDashboardViewModel.swift
│   │   │   └── Views/
│   │   │       ├── CreateRideView.swift
│   │   │       ├── DashboardView.swift
│   │   │       ├── EditRideView.swift
│   │   │       ├── RequestMapView.swift
│   │   │       ├── RideDetailView.swift
│   │   │       └── RidesDashboardView.swift
│   │   │
│   │   └── TownHall/
│   │       ├── ViewModels/
│   │       │   ├── CreatePostViewModel.swift
│   │       │   └── TownHallFeedViewModel.swift
│   │       └── Views/
│   │           ├── CreatePostView.swift
│   │           ├── PostCommentsView.swift
│   │           ├── TownHallFeedView.swift
│   │           ├── TownHallPostCard.swift
│   │           └── TownHallPostRow.swift
│   │
│   ├── UI/
│   │   ├── Components/
│   │   │   ├── Buttons/
│   │   │   │   ├── ClaimButton.swift
│   │   │   │   ├── PrimaryButton.swift
│   │   │   │   └── SecondaryButton.swift
│   │   │   │
│   │   │   ├── Cards/
│   │   │   │   ├── FavorCard.swift
│   │   │   │   ├── InviteCodeCard.swift
│   │   │   │   ├── ReviewCard.swift
│   │   │   │   └── RideCard.swift
│   │   │   │
│   │   │   ├── Common/
│   │   │   │   ├── AvatarView.swift
│   │   │   │   ├── NotificationBadge.swift
│   │   │   │   ├── RequestQAView.swift
│   │   │   │   ├── StarRatingInput.swift
│   │   │   │   ├── StarRatingView.swift
│   │   │   │   ├── TimePickerView.swift
│   │   │   │   └── UserAvatarLink.swift
│   │   │   │
│   │   │   ├── Feedback/
│   │   │   │   ├── EmptyStateView.swift
│   │   │   │   ├── ErrorView.swift
│   │   │   │   ├── LoadingView.swift
│   │   │   │   ├── SkeletonConversationRow.swift
│   │   │   │   ├── SkeletonFavorCard.swift
│   │   │   │   ├── SkeletonLeaderboardRow.swift
│   │   │   │   ├── SkeletonMessageRow.swift
│   │   │   │   ├── SkeletonRideCard.swift
│   │   │   │   └── SkeletonView.swift
│   │   │   │
│   │   │   ├── Inputs/
│   │   │   │   └── LocationAutocompleteField.swift
│   │   │   │
│   │   │   ├── Map/
│   │   │   │   ├── FilterBar.swift
│   │   │   │   ├── RequestPin.swift
│   │   │   │   ├── RequestPreviewCard.swift
│   │   │   │   └── RouteMapView.swift
│   │   │   │
│   │   │   └── Messaging/
│   │   │       ├── ConversationDisplayNameCache.swift
│   │   │       ├── MessageBubble.swift
│   │   │       ├── MessageInputBar.swift
│   │   │       ├── ReactionPicker.swift
│   │   │       └── UserSearchView.swift
│   │   │
│   │   └── Styles/
│   │       ├── ColorTheme.swift
│   │       └── Typography.swift
│   │
│   ├── NaarsCars/
│   │   ├── Assets.xcassets/
│   │   │   ├── AccentColor.colorset/Contents.json
│   │   │   ├── AppIcon.appiconset/Contents.json
│   │   │   └── Contents.json
│   │   ├── NaarsCars.entitlements
│   │   └── NaarsCarsDebug.entitlements
│   │
│   ├── NaarsCars.xcodeproj/
│   │   ├── project.pbxproj
│   │   ├── project.xcworkspace/
│   │   │   ├── contents.xcworkspacedata
│   │   │   └── xcshareddata/
│   │   │       └── WorkspaceSettings.xcsettings
│   │   └── xcshareddata/
│   │       └── xcschemes/
│   │           └── NaarsCars.xcscheme
│   │
│   ├── NaarsCarsTests/
│   │   ├── Core/
│   │   │   ├── Models/
│   │   │   │   ├── AppNotificationTests.swift
│   │   │   │   ├── FavorTests.swift
│   │   │   │   ├── LeaderboardEntryTests.swift
│   │   │   │   ├── ProfileTests.swift
│   │   │   │   ├── RideTests.swift
│   │   │   │   └── TownHallPostTests.swift
│   │   │   ├── Services/
│   │   │   │   ├── ClaimServiceTests.swift
│   │   │   │   ├── FavorServiceTests.swift
│   │   │   │   ├── LeaderboardServiceTests.swift
│   │   │   │   ├── NotificationServiceTests.swift
│   │   │   │   ├── ProfileServiceTests.swift
│   │   │   │   ├── PushNotificationServiceTests.swift
│   │   │   │   ├── RealtimeManagerTests.swift
│   │   │   │   ├── RideServiceTests.swift
│   │   │   │   └── TownHallServiceTests.swift
│   │   │   └── Utilities/
│   │   │       ├── CacheManagerTests.swift
│   │   │       ├── DeepLinkParserTests.swift
│   │   │       ├── ImageCompressorTests.swift
│   │   │       ├── RateLimiterTests.swift
│   │   │       └── ValidatorsTests.swift
│   │   ├── Features/
│   │   │   ├── Claiming/
│   │   │   │   └── ClaimViewModelTests.swift
│   │   │   ├── Favors/
│   │   │   │   ├── CreateFavorViewModelTests.swift
│   │   │   │   └── FavorsDashboardViewModelTests.swift
│   │   │   ├── Leaderboards/
│   │   │   │   └── LeaderboardViewModelTests.swift
│   │   │   ├── Notifications/
│   │   │   │   └── NotificationsListViewModelTests.swift
│   │   │   ├── Profile/
│   │   │   │   ├── EditProfileViewModelTests.swift
│   │   │   │   ├── MyProfileViewModelTests.swift
│   │   │   │   └── PublicProfileViewModelTests.swift
│   │   │   ├── Rides/
│   │   │   │   ├── CreateRideViewModelTests.swift
│   │   │   │   ├── RideDetailViewModelTests.swift
│   │   │   │   └── RidesDashboardViewModelTests.swift
│   │   │   └── TownHall/
│   │   │       ├── CreatePostViewModelTests.swift
│   │   │       └── TownHallFeedViewModelTests.swift
│   │   └── NaarsCarsTests.swift
│   │
│   ├── NaarsCarsUITests/
│   │   ├── NaarsCarsUITests.swift
│   │   └── NaarsCarsUITestsLaunchTests.swift
│   │
│   ├── Resources/
│   │   └── Localizable.xcstrings
│   │
│   └── Scripts/
│       ├── add-all-files-to-xcode.py
│       ├── add-all-missing-files-to-xcode.py
│       ├── add-models-to-xcode.py
│       ├── add-navigation-files.py
│       ├── add-phase2-files-to-xcode.py
│       ├── add-profile-files-to-xcode.py
│       └── obfuscate.swift
│
├── PRDs/
│   └── (19 PRD markdown files)
│
├── Tasks/
│   └── (18 task markdown files)
│
├── QA/
│   ├── Scripts/
│   │   ├── checkpoint.sh
│   │   └── generate-report.sh
│   └── Templates/
│       └── FLOW-CATALOG-TEMPLATE.md
│
├── database/
│   └── (55 migration SQL files: 010-064)
│
└── supabase/
    └── functions/
        └── send-message-push/
            ├── index.ts
            ├── deno.json
            └── (14 documentation files)
```

## Files NOT Tracked in Git (but exist locally)

The following files exist in the project directory but are NOT tracked by git:

1. **Secrets/Config:**
   - `NaarsCars/Core/Utilities/Secrets.swift` - Likely gitignored (contains API keys)

2. **Build artifacts/temporary:**
   - `NaarsCars/build-output.log` - Build log file
   - `NaarsCars/.DS_Store` - macOS system file (gitignored)
   - `NaarsCars/.gitignore` - Local gitignore (gitignored)

3. **Supabase temporary files:**
   - `supabase/.temp/` directory and its contents (gitignored)

4. **Xcode user-specific files:**
   - `NaarsCars/NaarsCars.xcodeproj/project.xcworkspace/xcuserdata/` - User-specific settings (gitignored)

These are expected to be excluded via `.gitignore`.

