---
color: purple
position:
  x: -826
  y: -1373
isContextNode: false
agent_name: Amy
---

# Core Data Models

NaarsCars iOS uses a clean, well-structured model layer that mirrors the PostgreSQL database schema.

## Key Models

### Request Models
- **Ride.swift** - Rideshare requests with pickup/destination, estimated cost, seats
- **Favor.swift** - Community favor requests with duration, requirements
- **Profile.swift** - User profiles with approval status, admin flags
- **RequestItem.swift** - Unified model for displaying rides/favors in dashboard

### Messaging Models
- **Message.swift** - Rich messaging with types (text, image, audio, location), reactions, replies, edit/unsend
- **Conversation.swift** - Conversation metadata with participants
- **MessageReactions** - Aggregated reactions per message
- **ReplyContext** - Lightweight reference for message threads

### Notification Models
- **AppNotification.swift** - In-app notifications for rides, favors, messages, reviews
- **NotificationGrouping.swift** - Smart grouping logic for notification lists

### Community Models
- **TownHallPost.swift** - Community posts with votes
- **TownHallComment.swift** - Threaded comments
- **Review.swift** - Star ratings and feedback for completed requests
- **LeaderboardEntry.swift** - Gamification/reputation tracking

## Model Design Strengths

1. **Clean Codable conformance** - All models use explicit `CodingKeys` for snake_case ↔ camelCase mapping
2. **Type-safe enums** - Status enums (RideStatus, FavorStatus, MessageType) with display properties
3. **Optional joined fields** - Models support efficient data fetching with relationships (poster, claimer, participants)
4. **Sendable conformance** - Thread-safe models for Swift concurrency
5. **Computed properties** - Rich domain logic (e.g., `canUnsend`, `isEdited`, `displayText`)

## Notable Issues

### 🟡 Duplicate SwiftUI Import
`Favor.swift:9-10` has `import SwiftUI` twice (minor cleanup needed)

```swift
import Foundation
import SwiftUI
import SwiftUI  // ❌ Duplicate
```

### 🟢 Local-First Fields
Message model includes local-first fields (`sendStatus`, `localAttachmentPath`, `syncError`) not in CodingKeys - these are managed by SwiftData layer for offline capabilities.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
