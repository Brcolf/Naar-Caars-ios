# Git Tracked Files

This document lists all files currently tracked in git (493 files total).

**Note:** Files in `.gitignore` (like `Secrets.swift`, `.DS_Store`, `build-output.log`, etc.) are intentionally excluded from version control.

## Summary

- **Total files tracked:** 493
- **Total files in project:** ~478 (excluding gitignored files)
- **Difference:** ~15 files are tracked but may be documentation/meta files

## Files Tracked in Git

Below is the complete list of files tracked in git, organized by directory structure:

### Root Level Documentation
- `.gitignore`
- `ADD-MISSING-FILES-TO-XCODE.md`
- `ADD_TO_XCODE.md`
- `AUTH-WARNING-FIX.md`
- `BUILD-COMPLETE.md`
- `BUILD-CONTEXT.md`
- `BUILD-ISSUES-FIXED.md`
- `BUILD-ISSUES-SUMMARY.md`
- `BUILD-PLAN.md`
- `BUILD-PROGRESS.md`
- `BUILD-WARNINGS-FIXED.md`
- `CHECK_TEST_RESULTS.md`
- `CLEAR-XCODE-CACHE.sh`
- `COMPILATION-ERRORS-SUMMARY.md`
- `CONTEXT-SYSTEM-GUIDE.md`
- `DATABASE_MIGRATION_INSTRUCTIONS.md`
- `DEPENDENCY-MAP.md`
- `FAVOR-REQUESTS-IMPLEMENTATION-SUMMARY.md`
- `FILE-STRUCTURE-TREE.md`
- `FIX-BUNDLE-ID-ERROR.md`
- `FIX-INFOPLIST-CONFLICT.md`
- `FIX-LOCALIZATION-KEYS.md`
- `FIX-MISSING-FILES-COMPILATION.md`
- `FIX-MISSING-FILES.md`
- `FIX-TOWNHALL-COMPILATION.md`
- `FLOW-REVIEW-FINDINGS.md`
- `GOOGLE-PLACES-SETUP.md`
- `INFOPLIST-FIX-COMPLETE.md`
- `INVITE_SYSTEM_ENHANCEMENTS.md`
- `INVITE_SYSTEM_IMPLEMENTATION.md`
- `INVITE_SYSTEM_IMPLEMENTATION_SUMMARY.md`
- `LOCALIZATION-SETUP.md`
- `MANUAL-XCODE-FIX.md`
- `MAPKIT-MIGRATION.md`
- `MESSAGING_WORKFLOWS.md`
- `NEXT-STEPS.md`
- `package-lock.json`
- `PHASE-0-2-100-PERCENT-COMPLETION-SUMMARY.md`
- `PHASE-0-2-COMPREHENSIVE-REVIEW.md`
- `PHASE-0-2-NEXT-STEPS-COMPLETE.md`
- `PHASE-0-2-TASK-COMPLETION-REVIEW.md`
- `PHASE-0-2-TASK-COMPLETION-UPDATE-SUMMARY.md`
- `PHASE-2-COMMUNICATION-IMPLEMENTATION-STATUS.md`
- `PHASE-2-COMPLETE-SUMMARY.md`
- `PHASE-2-FINAL-STATUS.md`
- `PHASE5-COMPLETE.md`
- `PHASE5-IMPLEMENTATION-PLAN.md`
- `PHASE5-IMPLEMENTATION-SUMMARY.md`
- `PRIVACY-DISCLOSURES.md`
- `PROFILE-IMPLEMENTATION-SUMMARY.md`
- `PROFILE_PAGE_UPDATES_COMPLETE.md`
- `PROFILE_UPDATES_SUMMARY.md`
- `PROGRESS-TRACKER.md`
- `PROJECT-REVIEW-REPORT.md`
- `README.md`
- `REQUEST-CLAIMING-IMPLEMENTATION-SUMMARY.md`
- `RESOLVE-INFOPLIST-ERROR.md`
- `RIDE-REQUESTS-IMPLEMENTATION-SUMMARY.md`
- `SECURITY.md`
- `SETUP-GUIDE-TASK-1.0.md`
- `STRING-CATALOG-SETUP.md`
- `TASK-INSTRUCTIONS-VERIFICATION.md`
- `TASK-LIST-UPDATE-GUIDE.md`
- `TESTFLIGHT-PREPARATION.md`
- `TESTING_RLS_FIX.md`
- `update_localizations.py`
- `VERIFICATION-SUMMARY.md`
- `VERIFY-FILES-ADDED-TO-XCODE.md`
- `XCODE-FILE-COUNT-ANALYSIS.md`
- `XCODE-FILE-SYNC-ANALYSIS.md`
- `XCODE-FILE-SYNC-ISSUE.md`
- `XCODE-FIX-STEPS.md`
- `XCODE-INTEGRATION-GUIDE.md`
- `XCODE-LOCALIZATION-SETUP.md`
- `XCODE-PROJECT-REVIEW-AND-FIX.md`
- `XCODE_FILE_ADDITION_GUIDE.md`

### NaarsCars/ - Main Application Code

#### App/
- `NaarsCars/App/AppDelegate.swift`
- `NaarsCars/App/AppLaunchManager.swift`
- `NaarsCars/App/AppState.swift`
- `NaarsCars/App/ContentView.swift`
- `NaarsCars/App/MainTabView.swift`
- `NaarsCars/App/NaarsCarsApp.swift`
- `NaarsCars/App/NavigationCoordinator.swift`

#### Core/Extensions/ (7 files)
- `Date+Extensions.swift`
- `Date+Localization.swift`
- `MKPolyline+Extensions.swift`
- `Number+Localization.swift`
- `String+Localization.swift`
- `View+Extensions.swift`

#### Core/Models/ (17 files)
- `AppNotification.swift`
- `Conversation.swift`
- `Favor.swift`
- `InviteCode.swift`
- `LeaderboardEntry.swift`
- `MapModels.swift`
- `Message.swift`
- `MessageReaction.swift` ⭐ (new)
- `Profile.swift`
- `RequestFilter.swift`
- `RequestItem.swift`
- `RequestQA.swift`
- `Review.swift`
- `Ride.swift`
- `TownHallComment.swift`
- `TownHallPost.swift`
- `TownHallVote.swift`

#### Core/Services/ (38 files)
- `AdminService.swift`
- `AppLogger.swift` ⭐ (new)
- `AuthService.swift`
- `AuthService+AppleSignIn.swift`
- `BadgeCountManager.swift` ⭐ (new)
- `BiometricService.swift`
- `ClaimService.swift`
- `EmailService.swift`
- `FavorService.swift`
- `InviteService.swift`
- `JSONDecoderFactory.swift` ⭐ (new)
- `LeaderboardService.swift`
- `LocationService.swift`
- `MapService.swift`
- `MessageService.swift`
- `MessagingDebugView.swift` ⭐ (new)
- `MessagingLogger.swift` ⭐ (new)
- `NetworkRetryHelper.swift` ⭐ (new)
- `NotificationService.swift`
- `PaginatedResponse.swift` ⭐ (new)
- `PerformanceImprovementsTests.swift` ⭐ (new)
- `PerformanceMonitor.swift` ⭐ (new)
- `ProfileService.swift`
- `PushNotificationService.swift`
- `RealtimeManager.swift`
- `RequestDeduplicator.swift` ⭐ (new)
- `ReviewService.swift` ⭐ (new)
- `ReviewService+Prompt.swift` ⭐ (new)
- `RideService.swift`
- `SupabaseService.swift`
- `TownHallCommentService.swift`
- `TownHallService.swift`
- `TownHallVoteService.swift`

#### Core/Utilities/ (16 files)
- `AnyCodable.swift`
- `AppError.swift`
- `BiometricPreferences.swift`
- `CacheManager.swift`
- `Constants.swift`
- `DeepLinkParser.swift`
- `DeviceIdentifier.swift`
- `ImageCompressor.swift`
- `InviteCodeGenerator.swift`
- `LocalizationManager.swift`
- `Logger.swift`
- `PostTitleExtractor.swift`
- `RateLimiter.swift`
- `RideCostEstimator.swift` ⭐ (new)
- `Validators.swift`
- Note: `Secrets.swift` is NOT tracked (gitignored)

#### Features/ - Feature Modules

##### Admin/ (10 files)
- ViewModels: `AdminPanelViewModel.swift`, `BroadcastViewModel.swift`, `PendingUsersViewModel.swift`, `UserManagementViewModel.swift`
- Views: `AdminInviteView.swift`, `AdminPanelView.swift`, `BroadcastView.swift`, `PendingUserDetailView.swift`, `PendingUsersView.swift`, `UserManagementView.swift`

##### Authentication/ (11 files)
- ViewModels: `AppleSignInViewModel.swift`, `LoginViewModel.swift`, `PasswordResetViewModel.swift`, `SignupViewModel.swift`
- Views: `AppLockView.swift`, `AppleSignInButton.swift`, `AppleSignInLinkView.swift`, `LoginView.swift`, `PasswordResetView.swift`, `PendingApprovalView.swift`, `SignupDetailsView.swift`, `SignupInviteCodeView.swift`, `SignupMethodChoiceView.swift`

##### Claiming/ (6 files)
- ViewModels: `ClaimViewModel.swift`
- Views: `ClaimSheet.swift`, `CompleteSheet.swift`, `PhoneRequiredSheet.swift`, `PushPermissionPromptView.swift`, `UnclaimSheet.swift`

##### Community/ (1 file)
- Views: `CommunityTabView.swift`

##### Favors/ (7 files)
- ViewModels: `CreateFavorViewModel.swift`, `FavorDetailViewModel.swift`, `FavorsDashboardViewModel.swift`
- Views: `CreateFavorView.swift`, `EditFavorView.swift`, `FavorDetailView.swift`, `FavorsDashboardView.swift`

##### Leaderboards/ (3 files)
- ViewModels: `LeaderboardViewModel.swift`
- Views: `LeaderboardRow.swift`, `LeaderboardView.swift`

##### Messaging/ (7 files)
- ViewModels: `ConversationDetailViewModel.swift`, `ConversationsListViewModel.swift`
- Views: `ConversationDetailView.swift`, `ConversationsListView.swift`, `MessageDetailsPopup.swift` ⭐ (new), `MessagesListView.swift`

##### Notifications/ (3 files)
- ViewModels: `NotificationsListViewModel.swift`
- Views: `NotificationRow.swift`, `NotificationsListView.swift`

##### Profile/ (11 files)
- ViewModels: `EditProfileViewModel.swift`, `MyProfileViewModel.swift`, `PublicProfileViewModel.swift`
- Views: `EditProfileView.swift`, `InvitationWorkflowView.swift`, `LanguageSettingsView.swift`, `MyProfileView.swift`, `ProfileView.swift`, `PublicProfileView.swift`, `SettingsView.swift`

##### Requests/ (4 files)
- ViewModels: `PastRequestsViewModel.swift` ⭐ (new), `RequestsDashboardViewModel.swift`
- Views: `PastRequestsView.swift` ⭐ (new), `RequestsDashboardView.swift`

##### Reviews/ (4 files) ⭐ (new feature)
- ViewModels: `LeaveReviewViewModel.swift`, `ReviewPromptManager.swift`
- Views: `LeaveReviewView.swift`, `ReviewPromptSheet.swift`

##### Rides/ (7 files)
- ViewModels: `CreateRideViewModel.swift`, `RideDetailViewModel.swift`, `RidesDashboardViewModel.swift`
- Views: `CreateRideView.swift`, `DashboardView.swift`, `EditRideView.swift`, `RequestMapView.swift`, `RideDetailView.swift`, `RidesDashboardView.swift`

##### TownHall/ (5 files)
- ViewModels: `CreatePostViewModel.swift`, `TownHallFeedViewModel.swift`
- Views: `CreatePostView.swift`, `PostCommentsView.swift`, `TownHallFeedView.swift`, `TownHallPostCard.swift`, `TownHallPostRow.swift`

#### UI/Components/ - Reusable UI Components

##### Buttons/ (3 files)
- `ClaimButton.swift`, `PrimaryButton.swift`, `SecondaryButton.swift`

##### Cards/ (4 files)
- `FavorCard.swift`, `InviteCodeCard.swift`, `ReviewCard.swift`, `RideCard.swift`

##### Common/ (7 files)
- `AvatarView.swift`, `NotificationBadge.swift`, `RequestQAView.swift`, `StarRatingInput.swift` ⭐ (new), `StarRatingView.swift`, `TimePickerView.swift` ⭐ (new), `UserAvatarLink.swift`

##### Feedback/ (9 files)
- `EmptyStateView.swift`, `ErrorView.swift`, `LoadingView.swift`, `SkeletonConversationRow.swift`, `SkeletonFavorCard.swift`, `SkeletonLeaderboardRow.swift`, `SkeletonMessageRow.swift`, `SkeletonRideCard.swift`, `SkeletonView.swift`

##### Inputs/ (1 file)
- `LocationAutocompleteField.swift`

##### Map/ (4 files)
- `FilterBar.swift`, `RequestPin.swift`, `RequestPreviewCard.swift`, `RouteMapView.swift` ⭐ (new)

##### Messaging/ (5 files)
- `ConversationDisplayNameCache.swift`, `MessageBubble.swift`, `MessageInputBar.swift`, `ReactionPicker.swift` ⭐ (new), `UserSearchView.swift`

#### UI/Styles/ (2 files)
- `ColorTheme.swift`, `Typography.swift`

#### NaarsCars/ - App Bundle Resources
- `NaarsCars/Info.plist`
- `NaarsCars/NaarsCars/Assets.xcassets/` (3 JSON files)
- `NaarsCars/NaarsCars/NaarsCars.entitlements`
- `NaarsCars/NaarsCars/NaarsCarsDebug.entitlements` ⭐ (new)

#### Resources/
- `NaarsCars/Resources/Localizable.xcstrings`

#### Scripts/ (7 files)
- `add-all-files-to-xcode.py`, `add-all-missing-files-to-xcode.py`, `add-models-to-xcode.py`, `add-navigation-files.py`, `add-phase2-files-to-xcode.py`, `add-profile-files-to-xcode.py`, `obfuscate.swift`

#### Xcode Project Files
- `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`
- `NaarsCars/NaarsCars.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `NaarsCars/NaarsCars.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` ⭐ (new)
- `NaarsCars/NaarsCars.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `NaarsCars/NaarsCars.xcodeproj/xcshareddata/xcschemes/NaarsCars.xcscheme`

#### NaarsCarsTests/ - Unit Tests (37 files)
- Core/Models tests (6 files)
- Core/Services tests (9 files)
- Core/Utilities tests (5 files)
- Features tests (16 files)
- `NaarsCarsTests.swift`

#### NaarsCarsUITests/ - UI Tests (2 files)
- `NaarsCarsUITests.swift`, `NaarsCarsUITestsLaunchTests.swift`

### PRDs/ - Product Requirements Documents (20 files)
- `PRD-INDEX.md` + 19 PRD markdown files

### Tasks/ - Task Lists (22 files)
- `TASK-LISTS-SUMMARY.md` + 18 task markdown files + 4 summary files

### QA/ - Quality Assurance (6 files)
- Scripts: `checkpoint.sh`, `generate-report.sh`
- Templates: `FLOW-CATALOG-TEMPLATE.md`
- Documentation: `CHECKPOINT-GUIDE.md`, `FLOW-CATALOG.md`, `QA-INTEGRATION-SUMMARY.md`, `QA-RUNNER-INSTRUCTIONS.md`

### database/ - Database Migrations (55 files)
- SQL migration files numbered 010-064
- Documentation: `APPLY_RLS_FIX.md`, `FINAL_RLS_FIX.md`, `README_RLS_FIX.md`

### supabase/ - Supabase Functions (18 files)
- `supabase/functions/send-message-push/`:
  - Code: `index.ts`, `deno.json`
  - Scripts: `create_webhook.sh`, `test_push.sh`, `QUICK_DEPLOY.sh`
  - Documentation: 14 markdown files

## Files NOT in Git (Intentionally Excluded)

These files exist locally but are correctly excluded via `.gitignore`:

1. **`NaarsCars/Core/Utilities/Secrets.swift`** - Contains API keys and sensitive configuration
2. **`NaarsCars/build-output.log`** - Build artifact/log file
3. **`.DS_Store`** files - macOS system files
4. **`supabase/.temp/`** directory - Temporary Supabase CLI files
5. **`xcuserdata/`** directories - Xcode user-specific settings

## Recent Changes (Latest Commit)

The latest commit (`16e9f82`) added/modified 296 files, including:

### New Features:
- Review system (4 new files)
- Message reactions (2 new files)
- Performance monitoring (3 new files)
- Badge count manager
- Route map view
- Time picker
- Star rating input

### Removed:
- `ConversationService.swift` (consolidated into MessageService)
- `Resources/Info.plist` (moved to NaarsCars directory)

### Database Migrations:
- 059-064 (participants, reviews, reactions, RLS fixes)

---

**Last Updated:** Generated from git repository state
**Branch:** `feature/messaging`
**Commit:** `16e9f82`

