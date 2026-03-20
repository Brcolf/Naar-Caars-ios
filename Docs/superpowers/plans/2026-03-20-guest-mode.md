# Guest Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow unauthenticated users to browse the app in read-only guest mode, satisfying Apple App Store Guideline 5.1.1(v).

**Architecture:** Add `.guest` to `AuthState`, a stored `isGuestMode` flag on `AppState`, and route guests to the same `MainTabView` with conditional rendering. Sensitive data is blurred, account-based actions show a reusable sign-in prompt sheet. Defense in depth: UI gating + ViewModel guards.

**Tech Stack:** SwiftUI, MVVM, Supabase (anon reads only for guests), XCStrings localization.

**Spec:** `Docs/superpowers/specs/2026-03-20-guest-mode-design.md`

**Note:** Per project conventions (CLAUDE.md), tests are not added unless explicitly requested. This plan omits TDD steps accordingly.

**Important pattern note:** Most views modified in this plan do NOT currently have `appState` in their properties. `AppState` is `@Observable` and is injected at the root (`NaarsCarsApp.swift`), so adding `@Environment(AppState.self) private var appState` to any view will work. Every task that references `appState.isGuest` requires this injection. `AppLaunchManager` is `ObservableObject` and is accessed via `AppLaunchManager.shared` — do NOT use `@Environment` for it.

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `NaarsCars/Core/Models/GuestRestrictionReason.swift` | Enum providing contextual titles/messages for the sign-in prompt |
| `NaarsCars/UI/Components/Common/GuestSignInPromptView.swift` | Reusable half-sheet sign-in prompt |
| `NaarsCars/Features/Authentication/Views/GuestProfileView.swift` | Guest's profile tab (identity + CTA + About section) |
| `NaarsCars/Features/Messaging/Views/GuestMessagesView.swift` | Guest's messages tab (empty state + privacy rationale) |

### Modified Files
| File | What Changes |
|------|-------------|
| `NaarsCars/Core/Services/AuthService.swift` | Add `.guest` case to `AuthState` enum |
| `NaarsCars/App/AppState.swift` | Add `isGuestMode` flag + `isGuest` computed property |
| `NaarsCars/App/AppLaunchManager.swift` | Add `enterGuestMode()` + `exitGuestMode()` methods |
| `NaarsCars/App/ContentView.swift` | Route `.guest` to `MainTabView`; verify `isAuthenticated` excludes `.guest` |
| `NaarsCars/Features/Authentication/Views/WelcomeView.swift` | "Continue as Guest" button |
| `NaarsCars/App/MainTabView.swift` | Conditional tabs for messages/profile; guard badge refresh, toasts, prompts |
| `NaarsCars/UI/Components/AddressText.swift` | Add `isBlurred` parameter with blur overlay |
| `NaarsCars/UI/Components/Cards/RideCard.swift` | Pass `isBlurred` to AddressText |
| `NaarsCars/UI/Components/Cards/FavorCard.swift` | Pass `isBlurred` to AddressText |
| `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift` | Relax `.open` guard for nil userId |
| `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift` | Guard realtime subscription for guests |
| `NaarsCars/Features/Rides/Views/RideDetailView.swift` | Blur addresses, hide map, gate actions |
| `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift` | Guard Q&A methods |
| `NaarsCars/Features/Claiming/ViewModels/ClaimViewModel.swift` | Guard `claim()` + `unclaim()` for guests |
| `NaarsCars/Features/Favors/Views/FavorDetailView.swift` | Blur addresses, gate actions |
| `NaarsCars/Features/Favors/ViewModels/FavorDetailViewModel.swift` | Guard Q&A methods |
| `NaarsCars/Features/Rides/Views/CreateRideView.swift` | Guest banner + gate submit |
| `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift` | Guard `createRide()` |
| `NaarsCars/Features/Favors/Views/CreateFavorView.swift` | Guest banner + gate submit |
| `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift` | Guard `createFavor()` |
| `NaarsCars/Features/Profile/Views/PublicProfileView.swift` | Hide phone section, gate message/block |
| `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift` | Gate create/vote/report |
| `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift` | Gate vote actions |
| `NaarsCars/Features/TownHall/Views/PostCommentsView.swift` | Hide input, gate reply/vote/report |
| `NaarsCars/Features/TownHall/ViewModels/CreatePostViewModel.swift` | Guard `validateAndPost()` |
| `NaarsCars/App/NavigationCoordinator.swift` | Guard auth-required intents for guests |
| `NaarsCars/Resources/Localizable.xcstrings` | All new guest mode strings |

---

## Task 1: Auth State Infrastructure

Add `.guest` to the auth state machine and wire up the guest mode flag on `AppState`.

**Files:**
- Modify: `NaarsCars/Core/Services/AuthService.swift` (line ~668: AuthState enum)
- Modify: `NaarsCars/App/AppState.swift` (lines 22-69: properties + computed authState)
- Modify: `NaarsCars/App/AppLaunchManager.swift` (lines 116-170: launch + deferred loading)
- Modify: `NaarsCars/App/ContentView.swift` (lines 20-68: isAuthenticated + switch)

### Steps

- [ ] **Step 1: Add `.guest` case to `AuthState` enum**

In `AuthService.swift`, find the `AuthState` enum (line ~668) and add `.guest`:

```swift
enum AuthState {
    case loading
    case unauthenticated
    case guest            // <-- NEW
    case needsApplication
    case pendingApproval
    case banned
    case authenticated
}
```

- [ ] **Step 2: Add `isGuestMode` flag and `isGuest` computed property to `AppState`**

In `AppState.swift` (which uses `@Observable`, not `ObservableObject`), add after the existing properties (around line 28):

```swift
var isGuestMode: Bool = false
```

Note: `AppState` uses `@Observable`, so use plain `var` — NOT `@Published`.

Add computed property after `authState` (around line 70):

```swift
var isGuest: Bool { isGuestMode }
```

- [ ] **Step 3: Add `enterGuestMode()` and `exitGuestMode()` to `AppLaunchManager`**

In `AppLaunchManager.swift`, add two new methods. `enterGuestMode()` sets the launch state to `.ready(.guest)` and sets `appState.isGuestMode = true` without creating a Supabase session or starting any deferred loading. `exitGuestMode()` sets `appState.isGuestMode = false` and transitions state to `.ready(.unauthenticated)`.

```swift
@MainActor
func enterGuestMode() {
    appState.isGuestMode = true
    state = .ready(.guest)
}

@MainActor
func exitGuestMode() {
    appState.isGuestMode = false
    state = .ready(.unauthenticated)
}
```

- [ ] **Step 4: Route `.guest` in ContentView switch**

In `ContentView.swift`, add the `.guest` case in the `authState` switch (after `.unauthenticated`, before `.needsApplication`):

```swift
case .guest:
    MainTabView()
```

Verify that `isAuthenticated` (line 20-25) does NOT include `.guest` — it should already be excluded since it only checks `.authenticated`, `.pendingApproval`, `.needsApplication`. Confirm no change needed.

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. The new `.guest` case may cause switch exhaustiveness warnings in other files — note them for later tasks.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(guest): add .guest to AuthState, isGuestMode to AppState, enter/exit methods to AppLaunchManager, route in ContentView"
```

---

## Task 2: GuestRestrictionReason Enum + GuestSignInPromptView

Create the shared components used by all guest-gated surfaces.

**Files:**
- Create: `NaarsCars/Core/Models/GuestRestrictionReason.swift`
- Create: `NaarsCars/UI/Components/Common/GuestSignInPromptView.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings` (add keys)

### Steps

- [ ] **Step 1: Create `GuestRestrictionReason.swift`**

```swift
//
//  GuestRestrictionReason.swift
//  NaarsCars
//

import Foundation

/// Contextual reasons shown in the guest sign-in prompt sheet.
enum GuestRestrictionReason {
    case claimRide
    case claimFavor
    case postRide
    case postFavor
    case sendMessage
    case viewMap
    case askQuestion
    case createPost
    case commentOnPost
    case voteOnPost
    case reportContent
    case addParticipants

    var title: String {
        switch self {
        case .claimRide:        return "guest_prompt_title_claim_ride".localized
        case .claimFavor:       return "guest_prompt_title_claim_favor".localized
        case .postRide:         return "guest_prompt_title_post_ride".localized
        case .postFavor:        return "guest_prompt_title_post_favor".localized
        case .sendMessage:      return "guest_prompt_title_send_message".localized
        case .viewMap:          return "guest_prompt_title_view_map".localized
        case .askQuestion:      return "guest_prompt_title_ask_question".localized
        case .createPost:       return "guest_prompt_title_create_post".localized
        case .commentOnPost:    return "guest_prompt_title_comment".localized
        case .voteOnPost:       return "guest_prompt_title_vote".localized
        case .reportContent:    return "guest_prompt_title_report".localized
        case .addParticipants:  return "guest_prompt_title_add_participants".localized
        }
    }

    var message: String {
        switch self {
        case .claimRide:        return "guest_prompt_message_claim_ride".localized
        case .claimFavor:       return "guest_prompt_message_claim_favor".localized
        case .postRide:         return "guest_prompt_message_post_ride".localized
        case .postFavor:        return "guest_prompt_message_post_favor".localized
        case .sendMessage:      return "guest_prompt_message_send_message".localized
        case .viewMap:          return "guest_prompt_message_view_map".localized
        case .askQuestion:      return "guest_prompt_message_ask_question".localized
        case .createPost:       return "guest_prompt_message_create_post".localized
        case .commentOnPost:    return "guest_prompt_message_comment".localized
        case .voteOnPost:       return "guest_prompt_message_vote".localized
        case .reportContent:    return "guest_prompt_message_report".localized
        case .addParticipants:  return "guest_prompt_message_add_participants".localized
        }
    }
}
```

- [ ] **Step 2: Create `GuestSignInPromptView.swift`**

This is a reusable sheet. It accepts a `GuestRestrictionReason` and an `onSignUp`/`onLogIn` callback that triggers the transition out of guest mode.

```swift
//
//  GuestSignInPromptView.swift
//  NaarsCars
//

import SwiftUI

/// Reusable half-sheet prompting guests to sign up or log in.
struct GuestSignInPromptView: View {
    let reason: GuestRestrictionReason
    let onSignUp: () -> Void
    let onLogIn: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(reason.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(reason.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    dismiss()
                    // Delay state transition to avoid tearing down sheet mid-dismissal
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        onSignUp()
                    }
                } label: {
                    Text("guest_prompt_sign_up".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("guestPrompt.signUp")

                Button {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        onLogIn()
                    }
                } label: {
                    Text("guest_prompt_log_in".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("guestPrompt.logIn")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 3: Add all localization keys to `Localizable.xcstrings`**

Add keys for all `GuestRestrictionReason` titles and messages, plus the prompt button labels. The exact format must match the existing xcstrings JSON structure. Keys to add:

Prompt buttons:
- `guest_prompt_sign_up` = "Sign Up"
- `guest_prompt_log_in` = "Log In"

Titles (one per reason):
- `guest_prompt_title_claim_ride` = "Sign In to Claim This Ride"
- `guest_prompt_title_claim_favor` = "Sign In to Claim This Favor"
- `guest_prompt_title_post_ride` = "Sign In to Post a Ride"
- `guest_prompt_title_post_favor` = "Sign In to Post a Favor"
- `guest_prompt_title_send_message` = "Sign In to Send Messages"
- `guest_prompt_title_view_map` = "Sign In to View Map"
- `guest_prompt_title_ask_question` = "Sign In to Ask a Question"
- `guest_prompt_title_create_post` = "Sign In to Create a Post"
- `guest_prompt_title_comment` = "Sign In to Comment"
- `guest_prompt_title_vote` = "Sign In to Vote"
- `guest_prompt_title_report` = "Sign In to Report Content"
- `guest_prompt_title_add_participants` = "Sign In to Add Participants"

Messages (one per reason):
- `guest_prompt_message_claim_ride` = "Create an account to claim rides and help your neighbors get where they need to go."
- `guest_prompt_message_claim_favor` = "Create an account to claim favors and help your neighbors."
- `guest_prompt_message_post_ride` = "Create an account to post ride requests to the community."
- `guest_prompt_message_post_favor` = "Create an account to post favor requests to the community."
- `guest_prompt_message_send_message` = "Create an account to message your neighbors."
- `guest_prompt_message_view_map` = "Create an account to view the full map with pickup and dropoff locations."
- `guest_prompt_message_ask_question` = "Create an account to ask questions about requests."
- `guest_prompt_message_create_post` = "Create an account to post in Town Hall."
- `guest_prompt_message_comment` = "Create an account to join the conversation."
- `guest_prompt_message_vote` = "Create an account to vote on posts and comments."
- `guest_prompt_message_report` = "Create an account to report content."
- `guest_prompt_message_add_participants` = "Create an account to add participants."

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(guest): add GuestRestrictionReason enum and GuestSignInPromptView shared components"
```

---

## Task 3: WelcomeView — "Continue as Guest" Button

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/WelcomeView.swift` (lines ~110-135)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Steps

- [ ] **Step 1: Add "Continue as Guest" button to WelcomeView**

Read the current WelcomeView. After the existing sign-up buttons section and before the "Already have an account?" footer, add a "Continue as Guest" button. The button calls `launchManager.enterGuestMode()`.

The WelcomeView needs access to `AppLaunchManager` — check if it's already available via environment or needs to be injected. Add:

```swift
@EnvironmentObject private var launchManager: AppLaunchManager
// or if @Observable:
@Environment(AppLaunchManager.self) private var launchManager
```

Add the button between the sign-up section and footer:

```swift
Button {
    launchManager.enterGuestMode()
} label: {
    Text("welcome_continue_as_guest".localized)
        .font(.subheadline)
        .foregroundStyle(.secondary)
}
.padding(.top, 8)
.accessibilityIdentifier("welcome.continueAsGuest")
```

- [ ] **Step 2: Add localization key**

- `welcome_continue_as_guest` = "Continue as Guest"

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(guest): add Continue as Guest button to WelcomeView"
```

---

## Task 4: MainTabView — Conditional Tabs and Guards

**Files:**
- Modify: `NaarsCars/App/MainTabView.swift` (lines 22-141: toast overlay, tab view, .task)
- Create: `NaarsCars/Features/Messaging/Views/GuestMessagesView.swift`
- Create: `NaarsCars/Features/Authentication/Views/GuestProfileView.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Steps

- [ ] **Step 1: Create `GuestMessagesView.swift`**

```swift
//
//  GuestMessagesView.swift
//  NaarsCars
//

import SwiftUI

/// Empty state shown to guest users on the Messages tab.
struct GuestMessagesView: View {
    /// AppLaunchManager is ObservableObject, accessed via .shared (not @Environment).
    private let launchManager = AppLaunchManager.shared

    @State private var showSignInPrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("guest_messages_title".localized)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("guest_messages_privacy_rationale".localized)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    showSignInPrompt = true
                } label: {
                    Text("guest_prompt_sign_up".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("guestMessages.signUp")

                Spacer()
            }
            .navigationTitle("messages_title".localized)
            .sheet(isPresented: $showSignInPrompt) {
                GuestSignInPromptView(
                    reason: .sendMessage,
                    onSignUp: { launchManager.exitGuestMode() },
                    onLogIn: { launchManager.exitGuestMode() }
                )
            }
        }
    }
}
```

Localization keys:
- `guest_messages_title` = "Messages"
- `guest_messages_privacy_rationale` = "Messages are private conversations between verified community members. Create an account to start messaging your neighbors."

- [ ] **Step 2: Create `GuestProfileView.swift`**

This view shows a guest identity header, sign-up CTA, and the About section (community guidelines, privacy policy, ToS, contact support). Read `MyProfileView.swift` to find the About section's exact implementation (likely in a `SettingsView` or the bottom of `MyProfileView`) and replicate just that section.

```swift
//
//  GuestProfileView.swift
//  NaarsCars
//

import SwiftUI

/// Profile tab view shown to guest users.
struct GuestProfileView: View {
    /// AppLaunchManager is ObservableObject, accessed via .shared (not @Environment).
    private let launchManager = AppLaunchManager.shared

    @State private var showSignInPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Guest identity header
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text("guest_profile_name".localized)
                            .font(.title2.bold())
                    }
                    .padding(.top, 24)

                    // Sign-up CTA card
                    VStack(spacing: 16) {
                        Text("guest_profile_cta_title".localized)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text("guest_profile_cta_message".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            showSignInPrompt = true
                        } label: {
                            Text("guest_prompt_sign_up".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("guestProfile.signUp")

                        Button {
                            showSignInPrompt = true
                        } label: {
                            Text("guest_prompt_log_in".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("guestProfile.logIn")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // About section — reuse the same links from MyProfileView/SettingsView
                    // Read MyProfileView to find the exact About section implementation
                    // and replicate here. Expected links:
                    // - Community Guidelines
                    // - Privacy Policy
                    // - Terms of Service
                    // - Contact Support
                    aboutSection
                }
            }
            .navigationTitle("guest_profile_title".localized)
            .sheet(isPresented: $showSignInPrompt) {
                GuestSignInPromptView(
                    reason: .sendMessage,
                    onSignUp: { launchManager.exitGuestMode() },
                    onLogIn: { launchManager.exitGuestMode() }
                )
            }
        }
    }

    // MARK: - About Section
    // Implementation note: The About section (community guidelines, privacy
    // policy, ToS, contact support) lives in SettingsView.swift (lines 229-326),
    // NOT in MyProfileView. Read SettingsView.swift and replicate the links here.
    // They use NavigationLink (guidelines), Link (privacy, terms), and a
    // mailto-based contact support pattern.
    @ViewBuilder
    private var aboutSection: some View {
        // Placeholder — replace with About section extracted from SettingsView.swift
        EmptyView()
    }
}
```

Localization keys:
- `guest_profile_name` = "Guest User"
- `guest_profile_title` = "Profile"
- `guest_profile_cta_title` = "Join the Community"
- `guest_profile_cta_message` = "Create an account to post rides and favors, message your neighbors, and join the community."

- [ ] **Step 3: Modify MainTabView**

Read `MainTabView.swift` and make these changes:

a) In the `.task` modifier (line ~132-141), guard badge refresh, prompt coordinator, and guidelines for guests:

```swift
.task {
    guard !appState.isGuest else { return }
    checkGuidelinesAcceptance()
    await badgeManager.refreshAllBadges()
    if let userId = AuthService.shared.currentUserId {
        await promptCoordinator.checkForPendingPrompts(userId: userId)
    }
}
```

b) In the toast overlay (line ~22-45), wrap in a guest check so toasts don't render for guests:

```swift
if !appState.isGuest {
    // existing toast overlay code
}
```

c) In the TabView body, conditionally swap Messages and Profile tabs:

For Messages tab (tab 1):
```swift
// Replace ConversationsListView() with:
if appState.isGuest {
    GuestMessagesView()
} else {
    ConversationsListView()
}
```

For Profile tab (tab 3):
```swift
// Replace MyProfileView() with:
if appState.isGuest {
    GuestProfileView()
} else {
    MyProfileView()
}
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(guest): add GuestMessagesView, GuestProfileView, conditional MainTabView tabs and guards"
```

---

## Task 5: AddressText Blur + Card Updates

**Files:**
- Modify: `NaarsCars/UI/Components/AddressText.swift` (lines 21-65)
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift` (lines 75, 90)
- Modify: `NaarsCars/UI/Components/Cards/FavorCard.swift` (line 80)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Steps

- [ ] **Step 1: Add `isBlurred` parameter to AddressText**

Read `AddressText.swift`. The existing init is `init(_ address: String, font: Font = .naarsBody, foregroundColor: Color = .primary)`. Add `isBlurred: Bool = false` as a new parameter alongside the existing ones. When `isBlurred` is true:
- Apply `.blur(radius: 6)` to the address text
- Disable the context menu (no copy, no open in Maps)
- Overlay a "Sign in to view" label

```swift
// Add parameter alongside existing ones
let isBlurred: Bool

// Update init — preserve existing font and foregroundColor params
init(_ address: String, font: Font = .naarsBody, foregroundColor: Color = .primary, isBlurred: Bool = false) {
    self.address = address
    self.font = font
    self.foregroundColor = foregroundColor
    self.isBlurred = isBlurred
}

// In body, wrap the existing content:
if isBlurred {
    Text(address)
        .blur(radius: 6)
        .overlay {
            Text("guest_address_hidden".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("guest_address_hidden_accessibility".localized)
} else {
    // existing address text with context menu
}
```

Localization keys:
- `guest_address_hidden` = "Sign in to view address"
- `guest_address_hidden_accessibility` = "Address hidden. Sign in to view."

- [ ] **Step 2: Update RideCard to pass `isBlurred`**

Read `RideCard.swift`. The card does NOT currently have `appState` — add `@Environment(AppState.self) private var appState` to the view's properties. (`AppState` is already injected at the root in `NaarsCarsApp.swift`.) Then at lines 75 and 90, change:

```swift
AddressText(ride.pickup, isBlurred: appState.isGuest)
AddressText(ride.destination, isBlurred: appState.isGuest)
```

Check how `appState` is currently accessed in card components — it may be via `@EnvironmentObject` or `@Environment`. Follow the existing pattern.

- [ ] **Step 3: Update FavorCard to pass `isBlurred`**

Read `FavorCard.swift`. Add `@Environment(AppState.self) private var appState` to the view's properties. At line 80, change:

```swift
AddressText(favor.location, isBlurred: appState.isGuest)
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(guest): add blur overlay to AddressText, pass isBlurred from RideCard and FavorCard"
```

---

## Task 6: RequestFilterManager — Relax Guards for Guest

**Files:**
- Modify: `NaarsCars/Features/Requests/ViewModels/RequestFilterManager.swift` (lines 31, 120, 141, 197, 217)
- Modify: `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift` (lines 103-108)

### Steps

- [ ] **Step 1: Update `getFilteredRequests()` (line 31)**

Read `RequestFilterManager.swift`. Change the guard at line 31 from a blanket return to allowing `.open` through:

```swift
// Before:
guard let userId = authService.currentUserId else { return [] }

// After:
let userId = authService.currentUserId
if userId == nil && filter != .open { return [] }
```

Then in the filter logic below (~lines 99-106), handle the nil userId case for `.open`. Note: `isParticipating` is a method on `RequestItem`, called as `$0.isParticipating(userId:)`:

```swift
case .open:
    // userId may be nil for guests — isParticipating always false for guests
    allRequests = allRequests.filter { $0.isUnclaimed && (userId == nil || !$0.isParticipating(userId: userId!)) }
```

- [ ] **Step 2: Update `fetchFilteredRides()` (line 120)**

Same pattern: allow `.open` through when userId is nil, return empty for `.mine`/`.claimed`:

```swift
let userId = authService.currentUserId
if userId == nil && filter != .open { return [] }
```

For the `.open` predicate path (~lines 124-125), it should not reference userId — verify it uses only status and claimedBy predicates.

- [ ] **Step 3: Update `fetchFilteredFavors()` (line 141)**

Same pattern as `fetchFilteredRides()`.

- [ ] **Step 4: Update `filterRidesInMemory()` (line 197)**

Same pattern: allow `.open` through, return empty for `.mine`/`.claimed`.

- [ ] **Step 5: Update `filterFavorsInMemory()` (line 217)**

Same pattern.

- [ ] **Step 6: Guard realtime subscription in RequestsDashboardView**

Read `RequestsDashboardView.swift`. Add `@Environment(AppState.self) private var appState` if not already present. In the `.task` modifier (line ~103-108), preserve the existing `viewModel.setup(modelContext:)` call and add a guest check before realtime:

```swift
.task {
    viewModel.setup(modelContext: modelContext)
    await viewModel.loadRequests()
    if !appState.isGuest {
        viewModel.setupRealtimeSubscription()
    }
}
```

Note: `loadRequests()` does a network fetch and writes to SwiftData — this works for guests via Supabase anon reads. Only the realtime subscription is skipped.

- [ ] **Step 7: Build and verify**

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(guest): relax RequestFilterManager .open guard for guests, skip realtime subscription"
```

---

## Task 7: Ride Detail View — Guest Restrictions

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift`

### Steps

- [ ] **Step 1: Add guest state and prompt to RideDetailView**

Read `RideDetailView.swift`. Add guest-related state:

```swift
@State private var showGuestPrompt = false
@State private var guestRestrictionReason: GuestRestrictionReason = .claimRide
```

Add the sheet at the view level:

```swift
.sheet(isPresented: $showGuestPrompt) {
    GuestSignInPromptView(
        reason: guestRestrictionReason,
        onSignUp: { launchManager.exitGuestMode() },
        onLogIn: { launchManager.exitGuestMode() }
    )
}
```

- [ ] **Step 2: Blur addresses and hide map for guests**

Find all `AddressText` usages for pickup/destination and pass `isBlurred: appState.isGuest`.

Find the `RouteMapView` usage and wrap it:

```swift
if appState.isGuest {
    // Placeholder for map
    VStack(spacing: 12) {
        Image(systemName: "map")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
        Text("guest_map_hidden".localized)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .frame(height: 200)
    .frame(maxWidth: .infinity)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
} else {
    RouteMapView(/* existing params */)
}
```

Localization: `guest_map_hidden` = "Sign in to view map"

- [ ] **Step 3: Gate action buttons for guests**

For the claim button section (~lines 560-563, 789-827): wrap in guest check. If guest, show a button that triggers the prompt:

```swift
if appState.isGuest {
    Button {
        guestRestrictionReason = .claimRide
        showGuestPrompt = true
    } label: {
        Text("guest_prompt_title_claim_ride".localized)
    }
    .buttonStyle(.borderedProminent)
} else {
    // existing claim button
}
```

For "Message participants" (~line 552): same pattern with `.sendMessage` reason.

For Q&A "Ask a question" (~line 540-558): same pattern with `.askQuestion` reason.

Edit/Delete buttons: these should already be hidden since `isPoster` is false for guests. Verify.

- [ ] **Step 4: Add ViewModel guards**

**Important:** Claim methods (`claim()`, `unclaim()`) are NOT on `RideDetailViewModel` — they live on `ClaimViewModel` at `NaarsCars/Features/Claiming/ViewModels/ClaimViewModel.swift`. The claim VM already guards with `guard let claimerId = authService.currentUserId` which returns nil for guests, but the error surfaces as `AppError.notAuthenticated` rather than a guest prompt. The UI-level gate in Step 3 above is the primary protection; the ClaimViewModel guard is belt-and-suspenders.

Read `RideDetailViewModel.swift`. Add early return in `postQuestion()` (~line 73):

```swift
guard AuthService.shared.currentUserId != nil else { return }
```

This uses `AuthService.shared.currentUserId == nil` as a proxy for guest mode in ViewModels, avoiding the need to inject `AppState`.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(guest): blur addresses, hide map, gate actions in RideDetailView"
```

---

## Task 8: Favor Detail View — Guest Restrictions

**Files:**
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`
- Modify: `NaarsCars/Features/Favors/ViewModels/FavorDetailViewModel.swift`

### Steps

- [ ] **Step 1: Mirror RideDetailView changes for FavorDetailView**

Apply the exact same patterns from Task 7:
- Add guest state + prompt sheet
- Blur `AddressText` for location
- Gate claim button, message button, Q&A
- Verify edit/delete hidden via `isPoster`

The only difference: FavorDetailView has no `RouteMapView`, so skip the map placeholder.

- [ ] **Step 2: Add ViewModel guard to FavorDetailViewModel**

Same pattern as RideDetailViewModel: guard `postQuestion()` with `AuthService.shared.currentUserId != nil`. Claim methods live on `ClaimViewModel` (shared with rides).

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(guest): blur addresses, gate actions in FavorDetailView"
```

---

## Task 9: Create Ride / Create Favor — Guest Banner + Gate Submit

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/CreateRideView.swift` (lines ~148-171)
- Modify: `NaarsCars/Features/Rides/ViewModels/CreateRideViewModel.swift` (line ~77)
- Modify: `NaarsCars/Features/Favors/Views/CreateFavorView.swift` (lines ~157-176)
- Modify: `NaarsCars/Features/Favors/ViewModels/CreateFavorViewModel.swift` (line ~75)
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Steps

- [ ] **Step 1: Add guest banner to CreateRideView**

Read `CreateRideView.swift`. Add a banner at the top of the form (inside the `Form` or `ScrollView`, before the first section):

```swift
if appState.isGuest {
    HStack(spacing: 12) {
        Image(systemName: "info.circle.fill")
            .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 4) {
            Text("guest_create_ride_banner_title".localized)
                .font(.subheadline.bold())
            Button("guest_prompt_log_in".localized) {
                guestRestrictionReason = .postRide
                showGuestPrompt = true
            }
            .font(.subheadline)
        }
    }
    .padding()
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal)
}
```

Localization: `guest_create_ride_banner_title` = "Sign in to post this ride"

- [ ] **Step 2: Gate the Post button in CreateRideView**

At the toolbar Post button (~line 148), intercept for guests:

```swift
// In the button action:
if appState.isGuest {
    guestRestrictionReason = .postRide
    showGuestPrompt = true
} else {
    // existing createRide() call
}
```

Add guest prompt state and sheet (same pattern as Task 7).

Also gate "Add participants" button with `.addParticipants` reason.

- [ ] **Step 3: Add ViewModel guard to CreateRideViewModel**

At the top of `createRide()` (~line 77):

```swift
guard AuthService.shared.currentUserId != nil else { return }
```

- [ ] **Step 4: Repeat for CreateFavorView + CreateFavorViewModel**

Same patterns: banner at top, gate Post button, gate participants, guard `createFavor()`.

Localization: `guest_create_favor_banner_title` = "Sign in to post this favor"

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(guest): add guest banners and gate submit on CreateRideView and CreateFavorView"
```

---

## Task 10: PublicProfileView — Hide Phone, Gate Actions

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift` (lines ~150-233, ~261-275)

### Steps

- [ ] **Step 1: Hide phone number section for guests**

Read `PublicProfileView.swift`. Find the phone section (~lines 150-195). Wrap the entire section in a guest check:

```swift
if !appState.isGuest {
    // existing phone section with mask/reveal
}
```

- [ ] **Step 2: Gate "Send Message" button for guests**

Find the send message button (~lines 201-233). For guests, replace with a guest prompt trigger:

```swift
if appState.isGuest {
    Button {
        guestRestrictionReason = .sendMessage
        showGuestPrompt = true
    } label: {
        // Same visual as existing button
        Label("profile_send_message".localized, systemImage: "bubble.left")
    }
} else {
    // existing send message button
}
```

Or simpler: intercept the existing button action for guests.

- [ ] **Step 3: Gate Block/Report menu for guests**

Find the block/report menu (~lines 69-87). Wrap in guest check or redirect to `.reportContent` prompt.

- [ ] **Step 4: Add guest state and prompt sheet**

Same pattern as previous tasks.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(guest): hide phone, gate message/block on PublicProfileView"
```

---

## Task 11: Town Hall — Gate Interactions

**Files:**
- Modify: `NaarsCars/Features/TownHall/Views/TownHallFeedView.swift`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`
- Modify: `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`
- Modify: `NaarsCars/Features/TownHall/ViewModels/CreatePostViewModel.swift`

### Steps

- [ ] **Step 1: Gate create post in TownHallFeedView**

Read `TownHallFeedView.swift`. The create button (~line 25) triggers `showCreatePost = true`. For guests, trigger the prompt instead:

```swift
Button {
    if appState.isGuest {
        guestRestrictionReason = .createPost
        showGuestPrompt = true
    } else {
        showCreatePost = true
    }
} label: {
    Image(systemName: "plus")
}
```

- [ ] **Step 2: Gate vote and report in TownHallFeedView**

The vote handler (~lines 165-169) calls `viewModel.votePost()`. For guests, trigger prompt:

```swift
onVote: { postId, voteType in
    if appState.isGuest {
        guestRestrictionReason = .voteOnPost
        showGuestPrompt = true
    } else {
        Task { await viewModel.votePost(postId: postId, voteType: voteType) }
    }
}
```

- [ ] **Step 3: Gate vote buttons in TownHallPostCard**

Read `TownHallPostCard.swift`. The vote buttons (~lines 283-333) call `onVote?()`. The card itself is presentational and uses callbacks, so the gating in TownHallFeedView (Step 2) should be sufficient. However, verify that `TownHallPostCard` is not used elsewhere without the guard.

If the card is also used standalone, add an `isGuest: Bool` parameter and conditionally disable vote buttons within the card.

- [ ] **Step 4: Gate interactions in PostCommentsView**

Read `PostCommentsView.swift`:

a) Comment input (~lines 77-129): Hide for guests, show a banner instead:

```swift
if appState.isGuest {
    HStack {
        Image(systemName: "lock.fill")
            .foregroundStyle(.secondary)
        Text("guest_comment_banner".localized)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer()
        Button("guest_prompt_log_in".localized) {
            guestRestrictionReason = .commentOnPost
            showGuestPrompt = true
        }
        .font(.subheadline)
    }
    .padding()
} else {
    // existing comment input section
}
```

b) Reply button (~lines 214-231): trigger prompt for guests
c) Vote buttons (~lines 271-321): trigger prompt for guests
d) Report button (~lines 245-266): trigger prompt for guests

Localization: `guest_comment_banner` = "Sign in to join the conversation"

- [ ] **Step 5: Guard PostCommentsViewModel methods**

**Important:** `PostCommentsViewModel` is defined INSIDE `PostCommentsView.swift` (starting around line 400), not as a separate file. The following methods already have `guard let userId = authService.currentUserId else { return }` guards:
- `addComment()` (line ~448)
- `addReply()` (line ~468)
- `voteComment()` (line ~488)
- `deleteComment()` (line ~505)

These guards already prevent guest writes. However, they set an error message that may confuse guests. Verify these guards produce clean behavior when combined with the UI-level gates from Step 4. The UI gates are the primary protection; these VM guards are belt-and-suspenders.

- [ ] **Step 6: Guard `validateAndPost()` in CreatePostViewModel**

Read `CreatePostViewModel.swift`. At line ~67, there's already a guard on `currentUserId` that throws `.notAuthenticated`. This is belt-and-suspenders — the UI gate in Step 1 prevents guests from reaching this code path.

- [ ] **Step 7: Build and verify**

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(guest): gate create/vote/comment/report in Town Hall for guests"
```

---

## Task 12: NavigationCoordinator — Deep Link Guards

**Files:**
- Modify: `NaarsCars/App/NavigationCoordinator.swift`

### Steps

- [ ] **Step 1: Guard auth-required intents**

Read `NavigationCoordinator.swift`. Find where `pendingIntent` is applied/consumed. Before applying an intent, check if it requires auth and the user is a guest.

Add a method or inline check:

Use the actual `NavigationIntent` case names from `NavigationIntent.swift`:

```swift
private func isGuestSafeIntent(_ intent: NavigationIntent) -> Bool {
    switch intent {
    case .openRide, .openFavor, .openTownHallPost, .openProfile, .openDashboard:
        return true
    case .openConversation, .openAdminPanel, .openPendingUsers, .openAdminReports,
         .openAnnouncements, .showReview, .showRequestCompletion:
        return false
    }
}
```

**Note:** Verify these case names against the actual enum in `NavigationIntent.swift` before implementing — the enum uses patterns like `.ride(UUID, anchor:)` not `.openRide`. Adapt the switch to match the actual case names. Guest-safe intents: ride, favor, townHallPost, profile, dashboard, requestListScroll. Auth-required: conversation, adminPanel, pendingUsers, adminReports, announcements, showReview, showRequestCompletion.

When applying the intent, if `appState.isGuest && !isGuestSafeIntent(intent)`, either ignore the intent or show the guest prompt. The exact mechanism depends on how intent is consumed — read the code to determine the right hook point.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(guest): guard auth-required navigation intents for guests"
```

---

## Task 13: Final Localization Pass + Build Verification

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Steps

- [ ] **Step 1: Verify all new strings are in Localizable.xcstrings**

Grep the codebase for all `"guest_` string literals and confirm each has a corresponding entry in `Localizable.xcstrings`.

```bash
grep -rn '"guest_' NaarsCars/ --include='*.swift' | grep -oP '"guest_[^"]+' | sort -u
```

Cross-reference with the keys added in previous tasks. Add any missing keys.

- [ ] **Step 2: Full build verification**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED with no warnings related to guest mode changes.

- [ ] **Step 3: Verify switch exhaustiveness**

After adding `.guest` to `AuthState`, there may be other switch statements throughout the codebase that need updating. Search for them:

```bash
grep -rn 'case .authenticated' NaarsCars/ --include='*.swift' | head -20
```

Ensure every switch on `AuthState` handles `.guest` appropriately — typically alongside `.unauthenticated` or as a separate case.

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "feat(guest): final localization pass and build verification"
```

---

## RLS Prerequisite (Pre-Task 1)

Before starting implementation, verify Supabase RLS SELECT policies allow anon reads. Use the Supabase MCP to check:

```sql
-- Check RLS policies on key tables
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN ('rides', 'favors', 'profiles', 'town_hall_posts', 'town_hall_comments', 'reviews')
AND cmd = 'SELECT';
```

If any policy restricts SELECT to `auth.uid() IS NOT NULL`, a migration is needed before client work begins.

---

## Dependency Graph

```
Task 1 (Auth State)
  └── Task 2 (Shared Components) — depends on AuthState.guest existing
       └── Task 3 (WelcomeView) — depends on enterGuestMode()
            └── Task 4 (MainTabView + Guest Views) — depends on routing working
                 ├── Task 5 (AddressText + Cards) — independent of Task 4
                 ├── Task 6 (RequestFilterManager) — independent of Task 4
                 ├── Task 7 (Ride Detail) — depends on Task 5 (AddressText)
                 ├── Task 8 (Favor Detail) — depends on Task 5 (AddressText)
                 ├── Task 9 (Create Views) — depends on Task 2 (prompt)
                 ├── Task 10 (Public Profile) — depends on Task 2 (prompt)
                 ├── Task 11 (Town Hall) — depends on Task 2 (prompt)
                 └── Task 12 (Navigation) — depends on Task 1 (AuthState)
Task 13 (Localization + Build) — depends on all above
```

Tasks 5-12 can be parallelized after Tasks 1-4 are complete.
