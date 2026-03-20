# Guest Mode / Unauthenticated Browse — Design Spec

> Date: 2026-03-20
> Purpose: Satisfy Apple App Store Guideline 5.1.1(v) by allowing unauthenticated users to browse non-account-based surfaces in a limited, read-only way.
> Status: Approved (pending implementation)

---

## 1. Problem

The app currently hard-gates all content behind authentication. Apple Guideline 5.1.1(v) requires that users can access non-account-based features without registering. The app was rejected under this guideline.

## 2. Solution Overview

Add a `.guest` case to the existing `AuthState` enum and a stored `isGuestMode` flag on `AppState` (since the existing `authState` computed property derives from `currentUser` and cannot produce `.guest` on its own). Guests enter via a "Continue as Guest" button on `WelcomeView`, land in the same `MainTabView` as authenticated users, and browse a read-only version of the app with sensitive data blurred and account-based actions gated behind reusable sign-in prompt sheets.

### Design Principles

- Single auth state check (`appState.isGuest`) — no parallel navigation stacks
- Reuse existing views with conditional rendering — no duplicated flows
- UI gating + ViewModel guards — defense in depth
- No Supabase session, no realtime subscriptions, no sync engines for guests
- Sensitive data (precise addresses, phone numbers, messages) never exposed to guests

---

## 3. Auth State & Routing

### AuthState enum change

```
existing: loading | unauthenticated | needsApplication | pendingApproval | banned | authenticated
new:      loading | unauthenticated | guest | needsApplication | pendingApproval | banned | authenticated
```

### AppState — guest state tracking

`AppState.authState` is a computed property that derives state from `currentUser`. Since `currentUser` is `nil` for guests, `authState` would return `.unauthenticated`, never `.guest`. Therefore, guest state is tracked via a stored flag:

```swift
// AppState.swift
@Published var isGuestMode: Bool = false

var isGuest: Bool { isGuestMode }
```

`AppLaunchManager` sets `appState.isGuestMode = true` when entering guest mode and `false` when transitioning to auth flow. The `LaunchState.ready(.guest)` variant is the source of truth for `ContentView` routing; `appState.isGuestMode` is the source of truth for view/VM guest checks.

`currentUser` remains `nil` for guests. `currentUserId` remains `nil`.

### ContentView routing

```
case .guest -> MainTabView()
```

Guests see the same 4-tab shell as authenticated users. Gating happens inside individual tabs/views.

### WelcomeView

Add a "Continue as Guest" button. On tap, `AppLaunchManager` transitions to `.ready(.guest)`. No Supabase session created. No profile fetched.

### What does NOT start for guests

- No Supabase realtime subscriptions
- No sync engines (messaging, dashboard, town hall)
- No push notification registration
- No badge count fetching (guard `BadgeCountManager.refreshAllBadges()`)
- No profile loading
- No prompt coordinator checks
- No toast overlay / in-app notification rendering
- `AppLaunchManager.performCriticalLaunch()` deferred loading is skipped

### ContentView.isAuthenticated

`ContentView` has a computed `isAuthenticated` property that controls whether `restartRealtimeSyncEngines()`, `recheckBanStatus()`, and `AppLockManager` engage on foreground. `.guest` must NOT be included in this check. Guests must not trigger sync engines, ban checks, or app lock.

### Guest -> Authenticated transition

When a guest taps "Sign Up" or "Log In" from any prompt:
1. Sheet dismisses
2. `AppLaunchManager` sets state to `.ready(.unauthenticated)`
3. `ContentView` routes to `WelcomeView`
4. Normal auth flow proceeds
5. On success, state becomes `.ready(.authenticated)`

Any unsaved form data (e.g., partially filled create ride) is lost. This is acceptable since the guest is warned upfront via banner.

---

## 4. Dashboard / Home Feed

### RequestsDashboardView (unified dashboard)

The dashboard uses `RequestsDashboardView` with `RequestFilterManager` (not the old separate `RidesDashboardViewModel`/`FavorsDashboardViewModel`).

- All three filter tabs visible: Open Requests / My Requests / Claimed Requests (per `RequestFilter` enum: `.open`, `.mine`, `.claimed`)
- "Open Requests" fetches rides/favors from Supabase (public read, no auth required)
- "My Requests" and "Claimed Requests" naturally return empty results (no `currentUserId`) — existing empty state UI renders
- `+` create button remains visible and tappable (guests can open create screens)
- Pull-to-refresh works for "Open Requests" tab

### RequestFilterManager changes

`RequestFilterManager.getFilteredRequests()` currently has `guard let userId = authService.currentUserId else { return [] }` — this returns empty for ALL filters including `.open` when there is no `currentUserId`. The `.open` path must be adjusted to return all open requests even when `currentUserId` is nil. `.mine` and `.claimed` paths continue to return empty naturally.

### Realtime subscriptions

`RequestsDashboardView` calls `viewModel.setupRealtimeSubscription()` in `.task`. For guests, this must be guarded — no realtime channels for unauthenticated users. Guard in the view's `.task` modifier or in the ViewModel method itself.

### Address blurring on cards

- `RideCard`: pickup and destination `AddressText` instances rendered with `isBlurred: true` for guests
- `FavorCard`: location `AddressText` rendered with `isBlurred: true` for guests
- All other card content (poster, status, time, seats, duration, flight info) remains visible

### Map views

- `RequestMapView` is dead code (not shown on dashboard). No changes needed.
- `RouteMapView` in ride detail is handled in Section 5 below.

---

## 5. Ride & Favor Detail Views

### Navigation

Guests tap cards and enter the real `RideDetailView` / `FavorDetailView`. No navigation interception.

### Visible to guests (read-only)

- Poster name/avatar, status badge
- Date, time, seats (rides) / title, description, duration (favors)
- Flight info (rides)
- Notes, gift, requirements
- Q&A section (read-only)
- Participants list (names/avatars only)
- Claimer name/avatar (no contact actions)

### Blurred/hidden for guests

- Pickup and destination addresses: `AddressText(isBlurred: true)`
- `RouteMapView`: replaced with placeholder ("Sign in to view map")

### Gated behind sign-in prompt

- Claim / Unclaim button -> prompt: "Sign in to claim this ride/favor"
- "Message participants" button -> prompt: "Sign in to send messages"
- Q&A "Ask a question" / reply -> prompt: "Sign in to ask a question"
- Edit / Delete: not shown (guest is never the poster; `isPoster` is false when `currentUserId` is nil)

### ViewModel safety

- `RideDetailViewModel` / `FavorDetailViewModel` load data via read fetches — safe for guests
- `isPoster`, `canEdit`, `isClaimer` naturally return `false` when `currentUserId` is nil
- Claim/unclaim methods get early `guard !appState.isGuest` return

---

## 6. Create Ride / Create Favor

### What guests see

- Full form UI — all fields visible and interactable
- Banner at top of form: "Sign in to post this ride" / "Sign in to post this favor" with tappable "Sign In" action

### Submit gating

- "Post" / "Create" toolbar button triggers `GuestSignInPromptView` sheet instead of submitting
- ViewModel `createRide()` / `createFavor()` methods: early `guard !appState.isGuest` return
- No network call, no optimistic insert, no side effects

### Participant picker

- "Add participants" button -> sign-in prompt

---

## 7. Profiles

### Guest's own profile tab: GuestProfileView (new)

- Generic avatar icon, "Guest User" name
- Prominent sign-up/sign-in CTA card
- About section (from existing MyProfileView): community guidelines, privacy policy, terms of service, contact support
- No stats, badges, XP, reviews, settings, admin panel, sign out, delete account

### Public profiles (other users): PublicProfileView

- Visible: name, avatar, car description, rating, fulfilled count, badges, reviews (read-only)
- Hidden: phone number section — entire section hidden for guests (not just disabled)
- Gated: "Send Message" button -> sign-in prompt
- Gated: Block/Report menu -> sign-in prompt

---

## 8. Messages

### Tab behavior

- Messages tab visible in tab bar
- For guests: renders `GuestMessagesView` instead of `ConversationsListView`
- `GuestMessagesView`: styled empty state with messaging icon, "Sign in to message your neighbors", sign-in prompt button
- No conversations loaded, no message previews, no participant data, no service calls

### Other messaging entry points

- "Message participants" on detail views: gated (Section 5)
- "Send Message" on public profiles: gated (Section 7)
- Deep links / push notifications: irrelevant (no push registration for guests)

---

## 9. Town Hall

### Feed view

- `TownHallFeedView` renders for guests — posts visible, scrollable, pull-to-refresh works
- Post cards: author name/avatar, content, images, type badge, vote counts, comment counts, timestamps — all visible

### Gated for guests

- Create post button -> sign-in prompt
- Upvote / Downvote on posts -> sign-in prompt
- Report post -> sign-in prompt
- Delete post: not shown (ownership check)

### Comments (PostCommentsView)

- Guests can open comments sheet and read existing comments
- Visible: comment content, author name/avatar, timestamps, vote counts
- Hidden: comment input field — replaced with "Sign in to comment" banner
- Gated: reply button -> sign-in prompt
- Gated: upvote/downvote on comments -> sign-in prompt
- Gated: report comment -> sign-in prompt
- Delete comment: not shown (ownership check)

### Privacy

Comments display author name and avatar only. No phone, email, or contact info in comment rows. Safe for guest viewing.

---

## 10. Leaderboard

The Community tab (`CommunityTabView`) contains both Town Hall and Leaderboard views.

### Feed view

- `LeaderboardView` renders for guests — rankings, names, avatars, badges, XP visible (all public data)
- Pull-to-refresh works

### Interactions for guests

- Tap a leaderboard entry to view public profile: works (PublicProfileView guest handling per Section 7)
- No leaderboard-specific mutations exist (leaderboard is read-only for all users)

### RLS

`leaderboard_entries` / leaderboard RPCs must allow anon reads (see Section 16 prerequisite).

---

## 11. Deep Link Behavior for Guests

When a guest encounters a deep link (e.g., universal link shared externally), `NavigationCoordinator` processes the `NavigationIntent`. Guest-safe and guest-unsafe intents:

| NavigationIntent | Guest behavior |
|-----------------|----------------|
| `.ride(UUID)` | Navigate to RideDetailView (guest-safe, read-only with blurring) |
| `.favor(UUID)` | Navigate to FavorDetailView (guest-safe, read-only with blurring) |
| `.townHallPost(UUID)` | Navigate to post (guest-safe, read-only) |
| `.profile(UUID)` | Navigate to PublicProfileView (guest-safe, read-only) |
| `.conversation(UUID)` | Show GuestSignInPromptView (requires auth) |
| `.adminPanel` | Ignore / no-op (requires auth + admin role) |
| `.pendingUsers` | Ignore / no-op (requires auth + admin role) |
| `.adminReports` | Ignore / no-op (requires auth + admin role) |
| `.notifications` | Show GuestSignInPromptView (requires auth) |
| `.dashboard` | Navigate to dashboard (guest-safe) |

Guard implementation: `NavigationCoordinator` checks `appState.isGuest` before applying intents that require auth; shows sign-in prompt for those cases.

---

## 12. Shared Components

### GuestSignInPromptView (new reusable sheet)

Half-height sheet containing:
- Icon (lock or community-themed)
- Contextual message (passed in via `GuestRestrictionReason`)
- "Sign Up" button (primary)
- "Log In" button (secondary)
- Dismiss via drag-down or "Not now"

### GuestRestrictionReason enum

```swift
enum GuestRestrictionReason {
    case claimRide, claimFavor, postRide, postFavor
    case sendMessage, viewMap, askQuestion
    case createPost, commentOnPost, voteOnPost
    case reportContent, addParticipants
}
```

Each case provides a `message: String` and `title: String` for the prompt.

### AddressText blurred variant

- New `isBlurred: Bool` parameter (default `false`)
- When true: `.blur(radius: 6)` on text, context menu disabled, "Sign in to view" overlay
- No changes to existing authenticated behavior

### GuestMessagesView (new)

Small self-contained view: empty state icon + "Sign in to message your neighbors" + sign-in button.

### GuestProfileView (new)

Guest identity header + sign-up CTA + About section (community guidelines, privacy policy, ToS, contact support).

---

## 13. Service-Layer Guards

Not a middleware — lightweight ViewModel-level pattern. ViewModels that perform mutations check `appState.isGuest` before calling service methods.

### Guard points

| ViewModel | Guarded methods |
|-----------|----------------|
| CreateRideViewModel | `createRide()` |
| CreateFavorViewModel | `createFavor()` |
| RideDetailViewModel | `claimRide()`, `unclaimRide()` |
| FavorDetailViewModel | `claimFavor()`, `unclaimFavor()` |
| ConversationsListViewModel | `createConversation()` |
| PostCommentsViewModel | `addComment()`, `addReply()`, `vote()`, `deleteComment()` |
| TownHallFeedViewModel | `createPost()`, `votePost()`, `deletePost()` |
| PublicProfileViewModel | `blockUser()`, `reportUser()` |

These are belt-and-suspenders. The UI already gates, but VM guards prevent writes if UI gating is bypassed.

### Network safety

- No Supabase session exists for guests — authenticated RPC calls would fail at the network layer even without guards
- The VM guards provide cleaner error handling (no network error shown to guest, just the sign-in prompt)

---

## 14. Guest Privacy Audit

| Surface | Sensitive Data | Mitigation |
|---------|---------------|------------|
| RideCard | Precise pickup/destination addresses | Blurred via `AddressText(isBlurred: true)` |
| FavorCard | Precise location address | Blurred via `AddressText(isBlurred: true)` |
| RideDetailView | Precise addresses + route map | Addresses blurred, map replaced with placeholder |
| FavorDetailView | Precise location address | Blurred |
| PublicProfileView | Phone number | Entire phone section hidden for guests |
| MyProfileView | Email, personal stats | Guests see `GuestProfileView` instead |
| ConversationsListView | Message previews, participants | Guests see `GuestMessagesView` instead |
| ConversationDetailView | All message content | Not reachable by guests |
| AddressText context menu | Copy address, open in Maps | Disabled when blurred |

---

## 15. New Files

| File | Purpose |
|------|---------|
| `Features/Authentication/Views/GuestProfileView.swift` | Guest's profile tab |
| `Features/Messaging/Views/GuestMessagesView.swift` | Guest's messages tab empty state |
| `Core/Models/GuestRestrictionReason.swift` | Enum for contextual sign-in prompt messages |
| `UI/Components/Common/GuestSignInPromptView.swift` | Reusable sign-in prompt sheet |

## 16. Modified Files

| File | Change |
|------|--------|
| `Core/Services/AuthService.swift` | Add `.guest` case to `AuthState` |
| `App/AppState.swift` | Add `isGuestMode` stored flag and `isGuest` computed property |
| `App/ContentView.swift` | Route `.guest` to `MainTabView()`; ensure `isAuthenticated` excludes `.guest` |
| `App/AppLaunchManager.swift` | `enterGuestMode()` method, skip deferred loading for guests |
| `App/MainTabView.swift` | Conditional tab content for messages/profile; guard `refreshAllBadges()`, toast overlay, prompt coordinator for guests |
| `App/NavigationCoordinator.swift` | Guard auth-required intents for guests (conversation, admin, notifications) |
| `Features/Authentication/Views/WelcomeView.swift` | "Continue as Guest" button |
| `UI/Components/AddressText.swift` | `isBlurred` parameter |
| `UI/Components/Cards/RideCard.swift` | Pass `isBlurred: appState.isGuest` to AddressText |
| `UI/Components/Cards/FavorCard.swift` | Pass `isBlurred: appState.isGuest` to AddressText |
| `Features/Requests/ViewModels/RequestFilterManager.swift` | Allow `.open` filter to return results when `currentUserId` is nil |
| `Features/Requests/Views/RequestsDashboardView.swift` | Guard realtime subscription setup for guests |
| `Features/Rides/Views/RideDetailView.swift` | Blur addresses, hide map, gate actions |
| `Features/Favors/Views/FavorDetailView.swift` | Blur addresses, gate actions |
| `Features/Rides/Views/CreateRideView.swift` | Guest banner, gate submit |
| `Features/Favors/Views/CreateFavorView.swift` | Guest banner, gate submit |
| `Features/Rides/ViewModels/RideDetailViewModel.swift` | Guard claim methods |
| `Features/Favors/ViewModels/FavorDetailViewModel.swift` | Guard claim methods |
| `Features/Rides/ViewModels/CreateRideViewModel.swift` | Guard create method |
| `Features/Favors/ViewModels/CreateFavorViewModel.swift` | Guard create method |
| `Features/Profile/Views/PublicProfileView.swift` | Hide phone, gate message/block |
| `Features/TownHall/Views/TownHallFeedView.swift` | Gate create/vote/report |
| `Features/TownHall/Views/TownHallPostCard.swift` | Gate vote actions |
| `Features/TownHall/Views/PostCommentsView.swift` | Hide input, gate reply/vote/report |
| `Resources/Localizable.xcstrings` | New localization keys for guest mode strings |

---

## 17. App Store Review Notes (Draft)

> Naar's Cars supports guest browsing for users who have not created an account. On launch, users can tap "Continue as Guest" to browse the app without signing in.
>
> Guest users can:
> - Browse the ride and favor request feeds
> - View Town Hall community posts and comments
> - View the community leaderboard
> - View public user profiles
> - Explore the create ride and create favor forms
>
> Guest users cannot:
> - View precise pickup/dropoff addresses (shown as blurred)
> - Send or read messages
> - Post rides, favors, or Town Hall content
> - Claim requests, comment, vote, or interact with other members
> - View phone numbers or private contact information
>
> All account-based actions prompt the guest to sign up or log in. Private data such as addresses, phone numbers, and messages are never exposed to unauthenticated users.

---

## 18. Prerequisite: RLS Policy Verification

Before any client-side implementation, verify that Supabase RLS SELECT policies on the following tables allow `anon` key reads (no `auth.uid() IS NOT NULL` restriction on SELECT):

- `rides`
- `favors`
- `profiles`
- `town_hall_posts`
- `town_hall_comments`
- `reviews`
- Leaderboard RPCs / underlying tables

If any of these restrict reads to authenticated users, add a migration to update policies before client work begins. This is a hard prerequisite — without it, every guest fetch returns empty arrays or 403 errors.

---

## 19. Architectural Risks & Edge Cases

1. **SwiftData cache for guests**: If sync engines are skipped, SwiftData queries (`@Query`) will return empty results. Dashboard and Town Hall views will rely on direct Supabase fetches via their respective services/repositories. The local SwiftData cache will be empty for guests and this is correct — do not attempt to "fix" the empty local cache.

2. **Deep link handling for guests**: Covered in Section 11. Guest-safe intents navigate normally; auth-required intents show sign-in prompt.

3. **Guest state persistence**: If the app is killed and relaunched, guest state is not persisted (no session). The app returns to `WelcomeView`. This is acceptable — guests re-tap "Continue as Guest" to re-enter.

4. **Tab badge counts**: `BadgeCountManager.refreshAllBadges()` is guarded for guests (Section 3). Badge counts are zero. No badge fetch errors since the call is skipped entirely.

5. **Analytics / screen tracking**: Several views use `.trackScreen()`. Guest screen views will fire but without a userId. This is acceptable for aggregate analytics but should be noted if per-user tracking is relied upon.
