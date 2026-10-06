# Naar's Cars Design System

The rules the iOS app's interface follows, and the tokens and components that carry them. Updated 2026-10-06 after the uniformity pass on branch `claude/quirky-gates-4bkmv4`; the state before that pass is recorded in [section 7](#7-what-the-2026-10-06-pass-changed).

- **Source of truth in code:** `NaarsCars/UI/Styles/ColorTheme.swift`, `NaarsCars/UI/Styles/Typography.swift`, `NaarsCars/Core/Utilities/Constants.swift`, `NaarsCars/Core/Extensions/View+Extensions.swift`, and the components under `NaarsCars/UI/Components/`.
- **Machine-readable tokens:** [`tokens.json`](tokens.json).
- **Visual reference:** the [Naar's Cars Design System canvas](https://claude.ai/artifact/2N48DgL9TW9jb43zB5iX8J) (private to the owner until shared).
- **Counts** come from `scripts/design-token-audit.sh`.

## Contents

1. [Principles](#1-principles)
2. [Foundations](#2-foundations)
3. [Components](#3-components)
4. [Screen patterns](#4-screen-patterns)
5. [Rules for new UI](#5-rules-for-new-ui)
6. [Open items](#6-open-items)
7. [What the 2026-10-06 pass changed](#7-what-the-2026-10-06-pass-changed)
8. [Method](#8-method)

---

## 1. Principles

1. **Native first.** The app sits inside iOS 26: system type, system grouped surfaces, capsule controls, and the system's glass for anything that floats. Terracotta is the one brand accent.
2. **One meaning, one treatment.** A count, a status, a destructive action, a ride, a favor and a card each have exactly one token or component. If a second way to draw one appears, it is a bug.
3. **Color carries meaning.** Red means an error, a destructive action or an unread count, and nothing else. Status colors pass 4.5 : 1 as text. Decoration uses the neutral grays.
4. **Content is opaque, chrome is glass.** Cards and rows are flat, opaque surfaces. Glass is for transient or floating elements only: toasts, banners, the system bars.
5. **Tokens for anything repeated.** Radius, elevation and motion come from tokens. Spacing sits on a 4-pt grid.
6. **Messaging follows iMessage.** The thread is outside this system's reach except for its colors; see `CLAUDE.md`.

---

## 2. Foundations

### 2.1 Color

Defined in `UI/Styles/ColorTheme.swift`. No hex or RGB literal exists outside that file.

**Brand and meaning**

| Token | Light | Dark | Use | Contrast on white |
|---|---|---|---|---|
| `naarsPrimary` | `#A35944` | `#C97A64` | Primary buttons, tint, links, own message bubbles, avatar initials, selected states | 5.2 |
| `naarsSuccess` | `#137A39` | `#34D669` | Open status, confirmations, pickup dot | 5.4 |
| `naarsWarning` | `#A35200` | `#FBBF24` | Pending status, cautions | 5.6 |
| `naarsError` | `#C62828` | `#F87171` | Errors, validation, destructive actions | 5.6 |
| `naarsBadge` | `#D32F2F` | `#D32F2F` | Fill of the unread-count badge (white text 5.0) | |
| `naarsRating` | `#C2780A` | `#FBBF24` | Rating stars | 3.5 (graphic) |
| `rideAccent` | `#1D5FD6` | `#6EA8FF` | Rides: card stripe, detail headers, route line, map pin | 5.7 |
| `favorAccent` | `#0F766E` | `#2DD4BF` | Favors: card stripe, detail headers, map pin | 5.5 |
| `naarsAccent` | `#D4A574` | `#E0B88A` | One decorative icon in Community Guidelines. Too light for text or meaningful icons | 2.2 |

**Surfaces**

| Token | Resolves to | Light | Dark | Use |
|---|---|---|---|---|
| `naarsBackground` | `systemGroupedBackground` | `#F2F2F7` | `#000000` | The ground of every scrolling screen |
| `naarsCardBackground` | `secondarySystemGroupedBackground` | `#FFFFFF` | `#1C1C1E` | Cards and rows |
| `naarsBackgroundSecondary` | `secondarySystemGroupedBackground` | `#FFFFFF` | `#1C1C1E` | Same surface; pinned headers and legacy call sites |
| `naarsInsetBackground` | `tertiarySystemGroupedBackground` | `#F2F2F7` | `#2C2C2E` | A block nested inside a card; unselected tiles and chips |
| `naarsOverlay` | | black 50% | black 70% | Modal scrim |

Because the surfaces are system colors they pick up the elevated variants inside sheets on their own.

**Text and lines**

| Token | Resolves to | Use |
|---|---|---|
| `naarsTextPrimary` | `label` | Same as `.primary` |
| `naarsTextSecondary` | `secondaryLabel` | Same as `.secondary`; the neutral chip and "completed" status |
| `naarsTextTertiary` | `tertiaryLabel` | Placeholders only; too faint for reading text |
| `naarsDivider`, `naarsBorder` | `separator` | Rules and hairline strokes |
| `naarsDisabled` | `systemGray5` | Fill of a disabled or non-interactive control |
| `naarsDisabledContent` | `tertiaryLabel` | Label and stroke on a disabled control |

Views write `.primary` and `.secondary` directly (about 440 times). That is the convention; the text tokens resolve to the same colors.

**Status mapping** (`RideStatus.color`, `FavorStatus.color`): open → `naarsSuccess`, pending → `naarsWarning`, confirmed (shown as "Claimed") → `naarsPrimary`, completed → `naarsTextSecondary`.

**Tints.** A color at 12% is the fill behind text of the same color (chips, highlighted rows). `naarsPrimary` at 5% marks an unread notification row.

**Asset catalog.** `AccentColor` matches `naarsPrimary` (`#A35944` / `#C97A64`). `LaunchBackground` is `#FFFFFF` / `#1C1C1E`.

**Known limit.** White text on the dark-mode `naarsPrimary` fill is 3.3 : 1. That clears the 3 : 1 bar for the 17 pt semibold button label but not for body-size text in own message bubbles. A darker dark-mode fill would fail as link text on dark surfaces, so fixing it needs separate fill and foreground tokens.

### 2.2 Typography

Defined in `UI/Styles/Typography.swift`. One family (SF Pro) through the system text styles; every token scales with Dynamic Type.

| Token | System style | Size / leading | Uses |
|---|---|---|---|
| `naarsLargeTitle` | `largeTitle`, bold | 34 / 41 | 0 |
| `naarsTitle` | `title`, semibold | 28 / 34 | 6 |
| `naarsTitle2` | `title2`, semibold | 22 / 28 | 38 |
| `naarsTitle3` | `title3`, semibold | 20 / 25 | 40 |
| `naarsHeadline` | `headline` | 17 / 22 | 84 |
| `naarsBody` | `body` | 17 / 22 | 109 |
| `naarsCallout` | `callout` | 16 / 21 | 6 |
| `naarsSubheadline` | `subheadline` | 15 / 20 | 70 |
| `naarsFootnote` | `footnote` | 13 / 18 | 24 |
| `naarsCaption` | `caption` | 12 / 16 | 288 |
| `naarsCaption2` | `caption2` | 11 / 13 | count badges, chip icons |

- Outside the messaging components, 5 raw system styles remain (`.largeTitle` twice, `.title2` three times), where the token's semibold weight would change the look.
- 51 fixed `.system(size:)` calls remain: SF Symbol glyphs in empty and error states (48, 60, 64 pt) and avatar initials.
- UIKit message cells use `preferredFont(forTextStyle:)`.
- 13 `dynamicTypeSize.isAccessibilitySize` branches switch rows to stacks at accessibility sizes.

### 2.3 Spacing

`Constants.Spacing`, on a 4-pt grid:

| Token | Value | Use |
|---|---|---|
| `xxs` | 2 | Between a value and its unit, or two lines of one label |
| `xs` | 4 | Title to caption |
| `sm` | 8 | Icon to label |
| `ms` | 12 | Between groups inside a card or row |
| `md` | 16 | Screen margin, card padding, space between cards |
| `lg` | 24 | Between sections |
| `xl` | 32 | Large breaks |

Literals on the grid (4, 8, 12, 16, 24, 32) are accepted in existing code; they were not rewritten. New code uses the tokens. Avoid 6, 10, 14 and 20.

### 2.4 Shape

`Constants.Radius`:

| Token | Value | Use | Uses |
|---|---|---|---|
| `xs` | 4 | Skeleton lines, hairline shapes | 23 |
| `sm` | 8 | Elements nested in a card: images, inset blocks, row highlights | 30 |
| `md` | 12 | Tiles, inputs that are not capsules | 5 |
| `card` | 16 | Cards and any free-standing container | 79 |
| `button` | 27 | Full-width buttons, toasts, the offline notice | |

**Capsules** are the shape of chips, badges, `NaarsTextField` and Sign in with Apple. Full-width buttons (`PrimaryButton`, `SecondaryButton`, `ClaimButton`) and the glass toasts use `Radius.button`, which is half the height of a one-line button: it draws as a capsule, and when a title wraps at large text sizes it becomes a rounded box instead of a capsule that cuts into the text. **Circles** are avatars and icon wells.

No radius literal remains outside the messaging components.

### 2.5 Elevation and materials

Two elevations, both in `View+Extensions.swift`:

| Modifier | Recipe | Use |
|---|---|---|
| `.cardShadow()` | black 6%, radius 6, y 2 | Cards at rest. Invisible in dark mode by design. |
| `.floatingShadow()` | black 16%, radius 10, y 4 | Anything opaque that floats |

`.cardStyle()` is the whole card recipe (16 pt padding, card surface, `Radius.card`, `cardShadow`); `.cardSurface()` is the same without padding.

**Liquid Glass** (`.glassEffect`) is used on five surfaces, all transient or floating: `ToastView`, `ErrorBanner`, the offline notice, the address-copied toast, and the map's count chip. The tab bar, navigation bars, toolbar buttons and sheets get glass from the system. Cards never do.

The message composer and overlay still use `UIBlurEffect`; they belong to the messaging path.

### 2.6 Motion and haptics

`Animation` extension in `View+Extensions.swift`:

| Token | Curve | Use |
|---|---|---|
| `.naarsStandard` | spring, response 0.3, damping 0.8 | State changes, banners, expand and collapse |
| `.naarsQuick` | ease-out, 0.2 s | Dismissals and fades |
| `.naarsPress` | spring, response 0.2, damping 0.7 | Button press (`ScaleButtonStyle`, scale 0.96) |

`Constants.Animation` still holds the raw durations (0.2, 0.3, 0.5).

Haptics go through `HapticManager`: `lightImpact` on button taps, `selectionChanged` on pickers and tiles, `success` on confirmations, `error` on failures.

### 2.7 Iconography and imagery

- **SF Symbols only**, sized with text styles, monochrome. Filled variants mark filled states.
- **Toolbar icons stay monochrome**, as the system draws them. The tab bar's selected item carries the brand tint. Do not add a root-level `.tint`: on iOS 26 it recolors every toolbar item and bar button.
- **Toggles keep the system green.** iOS 26 switches ignore `UISwitch.appearance()`, so a brand tint would have to be applied form by form; the system color is used everywhere instead.
- **Illustrations:** `NaarsLogo`, `NaarsTextLogo`, four empty-state illustrations and `SupremeLeader`, all raster images in a retro cartoon style.
- **Emoji as UI:** leaderboard medals, avatar achievement badges, and the six tapbacks.

---

## 3. Components

Paths are relative to `NaarsCars/`.

### 3.1 Buttons and controls

| Component | File | Spec |
|---|---|---|
| `PrimaryButton` | `UI/Components/Buttons/PrimaryButton.swift` | Full-width capsule, 16 pt padding (54 pt tall), `naarsHeadline` white on `naarsPrimary`. Loading: spinner, 70% opacity. Disabled: `naarsDisabled` fill, `naarsDisabledContent` label. |
| `SecondaryButton` | `UI/Components/Buttons/SecondaryButton.swift` | Same box, clear fill, 1.5 pt stroke and label in `naarsPrimary`. `isDestructive: true` draws it in `naarsError`. |
| `ClaimButton` | `UI/Components/Buttons/ClaimButton.swift` | canClaim: primary look. claimedByMe ("Unclaim"): secondary look. claimedByOther, completed, isPoster: a flat `naarsDisabled` capsule with secondary text, not interactive. |
| `ScaleButtonStyle` | `UI/Modifiers/ScaleButtonStyle.swift` | `.buttonStyle(.scale)`; all three buttons use it. |
| Sign in with Apple | `Features/Authentication/Views/AppleSignInButton.swift` | System button, 54 pt, clipped to a capsule. |
| System prominent | | Compact inline actions use `.borderedProminent`. Full-width ones add `.buttonBorderShape(.capsule)` and `.controlSize(.large)`. |
| `FilterTile` | `Features/Requests/Views/RequestsDashboardView.swift` | Three equal tiles, `Radius.md`. Selected: `naarsPrimary` with white text. Unselected: `naarsInsetBackground`. |
| `FilterChip` | `UI/Components/Map/FilterBar.swift` | Capsule. Selected: `rideAccent` or `favorAccent`. |

### 3.2 Labels

| Component | File | Spec |
|---|---|---|
| `NaarsChip` | `UI/Components/Common/NotificationBadge.swift` | Short label on a capsule: caption semibold in a tint, on that tint at 12%. `tint: nil` is neutral. `size: .large` for detail-screen headers. Used for request status, post type, invite state and admin tags. |
| `NotificationBadge` | same file | The one count badge: white `naarsCaption2` semibold on `naarsBadge`. `style: .muted` for a muted conversation. `cap:` sets where "N+" starts. Used on cards, filter tiles, the bell and conversation rows. |

### 3.3 Inputs

| Component | File | Spec |
|---|---|---|
| `NaarsTextField` | `UI/Components/Inputs/NaarsTextField.swift` | Capsule, 56 pt, `tertiarySystemFill`. Focus: 1.5 pt `naarsPrimary` 30% stroke. Error: `naarsError` 30% stroke and a caption below. |
| `LocationAutocompleteField` | `UI/Components/Inputs/LocationAutocompleteField.swift` | Address entry with suggestions; `Radius.md`. |
| System `Form` rows | | Create, edit and settings screens use plain system forms. |

### 3.4 Cards and rows

Every card: `naarsCardBackground`, `Radius.card`, 16 pt padding, `cardShadow`.

| Component | File | Notes |
|---|---|---|
| `RideCard`, `FavorCard` | `UI/Components/Cards/` | 4 pt leading stripe in the type color. Header: avatar, name, date, `NotificationBadge`, status `NaarsChip`. |
| `TownHallPostCard` | `Features/TownHall/Views/TownHallPostCard.swift` | Announcements add a 2 pt `naarsPrimary` 60% stroke. Type tags are chips. An active vote is `naarsPrimary`. |
| `ReviewCard`, `InviteCodeCard` | `UI/Components/Cards/` | |
| `ProfileStatsCard` | `UI/Components/Common/ProfileStatsCard.swift` | Four tappable stats. |
| `SpotlightCard`, `LeaderboardRow` | `Features/Leaderboards/Views/` | The current user's row gets `naarsPrimary` at 10%. |
| `NotificationRow` | `Features/Notifications/Views/NotificationRow.swift` | Unread: `naarsPrimary` 5% fill and an 8 pt dot. |
| `ConversationRow` | `Features/Messaging/Views/ConversationRow.swift` | 56 pt avatar, title (semibold when unread), two-line preview, `NotificationBadge`. |

A block nested inside a card uses `naarsInsetBackground` and `Radius.sm`.

### 3.5 Feedback

| Component | File | Spec |
|---|---|---|
| `ToastView` / `.toast(message:)` | `UI/Components/Feedback/ToastView.swift` | Glass capsule at the top. Icon in the status color, message in the label color. Stays 2 s plus reading time per character (up to 8 s; three times longer under VoiceOver) and is announced to VoiceOver. The haptic follows the style: success, warning, or none for info. |
| `ErrorBanner` / `.errorBanner(message:)` | `UI/Components/Feedback/ErrorBanner.swift` | Glass, `Radius.card`. Icon in the status color, Retry in `naarsPrimary`, a dismiss button. |
| Offline notice | `Core/Utilities/NetworkMonitor.swift` | Glass capsule with a `naarsError` icon. Does not take touches, so the navigation bar under it stays usable; going offline and coming back are announced. |
| `EmptyStateView` | `UI/Components/Feedback/EmptyStateView.swift` | Symbol or illustration, title3, body, optional `PrimaryButton`. |
| `ErrorView` | `UI/Components/Feedback/ErrorView.swift` | Full-screen error with Retry. |
| Skeleton rows | `UI/Components/Feedback/Skeleton*.swift` | Preferred over a spinner on list surfaces. |
| `SuccessCheckmark`, `LoadingView` | `UI/Components/Feedback/` | `LoadingView(isEmbedded: true)` draws no surface of its own, for use inside a screen that already has a background. Both stop animating under Reduce Motion. |
| `AccessibilityAnnouncer.announce(_:)` | `Core/Extensions/View+Extensions.swift` | Speaks a transient status change to VoiceOver. Toasts, banners, the checkmark and the offline notice already call it. |

### 3.6 Identity

| Component | File | Spec |
|---|---|---|
| `AvatarView` | `UI/Components/Common/AvatarView.swift` | Photo, or white initials on `naarsPrimary`. Sizes in use: 24, 28, 40, 44, 56, 100. |
| `StarRatingView`, `StarRatingInput` | `UI/Components/Common/` | `naarsRating` stars. |

### 3.7 Messaging (UIKit)

36 files under `UI/Components/Messaging/`. iMessage is the reference. This pass changed only what flows through tokens: own bubbles take the new `naarsPrimary`, and system-message pills take the unified card surface. Layout, radii, blur and reactions are as they were. Reaction badges stay at the top of the bubble.

---

## 4. Screen patterns

- **Navigation.** Four tabs: Requests, Messages, Community, Profile. Each root is a `NavigationStack` with a large title, the bell at the trailing edge and one primary action.
- **Ground.** Every scrolling screen sits on `naarsBackground`, including the ride and favor detail screens, the public profile and past requests.
- **Bodies.** A `ScrollView` of cards (Requests, Town Hall, Profile, details), a plain `List` (conversations, notifications), or a system `Form` (create, edit, settings).
- **Detail screens.** Status chip and poster, one card per topic with a title3 header, then actions: primary first, secondary after, destructive drawn in `naarsError`.
- **Profile rows.** A tinted icon, a label in the label color, a chevron.
- **States.** Skeleton rows while loading lists, `EmptyStateView` when empty, `ErrorView` or the banner on failure, pull to refresh.
- **Dark mode.** Every token has a dark value; cards are one surface.
- **Dynamic Type.** Verified on Requests at the largest accessibility size: tiles stack and chips wrap under the header.

---

## 5. Rules for new UI

| If you need | Use | Not |
|---|---|---|
| A color | A token from `ColorTheme.swift` | A hex literal, `Color.red`, `.blue`, `.orange`, `.green`, `.yellow` |
| Brand tint | `Color.naarsPrimary` | `Color.accentColor` |
| Text color | `.primary`, `.secondary` | A new gray; white on a status color |
| Something destructive | `naarsError`; `SecondaryButton(isDestructive: true)` | |
| A ride or a favor | `rideAccent`, `favorAccent` | Any other color for the type |
| A screen background | `Color.naarsBackground` | Leaving the default white |
| A card | `.cardStyle()` | A hand-built background, radius and shadow |
| A block inside a card | `naarsInsetBackground`, `Radius.sm` | The card surface again |
| A corner radius | `Constants.Radius` | A number |
| A shadow | `.cardShadow()` or `.floatingShadow()` | `.shadow(color:radius:)` |
| An animation | `.naarsStandard`, `.naarsQuick` | A spring or ease typed out |
| Text | A `naars*` font token | `.system(size:)`, raw `.font(.caption)` |
| Spacing | `Constants.Spacing` | 6, 10, 14, 20 |
| A full-width action | `PrimaryButton`, `SecondaryButton` | A hand-built button, a second filled button beside the first |
| A status, tag or state label | `NaarsChip` | A solid pill with white text |
| A count | `NotificationBadge`, placed on the corner of what it counts (`.overlay(alignment: .topTrailing)`) | An inline capsule; a badge laid over the label |
| A success | `.toast(message:)` | |
| A failure | `.errorBanner(message:)`, or `.toast(message:style: .warning)` inside a sheet | The success toast; a colored bar; replacing content that is already on screen with a full-screen error |
| A list whose refresh failed | Keep the rows and show `ErrorBanner` with Retry; `ErrorView` only when there is nothing to show | |
| A form with typed input | Ask before discarding (`confirmationDialog` plus `.interactiveDismissDisabled`); clear a field only after its send succeeds | |
| A full-screen prompt | Give it a way out and a visible failure state | A cover that can only be answered |
| A view that is pushed | Plain content; the presenting sheet supplies the `NavigationStack` | A `NavigationStack` inside a pushed view |
| Something that floats | `.glassEffect` | `.ultraThinMaterial`; glass on a card |
| Haptics | `HapticManager` | A UIKit generator |

Every interactive element needs an `accessibilityLabel` and a 44-pt target (`.frame(minWidth: 44, minHeight: 44)` plus `.contentShape`, inside the button's label); state must not rest on color alone (vote arrows change shape as well as tint). User-facing strings go through `.localized`, which shows the English text when a language has no entry yet; a string that needs a count gets one key per form (`ride_seats_count_one` / `_other`), not an appended "s".

---

## 6. Open items

| # | Item | Why it is open |
|---|---|---|
| 1 | Brand artwork | The app icon, the logo and the interface are three styles. The logo ribbon reads "COMMUINITY", the wordmark reads "CAR'S", and the cartoon cars and caricature deserve a rights and likeness check. A brand decision, not a code change. |
| 2 | Loading and launch logo | The logo's cream square shows on the white ground. Changing it means regenerating `LaunchLogo` to match. |
| 3 | White on dark-mode `naarsPrimary` | 3.3 : 1; see 2.1. Needs separate fill and foreground tokens. |
| 4 | Translations | The hardcoded English found in both passes now lives in the catalog, but 367 keys have English only and display in English in every language. |
| 5 | Spinners | `ProgressView` appears 63 times; skeleton rows exist for five surfaces. |
| 6 | Raw text fields | `NaarsTextField` is used only in authentication; forms elsewhere use system rows, which is fine, but a few sheets hand-style a `TextField`. |
| 7 | Twelve-point text | `naarsCaption` is 43% of all text tokens. A hierarchy pass on cards would help scanning. |
| 8 | Messaging | Still holds its own radii, `UIBlurEffect`, `systemBlue` reaction tint and 13 animation curves, by design. |
| 9 | Haptics | `Core/Utilities/Haptics.swift` duplicates `HapticManager`, and about 11 call sites still create generators directly. |
| 10 | Duplicate assets | Several 2.4 MB PNGs are stored twice under different names. |
| 11 | Emoji medals and badges | Platform emoji render differently from the rest of the iconography. |

---

## 6a. What the 2026-10-06 QA pass added

The functional and design QA pass that followed the uniformity pass (`Docs/qa/2026-10-06-functional-design-qa-pass.md`) changed these parts of the system:

- `Constants.Radius.button` (27) for full-width buttons and glass toasts, replacing true capsules that clipped wrapped titles.
- `Color.naarsBadgeMuted` (`#6E6E73`) for the muted count badge; white on `Color.secondary` was 3.4 : 1.
- `AccessibilityAnnouncer`, toast timing that scales with message length, Reduce Motion in the loading components, `LoadingView(isEmbedded:)`.
- The rules added to section 5: failures never use the success toast, lists keep their content when a refresh fails, forms protect typed input, prompts can be closed, pushed views do not own a stack, badges sit on a corner.
- Vote arrows use `arrowshape.up` / `.down` and their `.fill` variants; link-preview cards in messages use one neutral surface in both directions.
- One invalid SF Symbol name was found (`rocket.fill`); every symbol name in the app was then checked against the system catalog.

The canvas boards still show true capsules for the full-width buttons; at one line the two shapes look the same.

---

## 7. What the 2026-10-06 pass changed

107 files, all view-layer. No service, view model, sync, navigation or schema logic changed.

| Before | After |
|---|---|
| `naarsPrimary` `#B5634B`, 4.3 : 1 on white | `#A35944`, 5.2 : 1. `AccentColor` updated to match. |
| Status pills: white on green (2.3 : 1) and amber (2.2 : 1) | `NaarsChip`: status color as text on a 12% tint; light values darkened to pass 4.5 : 1 |
| `rideAccent` was the same red as `naarsError` | Rides are blue, on cards, detail headers, the route line and map pins |
| Map used `.blue` and `.orange` for rides and favors | Map uses `rideAccent` and `favorAccent` |
| Two card surfaces that differed in dark mode | One surface; `naarsInsetBackground` for nested blocks |
| Three unread badges; `NotificationBadge` had no call sites | One `NotificationBadge`, used in five places |
| Buttons radius 10, Apple button 12, fields capsule, chips 20 | All capsules |
| `ClaimButton`: amber "Unclaim", gray disabled buttons, its own haptics | Primary, secondary and neutral looks; shared haptics and press style |
| "Delete" drawn like "Edit" | `SecondaryButton(isDestructive: true)` |
| 16 radii written inline | `Constants.Radius` (4 values); cards 12 → 16 |
| 9 shadow recipes; card shadow glowed white in dark mode | `.cardShadow()`, `.floatingShadow()` |
| Text tokens with their own grays, used 10 times | Text tokens alias the system label colors |
| `.red` 29, `.orange` 16, `.green` 13, `.blue` 8, `.yellow` 5, `.accentColor` 23 | Semantic tokens. What remains is in the messaging components, the unused debug view, and one admin category color. |
| Toasts and banners: white text on status fills | Neutral glass with a colored icon |
| No Liquid Glass on custom surfaces | Five floating surfaces use `.glassEffect` |
| Detail screens, public profile, past requests on plain white | On `naarsBackground` |
| Raw `.font(.caption)` and similar, 75 | 5 remain outside messaging |
| Profile link rows tinted like links; badge section narrower than the rest | Label-colored rows; equal widths |
| Town Hall post with no body drew two dividers | One divider |
| Long names wrapped under "Claimed by" and in spotlight rows | Line-limited |
| One toggle tinted by hand | All toggles system green |

**Verification.** Built headless with Xcode 26.6 (exit 0, no new warnings); test targets compile. Checked in the iPhone 16 simulator on iOS 26.5, signed in: Requests, a ride detail, Town Hall and Profile in light and dark; Settings in dark; Requests at the largest accessibility text size. Unit tests were not run because the simulator was signed in to the live backend. Not seen on screen: toasts, the error banner, the offline notice, map chips, favor cards, the admin screens and the logged-out screens.

---

## 8. Method

- Counts are occurrences in `NaarsCars/App`, `Core`, `Features` and `UI`, produced by regular expressions. They include previews, so treat them as close estimates.

```bash
scripts/design-token-audit.sh all
```

- Contrast ratios use the WCAG 2.1 relative-luminance formula on the hex values in `ColorTheme.swift`.
- System color hex values are the long-standing UIKit ones; iOS 26 may render them slightly differently.
