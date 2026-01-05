# PRD: In-App Notifications

## Document Information
- **Feature Name**: In-App Notifications
- **Phase**: 2 (Communication)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

In-app notifications provide a history of events within the app, accessible via the bell icon. Unlike push notifications (which alert users externally), these are viewable within the app.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Display notification history | List shows past notifications |
| Unread indicator | Badge shows count |
| Mark as read | Individual and bulk marking |
| Deep linking | Tap to navigate |

---

## 3. Functional Requirements

### 3.1 Notification Model

```swift
struct AppNotification: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let text: String
    let rideId: UUID?
    let favorId: UUID?
    let conversationId: UUID?
    var read: Bool
    var isAdminDeclaration: Bool?
    var pinnedUntil: Date?
    var dismissed: Bool?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case text
        case rideId = "ride_id"
        case favorId = "favor_id"
        case conversationId = "conversation_id"
        case read
        case isAdminDeclaration = "is_admin_declaration"
        case pinnedUntil = "pinned_until"
        case dismissed
        case createdAt = "created_at"
    }
}
```

### 3.2 Notifications List View

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Notifications         [Mark All]  â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   ðŸ“Œ PINNED ANNOUNCEMENTS           â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“¢ Community Update         â”‚   â”‚
â”‚   â”‚ New features coming soon!   â”‚   â”‚
â”‚   â”‚ Posted by Admin â€¢ 2d ago    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   TODAY                             â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ â€¢ Bob claimed your ride to  â”‚   â”‚
â”‚   â”‚   SEA! You can now message. â”‚   â”‚
â”‚   â”‚   2h ago                    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚   Sara posted a new favor   â”‚   â”‚
â”‚   â”‚   request: Help moving      â”‚   â”‚
â”‚   â”‚   5h ago                    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   YESTERDAY                         â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚   New message from John...  â”‚   â”‚
â”‚   â”‚   1d ago                    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 3.3 Features

- **Unread dot** on unread notifications
- **Swipe to mark read/dismiss**
- **Pull to refresh**
- **Grouped by day**
- **Pinned admin announcements** at top

---

## 4. Non-Goals

- Notification preferences (handled in push PRD)
- Filtering by type

---

## 5. Dependencies

### Depends On
- `prd-foundation-architecture.md`

### Used By
- `prd-admin-panel.md` (for declarations)

---

*End of PRD: In-App Notifications*
