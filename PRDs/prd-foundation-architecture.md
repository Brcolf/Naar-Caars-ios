# PRD: Foundation Architecture

## Document Information
- **Feature Name**: Foundation Architecture
- **Phase**: 0 (Must be completed first)
- **Dependencies**: None (this is the foundation)
- **Estimated Effort**: 2-3 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the foundational architecture for the Naar's Cars iOS application. It establishes the complete Supabase database schema, project structure, design patterns, shared components, security infrastructure, and performance optimizations that every other feature will build upon.

### Why does this matter?
Building a solid foundation prevents technical debt and makes future development faster and more reliable. The database must be fully configured with Row Level Security before any client code connects. Since the target developer is at a beginner/intermediate SwiftUI level, having clear patterns to follow will reduce confusion and bugs.

### What problem does it solve?
Without a defined architecture:
- Database security vulnerabilities from missing RLS policies
- Code becomes messy and hard to maintain
- Different features work in inconsistent ways
- Bugs are harder to find and fix
- Adding new features becomes increasingly difficult
- Performance issues from lack of caching and rate limiting

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Configure complete Supabase database | 14 tables created with all constraints |
| Enable Row Level Security | RLS enabled on 100% of tables with policies verified |
| Create database automation | Triggers auto-create profiles, update timestamps |
| Deploy Edge Functions | 3 functions deployed and operational |
| Configure storage buckets | 3 buckets with correct access policies |
| Provide development seed data | 5 test users with sample data loadable |
| Establish consistent project structure | All files organized in defined folders |
| Configure Supabase Swift SDK | Successfully connect to Supabase backend |
| Create reusable UI components | 10+ shared components used across features |
| Implement caching strategy | CacheManager with TTL-based caching |
| Implement rate limiting | RateLimiter prevents rapid duplicate actions |
| Implement image processing | ImageCompressor meets size/dimension limits |
| Implement error handling pattern | All errors display user-friendly messages |
| Define navigation architecture | Tab-based navigation works consistently |
| Create security documentation | SECURITY.md documents all RLS policies |
| Create privacy documentation | PRIVACY-DISCLOSURES.md ready for App Store |

---

## 3. User Stories

### Developer Experience

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| FA-01 | Developer | Have the database fully configured before coding | I can build features against a real schema |
| FA-02 | Developer | Have RLS policies in place from the start | My queries are secure by default |
| FA-03 | Developer | Have seed data available | I can test features without manual data entry |
| FA-04 | Developer | Have a clear folder structure | I know where to put new files |
| FA-05 | Developer | Use pre-built UI components | I don't recreate buttons/cards for each feature |
| FA-06 | Developer | Have caching built-in | I don't make redundant network calls |
| FA-07 | Developer | Have rate limiting ready | I prevent accidental rapid actions |
| FA-08 | Developer | Follow established patterns | My code is consistent with the rest of the app |

### User Experience

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| FA-09 | User | See friendly error messages when something fails | I understand what went wrong |
| FA-10 | User | See skeleton loading states | I know content is loading (not frozen) |
| FA-11 | User | Have the app launch quickly | I can start using it within 1 second |
| FA-12 | User | Have my data protected | Only authorized users can see my information |

### QA/Testing

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| FA-13 | QA Tester | Have test users with known credentials | I can log in and test all user roles |
| FA-14 | QA Tester | Have an admin test user | I can test admin-only features |
| FA-15 | QA Tester | Have sample data for all features | I can test without creating data manually |

---

## 4. Functional Requirements

### 4.1 Database Schema

#### 4.1.1 Tables

**FR-001**: The database MUST include the following 14 tables:

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | User profiles | 1:1 with auth.users |
| `invite_codes` | Invitation codes | created_by → profiles |
| `rides` | Ride requests | user_id, claimed_by → profiles |
| `ride_participants` | Co-requestors | ride_id → rides, user_id → profiles |
| `favors` | Favor requests | user_id, claimed_by → profiles |
| `favor_participants` | Co-requestors | favor_id → favors, user_id → profiles |
| `request_qa` | Q&A threads | ride_id/favor_id, parent_id (self-ref) |
| `conversations` | Message threads | ride_id/favor_id optional |
| `conversation_participants` | Thread members | conversation_id, user_id |
| `messages` | Chat messages | conversation_id, from_id |
| `notifications` | In-app notifications | user_id, optional ride_id/favor_id |
| `push_tokens` | APNs device tokens | user_id |
| `reviews` | User reviews/ratings | reviewer_id, fulfiller_id → profiles |
| `town_hall_posts` | Community posts | user_id → profiles |

**FR-002**: The `profiles` table MUST have this structure:

```sql
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    car TEXT,
    phone_number TEXT,
    avatar_url TEXT,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    approved BOOLEAN NOT NULL DEFAULT false,
    invited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    
    -- Notification preferences
    notify_ride_updates BOOLEAN DEFAULT true,
    notify_messages BOOLEAN DEFAULT true,
    notify_announcements BOOLEAN DEFAULT true,
    notify_new_requests BOOLEAN DEFAULT true,
    notify_qa_activity BOOLEAN DEFAULT true,
    notify_review_reminders BOOLEAN DEFAULT true,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**FR-003**: The `rides` table MUST have this structure:

```sql
CREATE TYPE public.ride_status AS ENUM ('open', 'pending', 'confirmed', 'completed');

CREATE TABLE public.rides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'request',
    date DATE NOT NULL,
    time TIME NOT NULL,
    pickup TEXT NOT NULL,
    destination TEXT NOT NULL,
    seats INTEGER DEFAULT 1,
    notes TEXT,
    gift TEXT,
    status public.ride_status NOT NULL DEFAULT 'open',
    claimed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed BOOLEAN NOT NULL DEFAULT false,
    review_skipped BOOLEAN DEFAULT false,
    review_skipped_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**FR-004**: The `favors` table MUST have this structure:

```sql
CREATE TYPE public.favor_status AS ENUM ('open', 'pending', 'confirmed', 'completed');
CREATE TYPE public.favor_duration AS ENUM ('under_hour', 'couple_hours', 'couple_days', 'not_sure');

CREATE TABLE public.favors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT NOT NULL,
    duration public.favor_duration NOT NULL DEFAULT 'not_sure',
    requirements TEXT,
    date DATE NOT NULL,
    time TIME,
    gift TEXT,
    status public.favor_status NOT NULL DEFAULT 'open',
    claimed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed BOOLEAN NOT NULL DEFAULT false,
    review_skipped BOOLEAN DEFAULT false,
    review_skipped_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**FR-005**: All tables MUST use UUID primary keys with `gen_random_uuid()` default.

**FR-006**: All tables MUST include `created_at TIMESTAMPTZ DEFAULT NOW()`.

**FR-007**: Mutable tables MUST include `updated_at TIMESTAMPTZ DEFAULT NOW()`.

**FR-008**: Foreign keys MUST use `ON DELETE CASCADE` or `ON DELETE SET NULL` as appropriate.

#### 4.1.2 Row Level Security

**FR-009**: ALL tables MUST have Row Level Security enabled before any client connects.

**FR-010**: RLS policies MUST enforce these access patterns:

| Table | SELECT | INSERT | UPDATE | DELETE |
|-------|--------|--------|--------|--------|
| profiles | Own + approved users | Own only | Own only | N/A |
| invite_codes | Own created + unused (for validation) | Approved users | Mark as used | N/A |
| rides | Approved users | Own only | Own or claimed | Own only |
| ride_participants | Approved users | Ride owner | N/A | Ride owner |
| favors | Approved users | Own only | Own or claimed | Own only |
| favor_participants | Approved users | Favor owner | N/A | Favor owner |
| request_qa | Approved users | Approved users | N/A | Own only |
| conversations | Participants only | Approved users | Admins | N/A |
| conversation_participants | Participants | Creator or self | Own participation | N/A |
| messages | Participants | Participants as sender | Participants (read_by) | N/A |
| notifications | Own only | System only | Own only | N/A |
| push_tokens | Own only | Own only | Own only | Own only |
| reviews | Approved users | Reviewer only | N/A | N/A |
| town_hall_posts | Approved users | Own only | N/A | Own or admin |

**FR-011**: Admin operations MUST verify `is_admin = true` via RLS subquery, not client assertion.

**FR-012**: RLS policies MUST be documented in `SECURITY.md`.

#### 4.1.3 Database Triggers

**FR-013**: The following triggers MUST be created:

| Trigger | Table | Event | Action |
|---------|-------|-------|--------|
| `set_updated_at` | Multiple | BEFORE UPDATE | Set `updated_at = NOW()` |
| `on_auth_user_created` | auth.users | AFTER INSERT | Create profile row with defaults |
| `on_message_created` | messages | AFTER INSERT | Update conversation.updated_at |
| `on_invite_code_used` | invite_codes | BEFORE UPDATE | Set used_at, link invited_by |
| `protect_admin_fields` | profiles | BEFORE UPDATE | Prevent non-admin modifying is_admin/approved |
| `on_review_created` | reviews | BEFORE INSERT | Auto-create town_hall_post |
| `mark_request_reviewed` | reviews | AFTER INSERT | Set reviewed=true on ride/favor |

#### 4.1.4 Database Functions

**FR-014**: The following functions MUST be created:

| Function | Returns | Purpose |
|----------|---------|---------|
| `get_user_stats(user_id)` | avg_rating, review_count, fulfilled_count | Profile statistics |
| `get_unread_counts(user_id)` | unread_notifications, unread_messages | Badge counts |
| `mark_messages_read(conversation_id, user_id)` | void | Mark messages read |
| `get_or_create_request_conversation(...)` | UUID | Get/create conversation for request |
| `validate_invite_code(code)` | is_valid, code_id, created_by | Validate code for signup |
| `get_leaderboard(time_filter, limit)` | user_id, name, stats, rank | Leaderboard data |
| `get_pending_reviews(user_id)` | Pending review requests | Review reminders |
| `cleanup_stale_push_tokens()` | INT (deleted count) | Remove old tokens |

#### 4.1.5 Database Views

**FR-015**: Create `leaderboard_stats` view for efficient leaderboard queries:

```sql
CREATE VIEW public.leaderboard_stats AS
SELECT 
    p.id as user_id,
    p.name,
    p.avatar_url,
    COALESCE(fulfilled.count, 0) as fulfilled_count,
    COALESCE(ROUND(reviews.avg_rating, 2), 0) as average_rating,
    COALESCE(reviews.review_count, 0) as review_count,
    RANK() OVER (ORDER BY COALESCE(fulfilled.count, 0) DESC) as rank
FROM public.profiles p
LEFT JOIN (...) fulfilled ON fulfilled.user_id = p.id
LEFT JOIN (...) reviews ON reviews.user_id = p.id
WHERE p.approved = true;
```

#### 4.1.6 Performance Indexes

**FR-016**: Create indexes for all foreign keys and common query patterns:

| Index Pattern | Tables |
|---------------|--------|
| Foreign key columns | All tables with FKs |
| Status columns with WHERE | rides, favors |
| Timestamp ORDER BY | messages, notifications, rides, favors |
| Composite for common queries | rides(user_id, status), messages(conversation_id, created_at) |

### 4.2 Storage Buckets

**FR-017**: Create the following storage buckets:

| Bucket | Public | Max Size | Allowed Types | Access Policy |
|--------|--------|----------|---------------|---------------|
| `avatars` | Yes | 200KB | jpeg, png, webp | Owner upload, public read |
| `town-hall-images` | Yes | 500KB | jpeg, png, webp | Approved upload, public read |
| `message-images` | No | 500KB | jpeg, png, webp | Conversation participants only |

**FR-018**: Storage policies MUST restrict uploads to appropriate users/paths.

### 4.3 Edge Functions

**FR-019**: Deploy the following Edge Functions:

| Function | Trigger | Purpose | Implementation |
|----------|---------|---------|----------------|
| `send-push-notification` | HTTP POST | Send APNs push notification | Accepts user_id, title, body, data |
| `cleanup-tokens` | Scheduled (daily) | Remove stale push tokens | Calls `cleanup_stale_push_tokens()` |
| `refresh-leaderboard` | Scheduled (hourly) | Refresh cached leaderboard | Refresh materialized view if used |

**FR-020**: Push notification Edge Function MUST:
- Accept payload: `{ user_id, title, body, data?, badge? }`
- Query push_tokens for user's devices
- Send to APNs using stored auth key
- Handle token invalidation responses
- Log delivery status

### 4.4 Seed Data

**FR-021**: Development seed data MUST include:

| Entity | Count | Details |
|--------|-------|---------|
| Users | 5 | alice (admin), bob, carol, dave (approved), eve (pending) |
| Invite codes | 6 | 3 used, 3 available |
| Rides | 6 | 3 open (future), 1 confirmed, 2 completed |
| Favors | 5 | 3 open, 1 confirmed, 1 completed |
| Conversations | 2 | With message threads |
| Messages | 6+ | Sample conversation threads |
| Reviews | 2+ | For completed requests |
| Notifications | 5+ | Including 1 pinned admin announcement |
| Town Hall posts | 3 | Welcome + user posts |
| Q&A | 4 | Questions and replies |

**FR-022**: Test user credentials MUST use `[name]@test.com` format with documented passwords.

**FR-023**: Seed data SQL MUST be idempotent (safe to run multiple times).

### 4.5 Project Structure

**FR-024**: The Xcode project MUST use this folder structure:

```
NaarsCars/
├── App/
│   ├── NaarsCarsApp.swift
│   ├── AppState.swift
│   ├── AppLaunchManager.swift
│   └── ContentView.swift
├── Features/
│   ├── Authentication/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
│   ├── Rides/
│   ├── Favors/
│   ├── Messaging/
│   ├── Notifications/
│   ├── Profile/
│   ├── TownHall/
│   ├── Leaderboards/
│   └── Admin/
├── Core/
│   ├── Services/
│   │   ├── SupabaseService.swift
│   │   ├── AuthService.swift
│   │   └── RealtimeManager.swift
│   ├── Models/
│   │   ├── Profile.swift
│   │   ├── Ride.swift
│   │   ├── Favor.swift
│   │   └── Message.swift
│   ├── Extensions/
│   └── Utilities/
│       ├── Constants.swift
│       ├── Logger.swift
│       ├── AppError.swift
│       ├── RateLimiter.swift
│       ├── CacheManager.swift
│       ├── ImageCompressor.swift
│       └── DeviceIdentifier.swift
├── UI/
│   ├── Components/
│   │   ├── Buttons/
│   │   ├── Cards/
│   │   ├── Inputs/
│   │   ├── Feedback/
│   │   └── Common/
│   ├── Styles/
│   └── Modifiers/
└── Resources/
    ├── Assets.xcassets/
    └── Info.plist
```

**FR-025**: Every new Swift file MUST be placed in the appropriate folder.

**FR-026**: Feature folders MUST contain `Views/`, `ViewModels/`, and optionally `Models/`.

### 4.6 Supabase SDK Configuration

**FR-027**: Use `supabase-swift` SDK version 2.0+.

**FR-028**: Credentials MUST be stored in `Secrets.swift` (gitignored):

```swift
// Secrets.swift - DO NOT COMMIT
enum Secrets {
    static let supabaseURL = "https://your-project.supabase.co"
    static let supabaseAnonKey = "your-anon-key"
}
```

**FR-029**: Credentials SHOULD be obfuscated using XOR encoding (not plain text).

**FR-030**: Create singleton `SupabaseService` for all backend communication:

```swift
final class SupabaseService {
    static let shared = SupabaseService()
    let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseURL)!,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
}
```

**FR-031**: All Supabase operations MUST go through service classes, NOT directly in Views.

### 4.7 Data Models

**FR-032**: All models MUST conform to `Codable`, `Identifiable`, and `Equatable`.

**FR-033**: Model properties MUST use `CodingKeys` to map snake_case database columns:

```swift
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let email: String
    var phoneNumber: String?
    var isAdmin: Bool
    var approved: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, email
        case phoneNumber = "phone_number"
        case isAdmin = "is_admin"
        case approved
    }
}
```

**FR-034**: Required core models: `Profile`, `Ride`, `Favor`, `Message`, `Conversation`, `AppNotification`, `InviteCode`, `Review`, `TownHallPost`.

### 4.8 App State Management

**FR-035**: Create central `AppState` class:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: Profile?
    @Published var isLoading: Bool = true
    
    var isAdmin: Bool { currentUser?.isAdmin ?? false }
    var isApproved: Bool { currentUser?.approved ?? false }
    
    var authState: AuthState {
        if isLoading { return .loading }
        guard let user = currentUser else { return .unauthenticated }
        return user.approved ? .authenticated : .pendingApproval
    }
}

enum AuthState {
    case loading, unauthenticated, pendingApproval, authenticated
}
```

**FR-036**: `AppState` MUST be injected into SwiftUI environment at app root.

### 4.9 Navigation Architecture

**FR-037**: Use `NavigationStack` for all navigation.

**FR-038**: Main interface MUST use tab-based navigation:

| Tab | Icon | Label | Destination |
|-----|------|-------|-------------|
| 1 | `car.fill` | Requests | Dashboard |
| 2 | `message.fill` | Messages | Conversations |
| 3 | `bell.fill` | Notifications | Notifications |
| 4 | `trophy.fill` | Leaderboard | Leaderboard |
| 5 | `person.fill` | Profile | Profile |

**FR-039**: Navigation must handle auth states: loading → login/signup → pending → main tabs.

### 4.10 Error Handling

**FR-040**: Define `AppError` enum with user-friendly messages:

```swift
enum AppError: LocalizedError {
    case networkUnavailable
    case serverError(String)
    case invalidCredentials
    case sessionExpired
    case notAuthenticated
    case invalidInviteCode
    case notFound(String)
    case unauthorized
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "No internet connection."
        case .invalidCredentials: return "Invalid email or password."
        // ... etc
        }
    }
}
```

**FR-041**: ViewModels MUST use consistent error handling pattern with `isLoading`, `error`, `showError` properties.

### 4.11 Caching Strategy

**FR-042**: Implement `CacheManager` actor with TTL-based caching:

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| Profiles | 5 minutes | Balance freshness with performance |
| Rides/Favors | 2 minutes | Changes more frequently |
| Conversations | 1 minute | Messages arrive frequently |
| Leaderboard | 15 minutes | Changes slowly |

**FR-043**: Services MUST check cache before network requests.

**FR-044**: Cache MUST be invalidated on: user mutation, pull-to-refresh, logout.

### 4.12 Rate Limiting

**FR-045**: Implement `RateLimiter` actor to prevent rapid duplicate actions:

| Action | Minimum Interval |
|--------|------------------|
| Claim/unclaim | 5 seconds |
| Send message | 1 second |
| Generate invite | 10 seconds |
| Pull-to-refresh | 2 seconds |
| Login attempt | 2 seconds |
| Password reset | 30 seconds |

**FR-046**: When rate limited, show haptic feedback but no error alert.

### 4.13 Image Processing

**FR-047**: Implement `ImageCompressor` with presets:

| Preset | Max Dimension | Max Size |
|--------|---------------|----------|
| avatar | 400px | 200KB |
| messageImage | 1200px | 500KB |
| fullSize | 2000px | 1MB |

**FR-048**: All image uploads MUST use `ImageCompressor`.

### 4.14 Realtime Subscription Management

**FR-049**: Implement `RealtimeManager` singleton:
- Maximum 3 concurrent subscriptions
- Auto-unsubscribe oldest when limit exceeded
- Unsubscribe all after 30 seconds in background
- Resubscribe on foreground via view lifecycle

**FR-050**: Views MUST subscribe in `onAppear`, unsubscribe in `onDisappear`.

### 4.15 App Launch Sequence

**FR-051**: Critical path (blocks UI) must complete in <1 second:
- Auth session check
- Profile `approved` status check

**FR-052**: Deferred loading (after UI visible):
- Full profile details
- Ride/favor lists
- Conversations, notifications, leaderboard

**FR-053**: Show skeleton UI while deferred data loads.

### 4.16 Shared UI Components

**FR-054**: Create these reusable components:

| Component | Purpose |
|-----------|---------|
| `PrimaryButton` | Main action buttons |
| `SecondaryButton` | Secondary actions |
| `LoadingView` | Full-screen loading |
| `ErrorView` | Error with retry |
| `EmptyStateView` | Empty lists |
| `AvatarView` | User avatars |
| `SkeletonView` | Loading placeholders |
| `SkeletonRideCard` | Ride loading state |
| `SkeletonFavorCard` | Favor loading state |
| `ToastView` | Brief notifications |

**FR-055**: Components MUST have Xcode Previews.

### 4.17 Color Theme

**FR-056**: Define brand colors matching web app:

```swift
extension Color {
    static let naarsPrimary = Color(hex: "B5634B")    // Terracotta
    static let naarsAccent = Color(hex: "D4A574")     // Warm amber
    static let naarsSuccess = Color(hex: "22C55E")
    static let naarsWarning = Color(hex: "F59E0B")
    static let naarsError = Color(hex: "EF4444")
}
```

### 4.18 Logging

**FR-057**: Implement structured logging utility:

```swift
enum Log {
    static func auth(_ message: String) { ... }
    static func network(_ message: String) { ... }
    static func realtime(_ message: String) { ... }
    static func security(_ message: String) { ... }  // For admin ops, auth failures
}
```

### 4.19 Security Requirements

**FR-058**: All RLS policies MUST be documented in `SECURITY.md`.

**FR-059**: Client code SHOULD include defense-in-depth checks even with RLS.

**FR-060**: Implement security logging for admin operations and auth failures.

**FR-061**: Pre-launch checklist MUST include RLS verification for all tables.

### 4.20 Privacy Requirements

**FR-062**: Add Info.plist privacy keys before using features:
- `NSPhotoLibraryUsageDescription`
- `NSCameraUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSFaceIDUsageDescription`

**FR-063**: Document App Store Privacy Nutrition Labels in `PRIVACY-DISCLOSURES.md`.

**FR-064**: Defer permission requests until needed (not at launch).

**FR-065**: Handle permission denial gracefully with Settings app link.

---

## 5. Non-Goals (Out of Scope)

| Item | Reason | Future Consideration |
|------|--------|---------------------|
| Database migration tooling | Manual SQL sufficient for MVP | Add Supabase CLI in Phase 2+ |
| Read replicas | Single region sufficient | Consider for scaling |
| Materialized views | Standard views sufficient | Add if 500+ users |
| Authentication UI | Covered in `prd-authentication.md` | N/A |
| Specific feature implementations | Each feature has own PRD | N/A |
| App Store submission | Separate deployment document | N/A |
| Analytics integration | Future enhancement | Phase 2+ |
| Crash reporting | Future enhancement | Phase 2+ |
| Localization | Future enhancement | Phase 2+ |
| Dark mode custom theme | Use system defaults | Phase 2+ |
| iPad layout | iPhone only initially | Phase 2+ |

---

## 6. Design Considerations

### iOS-Native Patterns

| Pattern | Where to Use |
|---------|--------------|
| `NavigationStack` | All navigation |
| `ObservableObject` | ViewModels |
| `AsyncImage` | Remote images |
| `.task` modifier | Data fetching |
| `.refreshable` | All lists |
| `@Environment` | Dependency injection |
| `Form` | Settings, input screens |
| `List` with swipe actions | Message/notification lists |

### Entity Relationship Overview

```
auth.users (Supabase managed)
    │
    └──< profiles (1:1)
            │
            ├──< invite_codes
            ├──< rides ──< ride_participants, request_qa
            ├──< favors ──< favor_participants, request_qa
            ├──< reviews
            ├──< town_hall_posts
            ├──< notifications
            ├──< push_tokens
            └──< conversation_participants ──> conversations ──< messages
```

---

## 7. Technical Considerations

### Dependencies

| Package | URL | Version | Purpose |
|---------|-----|---------|---------|
| supabase-swift | github.com/supabase/supabase-swift | 2.0+ | Backend |

**No other external dependencies.** Use native SwiftUI and Foundation APIs.

### Minimum Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Supabase project (Free tier or higher)

### Performance Guidelines

- All network calls use `async/await`
- Lists with 20+ items use `LazyVStack`
- Images cached via `AsyncImage`
- Critical launch path <1 second

### Database Constraints

- Supabase Free tier: 500MB database, 1GB storage
- RLS adds ~5-10ms per query (acceptable)
- Edge Functions cold start ~200ms

---

## 8. Security & Performance Validation

### Database Security Tests

| Test ID | Test | Expected Result |
|---------|------|-----------------|
| SEC-DB-001 | Query profiles as unauthenticated | Blocked by RLS |
| SEC-DB-002 | Query profiles as unapproved user | Only own profile returned |
| SEC-DB-003 | Query profiles as approved user | All approved profiles returned |
| SEC-DB-004 | Update another user's profile | Blocked by RLS |
| SEC-DB-005 | Set own is_admin=true | Blocked by trigger |
| SEC-DB-006 | Admin approve user | Succeeds |
| SEC-DB-007 | Non-admin approve user | Blocked by RLS |
| SEC-DB-008 | Query messages not in conversation | Blocked by RLS |
| SEC-DB-009 | Insert ride as different user_id | Blocked by RLS |
| SEC-DB-010 | Claim own ride | Blocked by constraint or RLS |

### Database Performance Tests

| Test ID | Test | Expected Result |
|---------|------|-----------------|
| PERF-DB-001 | Query open rides (100 rows) | <100ms |
| PERF-DB-002 | Query leaderboard (50 users) | <200ms |
| PERF-DB-003 | Query conversation messages (100) | <100ms |
| PERF-DB-004 | Insert message with trigger | <50ms |
| PERF-DB-005 | Indexes exist for all FKs | Verified via pg_indexes |

### Edge Function Tests

| Test ID | Test | Expected Result |
|---------|------|-----------------|
| EDGE-001 | Send push to valid token | 200 response, notification received |
| EDGE-002 | Send push to invalid token | Token removed from database |
| EDGE-003 | Cleanup tokens older than 90 days | Correct count returned |

### Client Performance Tests

| Test ID | Test | Expected Result |
|---------|------|-----------------|
| PERF-CLI-001 | App cold launch to main screen | <1 second |
| PERF-CLI-002 | Cache hit returns immediately | <10ms |
| PERF-CLI-003 | Rate limiter blocks rapid taps | Second tap blocked |
| PERF-CLI-004 | Image compression meets limits | Output ≤ preset max size |

---

## 9. Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Tables created | 14 | Query information_schema |
| RLS enabled | 100% | Supabase Dashboard |
| RLS policies tested | 10 tests pass | Manual SQL verification |
| Triggers working | Profile auto-created | Create auth user, verify profile |
| Functions callable | 8 functions | Test each with parameters |
| Edge Functions deployed | 3 | Invoke each, verify response |
| Storage buckets | 3 | Upload test file to each |
| Seed data loaded | All counts match FR-021 | Verification queries |
| Project compiles | Zero errors | Xcode build |
| Supabase connection | Query succeeds | Test query |
| Components render | All previews work | Xcode Previews |
| App launches | No crashes | Device testing |
| Cache tests pass | 4 tests | Unit tests |
| Rate limiter tests pass | 3 tests | Unit tests |
| Image compressor tests pass | 2 tests | Unit tests |
| Realtime manager tests pass | 3 tests | Unit tests |

---

## 10. Open Questions

| Question | Status | Notes |
|----------|--------|-------|
| Use `@Observable` or `ObservableObject`? | **Use ObservableObject** | More learning resources |
| Add network reachability monitor? | **Later** | Not critical for MVP |
| Add SwiftLint? | **Optional** | Helpful but adds complexity |
| Pre-optimize ViewModel state? | **No** | Start simple, optimize if needed |
| Use pg_cron for scheduled functions? | **Depends on plan** | Pro plan required |
| APNs auth key vs certificate? | **TBD** | Determine before push function |

---

## Appendix A: SQL Execution Order

Execute in Supabase Dashboard SQL Editor in this order:

1. `001_extensions.sql` - Enable PostgreSQL extensions
2. `002_tables.sql` - Create all 14 tables
3. `003_indexes.sql` - Create performance indexes
4. `004_rls_policies.sql` - Enable RLS and create policies
5. `005_triggers.sql` - Create trigger functions
6. `006_functions.sql` - Create helper functions
7. `007_views.sql` - Create leaderboard view
8. `008_storage.sql` - Create storage buckets
9. `009_seed_data.sql` - Insert test data (dev only)

Complete SQL is provided in `DATABASE-SCHEMA.md`.

---

## Appendix B: Test User Credentials

| Email | Password | Role | Approved |
|-------|----------|------|----------|
| alice@test.com | TestPassword123! | Admin | Yes |
| bob@test.com | TestPassword123! | User | Yes |
| carol@test.com | TestPassword123! | User | Yes |
| dave@test.com | TestPassword123! | User | Yes |
| eve@test.com | TestPassword123! | User | No (pending) |

---

*End of PRD: Foundation Architecture*
