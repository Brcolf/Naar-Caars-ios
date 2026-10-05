---
color: cyan
position:
  x: 190
  y: -639
isContextNode: false
agent_name: Amy
---

# UI Components Library

Reusable SwiftUI components used throughout the app.

## Common Components

### LoadingView.swift
Standard loading spinner with optional message:
```swift
LoadingView(message: "Loading rides...")
```

### EmptyStateView.swift
Empty state placeholder with icon and text:
```swift
EmptyStateView(
    icon: "tray",
    title: "No requests",
    message: "Post a ride or favor to get started"
)
```

### ErrorView.swift
Error display with retry button:
```swift
ErrorView(error: error, retryAction: { /* retry */ })
```

### SuccessCheckmark.swift
Animated success checkmark (used in forms):
```swift
if showSuccess {
    SuccessCheckmark()
}
```

### SkeletonView.swift
Skeleton loading placeholder for lists:
```swift
SkeletonView()
```

### ThemePreview.swift
Theme selection preview (light/dark/system)

### LanguageSelector.swift
Language picker for localization

## Buttons

### PrimaryButton.swift
Brand-styled primary action button:
```swift
PrimaryButton(title: "Post Ride", action: { /* action */ })
```

### SecondaryButton.swift
Secondary action button (outline style)

### DestructiveButton.swift
Red button for destructive actions (delete, etc.)

### LoadingButton.swift
Button with loading state:
```swift
LoadingButton(
    title: "Claim",
    isLoading: $isLoading,
    action: { /* async action */ }
)
```

## Cards

### RequestCard.swift
Display ride/favor in list:
- Poster avatar and name
- Pickup → Destination (or title/location)
- Date, time, status badge
- Tap action to view details

### ProfileCard.swift
User profile summary card:
- Avatar
- Name
- Reputation stars
- Bio snippet

### NotificationCard.swift
Notification display card:
- Icon for type
- Title and message
- Time ago
- Read/unread indicator

## Feedback Components

### Toast.swift
Temporary notification banner:
```swift
Toast(message: "Ride posted successfully", type: .success)
```

### ConfirmationDialog.swift
Reusable confirmation dialog:
```swift
ConfirmationDialog(
    title: "Delete Request",
    message: "Are you sure?",
    confirmText: "Delete",
    onConfirm: { /* action */ }
)
```

### RatingStars.swift
5-star rating display and input:
```swift
RatingStars(rating: $rating, isEditable: true)
```

### BadgeView.swift
Count badge (for notifications, messages):
```swift
BadgeView(count: 5)
```

### StatusBadge.swift
Colored status indicator:
```swift
StatusBadge(status: .open) // Green "Open"
StatusBadge(status: .confirmed) // Blue "Claimed"
```

## Input Components

### SearchBar.swift
Standard search input:
```swift
SearchBar(text: $searchText, placeholder: "Search rides...")
```

### DateTimePicker.swift
Combined date + time picker

### LocationPicker.swift
Location input with map preview

### ImagePicker.swift
Photo selection wrapper (PhotosPicker)

### PhoneNumberField.swift
Phone number input with validation

## Messaging Components

### MessageBubble.swift
Rich message display:
- Text messages with Markdown-style formatting
- Image messages with loading states
- Audio messages with playback controls
- Location messages with map preview
- Reply context display
- Edit indicator
- Reactions display

### MessageInputBar.swift
Message composer:
- Text input
- Attachment button (photos, camera)
- Audio recording button
- Location sharing button
- Send button

### ConversationRow.swift
Conversation in list:
- Participants avatars
- Last message preview
- Timestamp
- Unread badge

### TypingIndicator.swift
"User is typing..." animated dots

### MessageAudioPlayer.swift
Audio message playback:
- Play/pause button
- Waveform visualization
- Duration display
- Scrubbing support

### MessageReactionPicker.swift
Emoji reaction selector (like iMessage)

## Map Components

### MapView.swift
SwiftUI wrapper for MKMapView

### RouteMapView.swift
Map showing route from pickup to destination

### LocationAnnotation.swift
Custom map annotation view

## Community Components

### VoteButtons.swift
Upvote/downvote buttons with score:
```swift
VoteButtons(
    score: post.voteScore,
    userVote: post.userVote,
    onUpvote: { /* action */ },
    onDownvote: { /* action */ }
)
```

### CommentRow.swift
Comment display with threading:
- Indent level for nested replies
- Collapse/expand button
- Vote buttons
- Reply button

## Special Components

### AddressText.swift
Formatted address display with icon:
```swift
AddressText(address: "123 Main St, City, State")
```

### AvatarView.swift
User avatar with fallback to initials:
```swift
AvatarView(url: avatarUrl, name: userName, size: 40)
```

### ConversationAvatar.swift
Multi-user avatar for group conversations

## Usage Patterns

### Consistent Styling
All components use:
- Theme colors from `Constants.Colors`
- Spacing from `Constants.Dimensions`
- Corner radius from `Constants.cornerRadius`

### Accessibility
Components include:
- `accessibilityLabel`
- `accessibilityHint`
- Dynamic Type support
- VoiceOver support

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
