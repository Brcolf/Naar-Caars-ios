# PRD: Town Hall

## Document Information
- **Feature Name**: Town Hall (Community Forum)
- **Phase**: 3 (Community Features)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

Town Hall is a community forum where users can post updates, share reviews, and communicate with the entire community. It's a simple social feed within the app.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can post updates | Posts appear in feed |
| Posts support images | Images display inline |
| Real-time feed | New posts appear live |
| Users can delete own posts | Post removed |

---

## 3. Functional Requirements

### 3.1 Post Model

```swift
struct TownHallPost: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var content: String
    var imageUrl: String?
    let createdAt: Date
    
    // Joined
    var author: Profile?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case content
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }
}
```

### 3.2 Town Hall View

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Town Hall                   ðŸ“¢    â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   Share with the Community          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ What's on your mind?        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   [ðŸ“· Add Photo]          [Post]    â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   Recent Posts                      â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] Jane D.     [ðŸ—‘ï¸]   â”‚   â”‚
â”‚   â”‚ 2 hours ago                 â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚ â­ Review for Bob M.        â”‚   â”‚
â”‚   â”‚ Rating: â˜…â˜…â˜…â˜…â˜…               â”‚   â”‚
â”‚   â”‚ "Amazing help moving!"      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] John S.            â”‚   â”‚
â”‚   â”‚ Yesterday                   â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚ Thanks everyone for the     â”‚   â”‚
â”‚   â”‚ warm welcome! ðŸŽ‰            â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚ [Image attachment]          â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 3.3 Features

- **Text posts** with max 500 characters
- **Image attachments** (optional)
- **Real-time updates** via Supabase
- **Delete own posts** only
- **Tap avatar** to view profile
- **Pull to refresh**

### 3.4 Review Integration

Reviews posted via the review system automatically create Town Hall posts with formatted content:
```
â­ Review for [Name]
Rating: â˜…â˜…â˜…â˜…â˜…
"[Review text]"
For: [Request description]
```

---

## 4. Non-Goals

- Comments/replies on posts
- Likes/reactions
- Post editing
- Hashtags/mentions

---

## 5. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-user-profile.md`

### Used By
- `prd-reviews-ratings.md`

---

*End of PRD: Town Hall*
