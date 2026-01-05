# Tasks: Foundation Architecture

Based on `prd-foundation-architecture.md`

## Affected Flows

- FLOW_FOUNDATION_001: App Launch & Session Restoration

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Database Files
- `DATABASE-SCHEMA.md` - Complete database schema with embedded SQL files
- SQL sections embedded in DATABASE-SCHEMA.md:
  - 001_extensions.sql
  - 002_tables.sql
  - 003_indexes.sql
  - 004_rls_policies.sql
  - 005_triggers.sql
  - 006_functions.sql
  - 007_views.sql
  - 008_storage.sql
  - 009_seed_data.sql (development only)

### Documentation Files
- `SECURITY.md` - Security requirements and RLS policy documentation
- `PRIVACY-DISCLOSURES.md` - Privacy requirements for App Store compliance

### Source Files
- `App/NaarsCarsApp.swift` - Main app entry point
- `App/AppState.swift` - Global app state management
- `App/AppLaunchManager.swift` - Critical-path launch management ⭐ NEW
- `App/ContentView.swift` - Root view handling auth states
- `Core/Utilities/Secrets.swift` - Supabase credentials (NOT committed to git)
- `Core/Services/SupabaseService.swift` - Singleton Supabase client
- `Core/Services/AuthService.swift` - Authentication service
- `Core/Services/RealtimeManager.swift` - Realtime subscription management ⭐ NEW
- `Core/Models/Profile.swift` - User profile model
- `Core/Models/Ride.swift` - Ride request model
- `Core/Models/Favor.swift` - Favor request model
- `Core/Models/Message.swift` - Message model
- `Core/Utilities/Constants.swift` - App-wide constants
- `Core/Utilities/Logger.swift` - Logging utility
- `Core/Utilities/AppError.swift` - Error types
- `Core/Utilities/RateLimiter.swift` - Client-side rate limiting ⭐ NEW
- `Core/Utilities/CacheManager.swift` - TTL-based caching ⭐ NEW
- `Core/Utilities/ImageCompressor.swift` - Image processing ⭐ NEW
- `Core/Utilities/DeviceIdentifier.swift` - Keychain-persisted device ID ⭐ NEW
- `Core/Extensions/Date+Extensions.swift` - Date helper methods
- `Core/Extensions/View+Extensions.swift` - SwiftUI view extensions
- `UI/Components/Buttons/PrimaryButton.swift` - Primary button component
- `UI/Components/Buttons/SecondaryButton.swift` - Secondary button component
- `UI/Components/Cards/RideCard.swift` - Ride card component
- `UI/Components/Cards/FavorCard.swift` - Favor card component
- `UI/Components/Feedback/LoadingView.swift` - Loading state view
- `UI/Components/Feedback/ErrorView.swift` - Error state view
- `UI/Components/Feedback/EmptyStateView.swift` - Empty state view
- `UI/Components/Feedback/SkeletonView.swift` - Skeleton loading components ⭐ NEW
- `UI/Components/Common/AvatarView.swift` - User avatar component
- `UI/Styles/ColorTheme.swift` - App color definitions
- `UI/Styles/Typography.swift` - Typography styles

### Test Files
- `NaarsCarsTests/Core/Utilities/RateLimiterTests.swift`
- `NaarsCarsTests/Core/Utilities/CacheManagerTests.swift`
- `NaarsCarsTests/Core/Utilities/ImageCompressorTests.swift`
- `NaarsCarsTests/Core/Services/RealtimeManagerTests.swift`
- `NaarsCarsTests/Core/Models/ProfileTests.swift`
- `NaarsCarsTests/Core/Models/RideTests.swift`
- `NaarsCarsTests/Core/Models/FavorTests.swift`

### Edge Functions
- `supabase/functions/send-push-notification/index.ts`
- `supabase/functions/cleanup-tokens/index.ts`
- `supabase/functions/refresh-leaderboard/index.ts`

## Notes

- This is an iOS Swift/SwiftUI project, not TypeScript/JavaScript
- Use Swift Package Manager for dependencies
- Follow MVVM architecture pattern
- All network calls must use async/await
- Minimum iOS version: 17.0
- **Database setup (Tasks 0.0-5.0) MUST be completed before app development**
- Database tasks are done in Supabase Dashboard SQL Editor (no Xcode required)
- Task 1.0 creates the Xcode project AND the feature branch
- Never commit Supabase credentials to git
- Seed data is for development only - never run in production
- RLS must be enabled and tested on ALL tables before connecting the app
- ⭐ NEW items are from Security/Performance Review
- 🧪 items are QA tasks - write tests as you implement
- 🔒 CHECKPOINT items are mandatory quality gates - do not skip
- ⛔ marks blocking tasks that must complete before dependent work

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

---

## Tasks

### ⛔ DATABASE SETUP (Tasks 0.0-5.0 must complete before app development)

- [ ] 0.0 ⛔ Create Supabase project and execute core database schema
  - [x] 0.1 Go to supabase.com and sign in (or create account)
  - [x] 0.2 Click "New Project" and enter project name: "naars-cars"
  - [x] 0.3 Set a secure database password and save it securely
  - [x] 0.4 Select region closest to your users and wait for provisioning (~2 min)
  - [x] 0.5 Go to Project Settings → API and copy/save Project URL
  - [x] 0.6 Copy/save the anon/public key (⚠️ NOT service_role key)
  - [ ] 0.7 In Supabase Dashboard, go to SQL Editor → New Query
  - [ ] 0.8 Copy SQL from DATABASE-SCHEMA.md Section 3.1 (001_extensions.sql)
  - [ ] 0.9 Paste and click "Run" - verify "Success" message
  - [ ] 0.10 Create new query, copy SQL from Section 3.2 (002_tables.sql)
  - [ ] 0.11 Paste and click "Run" - verify all tables created
  - [ ] 0.12 Go to Table Editor and verify 14 tables exist: profiles, invite_codes, rides, ride_participants, favors, favor_participants, request_qa, conversations, conversation_participants, messages, notifications, push_tokens, reviews, town_hall_posts
  - [ ] 0.13 Create new query, copy SQL from Section 3.3 (003_indexes.sql)
  - [ ] 0.14 Paste and click "Run" - verify indexes created

- [x] 1.0 Set up Xcode project, folder structure, and feature branch
  - [x] 1.1 Open Xcode and create new iOS App project named "NaarsCars"
  - [x] 1.2 Set organization identifier to "com.naarscars" (or your own)
  - [x] 1.3 Select SwiftUI interface and Swift language
  - [x] 1.4 Set minimum deployment target to iOS 17.0
  - [x] 1.5 Include unit tests when prompted
  - [x] 1.6 Save project and initialize git repository
  - [x] 1.7 Create and checkout feature branch: `git checkout -b feature/foundation-architecture`
  - [x] 1.8 Create folder groups in Project Navigator: App, Features, Core, UI, Resources
  - [x] 1.9 Create subfolders under Features: Authentication, Rides, Favors, Messaging, Notifications, Profile, TownHall, Leaderboards, Admin
  - [x] 1.10 Create subfolders under Core: Services, Models, Extensions, Utilities
  - [x] 1.11 Create subfolders under UI: Components, Styles, Modifiers
  - [x] 1.12 Create subfolders under UI/Components: Buttons, Cards, Inputs, Feedback, Common, Messaging
  - [x] 1.13 Move default ContentView.swift to App folder
  - [x] 1.14 Move NaarsCarsApp.swift to App folder
  - [x] 1.15 Create test folder structure: NaarsCarsTests/Core/Utilities, NaarsCarsTests/Core/Services, NaarsCarsTests/Core/Models, NaarsCarsTests/Features
  - [x] 1.16 Commit initial project structure

- [ ] 2.0 ⛔ Execute database RLS policies and triggers
  - [ ] 2.1 In SQL Editor, create new query
  - [ ] 2.2 Copy SQL from DATABASE-SCHEMA.md Section 3.4 (004_rls_policies.sql)
  - [ ] 2.3 Paste and click "Run" - verify all policies created
  - [ ] 2.4 Go to Authentication → Policies in Dashboard
  - [ ] 2.5 Verify each table shows RLS policies listed
  - [ ] 2.6 ⚠️ CRITICAL: Verify "RLS Enabled" toggle is ON for ALL 14 tables
  - [ ] 2.7 If any table shows RLS disabled, run: `ALTER TABLE public.[tablename] ENABLE ROW LEVEL SECURITY;`
  - [ ] 2.8 Create new query, copy SQL from Section 3.5 (005_triggers.sql)
  - [ ] 2.9 Paste and click "Run" - verify trigger functions created
  - [ ] 2.10 Go to Database → Functions in Dashboard
  - [ ] 2.11 Verify these trigger functions exist: handle_updated_at, handle_new_user, handle_new_message, handle_invite_code_used, protect_admin_fields, handle_new_review, mark_request_reviewed

- [ ] 3.0 ⛔ Execute database functions, views, and storage buckets
  - [ ] 3.1 In SQL Editor, create new query
  - [ ] 3.2 Copy SQL from DATABASE-SCHEMA.md Section 3.6 (006_functions.sql)
  - [ ] 3.3 Paste and click "Run" - verify functions created
  - [ ] 3.4 Verify these functions exist in Database → Functions: get_user_stats, get_unread_counts, mark_messages_read, get_or_create_request_conversation, cleanup_stale_push_tokens, validate_invite_code, get_pending_reviews
  - [ ] 3.5 Create new query, copy SQL from Section 3.7 (007_views.sql)
  - [ ] 3.6 Paste and click "Run" - verify views created
  - [ ] 3.7 Verify leaderboard_stats view exists and get_leaderboard function works
  - [ ] 3.8 Create new query, copy SQL from Section 3.8 (008_storage.sql)
  - [ ] 3.9 Paste and click "Run" - verify buckets created
  - [ ] 3.10 Go to Storage in Dashboard and verify buckets: avatars (public), town-hall-images (public), message-images (private)
  - [ ] 3.11 Click each bucket → Policies and verify storage policies configured

- [ ] 4.0 ⛔ Create test users, execute seed data, and deploy Edge Functions
  - [ ] 4.1 Go to Authentication → Users in Supabase Dashboard
  - [ ] 4.2 Click "Add User" → "Create New User"
  - [ ] 4.3 Create alice@test.com with password TestPassword123! - note the User UID
  - [ ] 4.4 Create bob@test.com with same password - note UID
  - [ ] 4.5 Create carol@test.com with same password - note UID
  - [ ] 4.6 Create dave@test.com with same password - note UID
  - [ ] 4.7 Create eve@test.com with same password - note UID
  - [ ] 4.8 ⚠️ DEVELOPMENT ONLY: Open DATABASE-SCHEMA.md Section 3.9 (009_seed_data.sql)
  - [ ] 4.9 Update UUID placeholders with actual UIDs from steps 4.3-4.7
  - [ ] 4.10 Create new query, paste updated seed SQL, click "Run"
  - [ ] 4.11 Verify seed data: profiles (5), invite_codes (6+), rides (6), favors (5), reviews (2+), conversations (2), messages (6+), notifications (5+), town_hall_posts (3), request_qa (4)
  - [ ] 4.12 Install Supabase CLI: `npm install -g supabase`
  - [ ] 4.13 Login to Supabase CLI: `supabase login`
  - [ ] 4.14 Link project: `supabase link --project-ref [your-project-ref]`
  - [ ] 4.15 Create Edge Function: `supabase functions new send-push-notification`
  - [ ] 4.16 Implement send-push-notification function (APNs integration)
  - [ ] 4.17 Create Edge Function: `supabase functions new cleanup-tokens`
  - [ ] 4.18 Implement cleanup-tokens to call cleanup_stale_push_tokens()
  - [ ] 4.19 Create Edge Function: `supabase functions new refresh-leaderboard`
  - [ ] 4.20 Deploy all functions: `supabase functions deploy`
  - [ ] 4.21 Configure cleanup-tokens as scheduled function (daily)
  - [ ] 4.22 Configure refresh-leaderboard as scheduled function (hourly)

- [ ] 5.0 🔒 CHECKPOINT: Verify database setup with security and performance tests
  - [ ] 5.1 Run verification query from DATABASE-SCHEMA.md to check table counts
  - [ ] 5.2 🧪 SEC-DB-001: Test query profiles as unauthenticated - verify blocked by RLS
  - [ ] 5.3 🧪 SEC-DB-002: Test query profiles as unapproved user (eve) - verify only own profile returned
  - [ ] 5.4 🧪 SEC-DB-003: Test query profiles as approved user (bob) - verify all approved profiles returned
  - [ ] 5.5 🧪 SEC-DB-004: Test update another user's profile - verify blocked by RLS
  - [ ] 5.6 🧪 SEC-DB-005: Test set own is_admin=true as non-admin - verify blocked by trigger
  - [ ] 5.7 🧪 SEC-DB-006: Test admin (alice) approve user - verify succeeds
  - [ ] 5.8 🧪 SEC-DB-007: Test non-admin approve user - verify blocked by RLS
  - [ ] 5.9 🧪 SEC-DB-008: Test query messages not in conversation - verify blocked
  - [ ] 5.10 🧪 SEC-DB-009: Test insert ride with different user_id - verify blocked
  - [ ] 5.11 🧪 PERF-DB-001: Query open rides - verify <100ms
  - [ ] 5.12 🧪 PERF-DB-002: Query leaderboard - verify <200ms
  - [ ] 5.13 🧪 PERF-DB-003: Query conversation messages - verify <100ms
  - [ ] 5.14 🧪 EDGE-001: Test send-push-notification with valid token
  - [ ] 5.15 🧪 EDGE-002: Test cleanup-tokens function
  - [ ] 5.16 Test auto-profile trigger: create new auth user, verify profile auto-created
  - [ ] 5.17 Verify Alice is admin: `SELECT is_admin, approved FROM profiles WHERE email = 'alice@test.com'`
  - [ ] 5.18 If not admin, fix: `UPDATE profiles SET is_admin = true, approved = true WHERE email = 'alice@test.com'`
  - [ ] 5.19 Document any issues found and fixes applied
  - [ ] 5.20 ✅ Database setup verified - proceed to app development

---

### APP DEVELOPMENT (Tasks 6.0+)

- [ ] 6.0 Configure Supabase SDK integration
  - [x] 6.1 In Xcode, go to File → Add Package Dependencies
  - [x] 6.2 Enter URL: https://github.com/supabase/supabase-swift
  - [x] 6.3 Select version 2.0.0 or later and add to NaarsCars target
  - [x] 6.4 Wait for package resolution to complete
  - [x] 6.5 Create Secrets.swift file in Core/Utilities folder
  - [x] 6.6 Add Supabase URL and anon key to Secrets.swift (from Task 0.5, 0.6)
  - [x] 6.7 Add Secrets.swift to .gitignore file
  - [x] 6.8 ⭐ Create obfuscation helper script (Scripts/obfuscate.swift) for credential encoding
  - [x] 6.9 ⭐ Implement XOR deobfuscation function in Secrets.swift
  - [x] 6.10 ⭐ Replace plain text credentials with obfuscated byte arrays
  - [x] 6.11 Create SupabaseService.swift in Core/Services with singleton pattern
  - [x] 6.12 Initialize SupabaseClient in SupabaseService using credentials from Secrets
  - [x] 6.13 Test Supabase connection by running a simple query (e.g., fetch profiles count)
  - [x] 6.14 Commit SDK integration

- [x] 7.0 Create core data models
  - [x] 7.1 Create Profile.swift in Core/Models with all fields from FR-002 (id, name, email, car, phone_number, avatar_url, is_admin, approved, invited_by, notification preferences, timestamps)
  - [x] 7.2 Make Profile conform to Codable, Identifiable, Equatable
  - [x] 7.3 Add CodingKeys enum mapping snake_case to camelCase
  - [x] 7.4 🧪 Write ProfileTests.swift - test Codable encoding/decoding with snake_case JSON
  - [x] 7.5 Create Ride.swift in Core/Models with all fields from FR-003 (id, user_id, type, date, time, pickup, destination, seats, notes, gift, status, claimed_by, reviewed, timestamps)
  - [x] 7.6 Create RideStatus enum matching database enum
  - [x] 7.7 Make Ride conform to Codable, Identifiable, Equatable
  - [x] 7.8 🧪 Write RideTests.swift - test Codable with enum and date handling
  - [x] 7.9 Create Favor.swift in Core/Models with all fields from FR-004
  - [x] 7.10 Create FavorStatus and FavorDuration enums matching database
  - [x] 7.11 Make Favor conform to Codable, Identifiable, Equatable
  - [x] 7.12 🧪 Write FavorTests.swift - test Codable encoding/decoding
  - [x] 7.13 Create Message.swift in Core/Models (id, conversation_id, from_id, text, image_url, read_by, created_at)
  - [x] 7.14 Make Message conform to Codable, Identifiable, Equatable
  - [x] 7.15 Create Conversation.swift, AppNotification.swift, InviteCode.swift, Review.swift, TownHallPost.swift
  - [x] 7.16 Commit all models

### 🔒 CHECKPOINT: QA-FOUNDATION-001
> Run: `./QA/Scripts/checkpoint.sh foundation-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: Project compiles, all model tests pass
> Must pass before continuing

- [x] 8.0 Implement service layer architecture
  - [x] 8.1 Create AuthService.swift skeleton in Core/Services with @MainActor and ObservableObject
  - [x] 8.2 Add singleton pattern to AuthService with static shared instance
  - [x] 8.3 Add @Published properties: currentUserId (UUID?), currentProfile (Profile?), isLoading (Bool)
  - [x] 8.4 Add method stubs: checkAuthStatus(), signIn(), signUp(), signOut(), sendPasswordReset()
  - [x] 8.5 Add session lifecycle management: clear CacheManager on logout, unsubscribe RealtimeManager (TODO comments added)
  - [x] 8.6 Create AppError.swift in Core/Utilities with all error cases from FR-040
  - [x] 8.7 Add LocalizedError conformance with user-friendly errorDescription
  - [x] 8.8 Document each service class with clear comments explaining its purpose
  - [ ] 8.9 Commit service layer

- [ ] 9.0 Build app state management
  - [ ] 9.1 Create AppState.swift in App folder
  - [ ] 9.2 Make AppState conform to ObservableObject with @MainActor
  - [ ] 9.3 Add @Published var currentUser: Profile? property
  - [ ] 9.4 Add @Published var isLoading: Bool = true property
  - [ ] 9.5 Add computed properties: isAdmin, isApproved (from FR-035)
  - [ ] 9.6 Create AuthState enum: loading, unauthenticated, pendingApproval, authenticated
  - [ ] 9.7 Add computed authState property that returns appropriate AuthState
  - [ ] 9.8 Update NaarsCarsApp.swift to create @StateObject var appState = AppState()
  - [ ] 9.9 Update NaarsCarsApp.swift to inject appState as environmentObject to ContentView
  - [ ] 9.10 Commit app state

- [ ] 10.0 Create reusable UI components
  - [ ] 10.1 Create ColorTheme.swift in UI/Styles with brand colors from FR-056
  - [ ] 10.2 Add Color extension for hex color initialization
  - [ ] 10.3 Create Typography.swift in UI/Styles with text style definitions
  - [ ] 10.4 Create PrimaryButton.swift in UI/Components/Buttons with loading state support
  - [ ] 10.5 Create SecondaryButton.swift in UI/Components/Buttons
  - [ ] 10.6 Create LoadingView.swift in UI/Components/Feedback with optional message parameter
  - [ ] 10.7 Create ErrorView.swift in UI/Components/Feedback with error and retry action
  - [ ] 10.8 Create EmptyStateView.swift in UI/Components/Feedback with icon, title, message, optional action
  - [ ] 10.9 Create AvatarView.swift in UI/Components/Common using AsyncImage with initials fallback
  - [ ] 10.10 Create RideCard.swift skeleton in UI/Components/Cards
  - [ ] 10.11 Create FavorCard.swift skeleton in UI/Components/Cards
  - [ ] 10.12 Add Xcode Previews to each component
  - [ ] 10.13 Commit UI components

- [ ] 11.0 Add utilities and extensions
  - [ ] 11.1 Create Constants.swift in Core/Utilities with app-wide constants (animation durations, spacing, API timeouts)
  - [ ] 11.2 Create Logger.swift in Core/Utilities with categories: auth, network, ui, realtime, push
  - [ ] 11.3 ⭐ Add Log.security() method for admin operations and auth failures
  - [ ] 11.4 Create Date+Extensions.swift in Core/Extensions
  - [ ] 11.5 Add Date extensions: isToday, timeAgo, formatted strings (timeString, dateString)
  - [ ] 11.6 Create View+Extensions.swift in Core/Extensions
  - [ ] 11.7 Add View extensions for common modifiers (cardStyle, etc.)
  - [ ] 11.8 Create Validators.swift in Core/Utilities for input validation helpers
  - [ ] 11.9 Commit utilities

- [ ] 12.0 Set up navigation and routing
  - [ ] 12.1 Update ContentView.swift to observe AppState via @EnvironmentObject
  - [ ] 12.2 Add switch on appState.authState with cases from FR-039
  - [ ] 12.3 Case .loading → show LoadingView
  - [ ] 12.4 Case .unauthenticated → show placeholder Text("Login View")
  - [ ] 12.5 Case .pendingApproval → show placeholder PendingApprovalView
  - [ ] 12.6 Case .authenticated → show MainTabView
  - [ ] 12.7 Add .task modifier to ContentView that calls auth check on appear
  - [ ] 12.8 Create MainTabView.swift with 5 tabs from FR-038
  - [ ] 12.9 Create placeholder views: DashboardView, MessagesListView, NotificationsListView, LeaderboardView, ProfileView
  - [ ] 12.10 Wrap each tab content in NavigationStack
  - [ ] 12.11 Create PendingApprovalView.swift with waiting message
  - [ ] 12.12 Commit navigation

### 🔒 CHECKPOINT: QA-FOUNDATION-002
> Run: `./QA/Scripts/checkpoint.sh foundation-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: App launches, navigation works based on auth state, UI components render in previews
> Must pass before continuing

- [ ] 13.0 ⭐ Create Security Documentation ⛔
  - [ ] 13.1 Create or verify SECURITY.md exists in project root
  - [ ] 13.2 Document RLS policy requirements for all 14 tables (reference FR-010)
  - [ ] 13.3 Document credential management guidelines (Secrets.swift, obfuscation)
  - [ ] 13.4 Document admin authorization requirements (server-side verification)
  - [ ] 13.5 Document rate limiting requirements table (from FR-045)
  - [ ] 13.6 Document security logging requirements
  - [ ] 13.7 Add defense-in-depth guidelines for client code
  - [ ] 13.8 Add pre-launch security checklist
  - [ ] 13.9 Commit SECURITY.md

- [ ] 14.0 ⭐ Create Privacy Documentation and Info.plist keys ⛔
  - [ ] 14.1 Create PRIVACY-DISCLOSURES.md in project root
  - [ ] 14.2 Document all required Info.plist privacy keys with descriptions
  - [ ] 14.3 Document App Store Connect Privacy Nutrition Label selections
  - [ ] 14.4 Document user consent flows for each permission
  - [ ] 14.5 Document phone number visibility disclosure requirements
  - [ ] 14.6 Document data retention policies
  - [ ] 14.7 Add pre-submission privacy checklist
  - [ ] 14.8 Add NSPhotoLibraryUsageDescription to Info.plist
  - [ ] 14.9 Add NSCameraUsageDescription to Info.plist
  - [ ] 14.10 Add NSLocationWhenInUseUsageDescription to Info.plist
  - [ ] 14.11 Add NSFaceIDUsageDescription to Info.plist
  - [ ] 14.12 Commit privacy documentation and Info.plist

- [ ] 15.0 ⭐ Create RateLimiter Utility ⛔
  - [ ] 15.1 Create RateLimiter.swift in Core/Utilities
  - [ ] 15.2 Implement as actor for thread safety
  - [ ] 15.3 Add private lastActionTime dictionary [String: Date]
  - [ ] 15.4 Implement checkAndRecord(action:minimumInterval:) -> Bool method
  - [ ] 15.5 Implement reset(action:) method to clear rate limit
  - [ ] 15.6 Add static shared instance
  - [ ] 15.7 Document rate limit intervals for each action type (from FR-045)
  - [ ] 15.8 🧪 Write RateLimiterTests - test checkAndRecord returns false when too fast
  - [ ] 15.9 🧪 Write RateLimiterTests - test checkAndRecord returns true after interval passes
  - [ ] 15.10 🧪 Write RateLimiterTests - test reset clears the rate limit
  - [ ] 15.11 Commit RateLimiter

- [ ] 16.0 ⭐ Create CacheManager Utility
  - [ ] 16.1 Create CacheManager.swift in Core/Utilities
  - [ ] 16.2 Implement as actor for thread safety
  - [ ] 16.3 Add profile cache with 5-minute TTL (from FR-042)
  - [ ] 16.4 Add rides cache with 2-minute TTL
  - [ ] 16.5 Add favors cache with 2-minute TTL
  - [ ] 16.6 Add conversations cache with 1-minute TTL
  - [ ] 16.7 Implement getCachedProfile(id:) with TTL check
  - [ ] 16.8 Implement cacheProfile(_:) method
  - [ ] 16.9 Implement invalidateProfile(id:) method
  - [ ] 16.10 Implement getCachedRides() / cacheRides(_:) / invalidateRides()
  - [ ] 16.11 Implement getCachedFavors() / cacheFavors(_:) / invalidateFavors()
  - [ ] 16.12 Implement clearAll() method for logout
  - [ ] 16.13 🧪 Write CacheManagerTests - test cache returns nil when empty
  - [ ] 16.14 🧪 Write CacheManagerTests - test cache returns value before TTL expires
  - [ ] 16.15 🧪 Write CacheManagerTests - test cache returns nil after TTL expires
  - [ ] 16.16 🧪 Write CacheManagerTests - test clearAll removes all cached data
  - [ ] 16.17 Commit CacheManager

### 🔒 CHECKPOINT: QA-FOUNDATION-003
> Run: `./QA/Scripts/checkpoint.sh foundation-003`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: RateLimiter and CacheManager tests pass
> Must pass before continuing

- [ ] 17.0 ⭐ Create ImageCompressor Utility ⛔
  - [ ] 17.1 Create ImageCompressor.swift in Core/Utilities
  - [ ] 17.2 Define Preset enum with cases: avatar, messageImage, fullSize (from FR-047)
  - [ ] 17.3 Define maxDimension for each preset (400, 1200, 2000)
  - [ ] 17.4 Define maxBytes for each preset (200KB, 500KB, 1MB)
  - [ ] 17.5 Define initialQuality for each preset (0.8, 0.7, 0.8)
  - [ ] 17.6 Implement compress(_:preset:) static method
  - [ ] 17.7 Implement private resize(_:maxDimension:) method using UIGraphicsImageRenderer
  - [ ] 17.8 Implement iterative quality reduction loop to meet size targets
  - [ ] 17.9 Return nil if image cannot be compressed enough (quality < 0.1)
  - [ ] 17.10 🧪 Write ImageCompressorTests - test avatar preset reduces dimensions correctly
  - [ ] 17.11 🧪 Write ImageCompressorTests - test output size is under maxBytes
  - [ ] 17.12 Commit ImageCompressor

- [ ] 18.0 ⭐ Create RealtimeManager ⛔
  - [ ] 18.1 Create RealtimeManager.swift in Core/Services
  - [ ] 18.2 Implement as @MainActor singleton
  - [ ] 18.3 Add activeChannels dictionary [String: RealtimeChannelV2]
  - [ ] 18.4 Set maxConcurrentSubscriptions = 3 (from FR-049)
  - [ ] 18.5 Implement subscribe(channelName:table:filter:onInsert:onUpdate:onDelete:) method
  - [ ] 18.6 Add logic to unsubscribe oldest channel if limit exceeded
  - [ ] 18.7 Implement unsubscribe(channelName:) method
  - [ ] 18.8 Implement unsubscribeAll() method
  - [ ] 18.9 Add NotificationCenter observer for UIApplication.didEnterBackgroundNotification
  - [ ] 18.10 Add NotificationCenter observer for UIApplication.willEnterForegroundNotification
  - [ ] 18.11 Implement auto-unsubscribe after 30 seconds in background
  - [ ] 18.12 Add logging for subscription events using Log.realtime()
  - [ ] 18.13 🧪 Write RealtimeManagerTests - test subscribe adds channel to activeChannels
  - [ ] 18.14 🧪 Write RealtimeManagerTests - test max subscriptions enforced (oldest removed)
  - [ ] 18.15 🧪 Write RealtimeManagerTests - test unsubscribeAll clears all channels
  - [ ] 18.16 Commit RealtimeManager

- [ ] 19.0 ⭐ Create AppLaunchManager
  - [ ] 19.1 Create AppLaunchManager.swift in App folder
  - [ ] 19.2 Define LaunchState enum: initializing, checkingAuth, ready(AuthState), failed(Error)
  - [ ] 19.3 Add @Published state property
  - [ ] 19.4 Implement performCriticalLaunch() - auth session + approval check only (from FR-051)
  - [ ] 19.5 Implement private checkApprovalStatus(userId:) - minimal query for approved field
  - [ ] 19.6 Implement performDeferredLoading(userId:) - background fetch of profile, rides, etc.
  - [ ] 19.7 Target: critical path completes in <1 second
  - [ ] 19.8 Update ContentView to use AppLaunchManager instead of inline auth check
  - [ ] 19.9 Commit AppLaunchManager

- [ ] 20.0 ⭐ Create Skeleton UI Components
  - [ ] 20.1 Create SkeletonView.swift in UI/Components/Feedback
  - [ ] 20.2 Implement shimmer animation with LinearGradient
  - [ ] 20.3 Create SkeletonRideCard component matching RideCard layout
  - [ ] 20.4 Create SkeletonFavorCard component matching FavorCard layout
  - [ ] 20.5 Create SkeletonMessageRow component
  - [ ] 20.6 Create SkeletonConversationRow component
  - [ ] 20.7 Create SkeletonLeaderboardRow component
  - [ ] 20.8 Add Xcode previews for all skeleton components
  - [ ] 20.9 Commit skeleton components

- [ ] 21.0 ⭐ Create DeviceIdentifier Utility
  - [ ] 21.1 Create DeviceIdentifier.swift in Core/Utilities
  - [ ] 21.2 Implement private readFromKeychain() function using Security framework
  - [ ] 21.3 Implement private saveToKeychain(_:) function
  - [ ] 21.4 Add static var current: String that returns persistent UUID
  - [ ] 21.5 Generate new UUID on first access if not in Keychain
  - [ ] 21.6 Use kSecAttrAccessibleAfterFirstUnlock for accessibility
  - [ ] 21.7 Verify identifier survives app reinstall (Keychain persists)
  - [ ] 21.8 Commit DeviceIdentifier

### 🔒 CHECKPOINT: QA-FOUNDATION-004
> Run: `./QA/Scripts/checkpoint.sh foundation-004`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ImageCompressor tests pass, RealtimeManager tests pass
> Must pass before continuing

- [ ] 22.0 🔒 Verify foundation implementation and run all tests
  - [ ] 22.1 Build project and ensure zero compilation errors
  - [ ] 22.2 Run app in simulator and verify it launches without crashes
  - [ ] 22.3 Verify folder structure matches PRD specification (FR-024)
  - [ ] 22.4 Test SupabaseService singleton can be accessed and queries work
  - [ ] 22.5 Verify all reusable components render correctly in Xcode Previews
  - [ ] 22.6 Run all unit tests: `Cmd+U` or `xcodebuild test`
  - [ ] 22.7 Verify RateLimiter tests pass (3 tests)
  - [ ] 22.8 Verify CacheManager tests pass (4 tests)
  - [ ] 22.9 Verify ImageCompressor tests pass (2 tests)
  - [ ] 22.10 Verify RealtimeManager tests pass (3 tests)
  - [ ] 22.11 Verify model tests pass (Profile, Ride, Favor)
  - [ ] 22.12 🧪 PERF-CLI-001: Measure app cold launch to main screen - verify <1 second
  - [ ] 22.13 🧪 PERF-CLI-002: Test cache hit returns immediately - verify <10ms
  - [ ] 22.14 🧪 PERF-CLI-003: Test rate limiter blocks rapid taps
  - [ ] 22.15 🧪 PERF-CLI-004: Test image compression meets size limits
  - [ ] 22.16 Verify SECURITY.md is complete and documents all RLS policies
  - [ ] 22.17 Verify PRIVACY-DISCLOSURES.md is complete
  - [ ] 22.18 Verify Info.plist has all 4 required privacy keys
  - [ ] 22.19 Code review: check all files follow Swift naming conventions
  - [ ] 22.20 Code review: verify all classes and methods have documentation comments
  - [ ] 22.21 Commit final changes with message: "feat: implement foundation architecture with database, security, and performance infrastructure"
  - [ ] 22.22 Push feature branch to remote repository
  - [ ] 22.23 Create pull request for code review

### 🔒 CHECKPOINT: QA-FOUNDATION-FINAL
> Run: `./QA/Scripts/checkpoint.sh foundation-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_FOUNDATION_001
> All foundation tests must pass before starting Authentication feature
