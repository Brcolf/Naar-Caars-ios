# PRD: Reviews & Ratings

## Document Information
- **Feature Name**: Reviews & Ratings
- **Phase**: 3 (Community Features)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-request-claiming.md`, `prd-town-hall.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

After a request is completed, the poster can leave a review for the helper. Reviews build reputation and trust within the community.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Prompt for review after completion | Review modal appears |
| 5-star rating system | Rating captured |
| Written review | Text feedback saved |
| Reviews visible on profile | Profile shows reviews |
| Reviews posted to Town Hall | Automatic sharing |
| Skip option | Users can defer |

---

## 3. Functional Requirements

### 3.1 Review Model

```swift
struct Review: Codable, Identifiable {
    let id: UUID
    let requestId: UUID
    let requestType: String  // "ride" or "favor"
    let reviewerId: UUID
    let fulfillerId: UUID
    let rating: Int  // 1-5
    let summary: String
    let townHallPostId: UUID?
    let createdAt: Date
    
    var reviewer: Profile?
    
    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case requestType = "request_type"
        case reviewerId = "reviewer_id"
        case fulfillerId = "fulfiller_id"
        case rating, summary
        case townHallPostId = "town_hall_post_id"
        case createdAt = "created_at"
    }
}
```

### 3.2 Review Prompt Flow

When poster marks request as complete:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                                     â”‚
â”‚      Leave a Review                 â”‚
â”‚                                     â”‚
â”‚   Your request has been completed!  â”‚
â”‚   Please take a moment to review    â”‚
â”‚   Bob for their help.               â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Capitol Hill â†’ SEA          â”‚   â”‚
â”‚   â”‚ Monday, January 6           â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   How was your experience?          â”‚
â”‚                                     â”‚
â”‚       â˜†  â˜†  â˜†  â˜†  â˜†                â”‚
â”‚       (tap to rate)                 â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Share your experience...    â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚      Submit Review          â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚         Skip for now                â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 3.3 Review Submission

When submitted:
1. Create Review record
2. Create Town Hall post with formatted review
3. Mark request as `reviewed = true`
4. Notify fulfiller of new review

### 3.4 Skip Behavior

- User can skip review temporarily
- Skipped reviews show in "Skipped Reviews" badge
- 7-day window to return and review
- After 7 days, review opportunity expires

### 3.5 Reviews on Profile

Profile displays:
- Average rating (stars)
- Total review count
- List of reviews with:
  - Reviewer avatar/name
  - Star rating
  - Review text
  - Date

### 3.6 Star Rating Component

```swift
struct StarRatingView: View {
    @Binding var rating: Int
    var interactive: Bool = true
    var size: CGFloat = 32
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(star <= rating ? .yellow : .gray)
                    .onTapGesture {
                        if interactive {
                            rating = star
                        }
                    }
            }
        }
    }
}
```

---

## 4. Non-Goals

- Review replies
- Review editing
- Disputing reviews
- Review for both parties (only poster reviews helper)

---

## 5. Dependencies

### Depends On
- `prd-request-claiming.md`
- `prd-town-hall.md`

### Used By
- `prd-user-profile.md`
- `prd-leaderboards.md`

---

*End of PRD: Reviews & Ratings*
