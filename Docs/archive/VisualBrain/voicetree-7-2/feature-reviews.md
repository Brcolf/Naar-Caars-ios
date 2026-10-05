---
color: orange
position:
  x: 77
  y: -1080
isContextNode: false
agent_name: Amy
---

# Feature: Reviews

Star ratings and feedback for completed requests.

## Views
- **LeaveReviewView.swift** - 5-star rating with optional comment
- **ReviewPromptSheet.swift** - Prompt after request completion
- **ReviewsListView.swift** - View reviews received

## ViewModels
- **LeaveReviewViewModel.swift** - Submit review with validation
- **ReviewsViewModel.swift** - Load user's reviews

## Services
- **ReviewService.swift** - CRUD for reviews
- **ReviewPromptProvider.swift** - Logic for when to prompt reviews
- **CompletionPromptProvider.swift** - Related prompt triggers

## Models
- **Review.swift** - Star rating, comment, reviewer/reviewee

## Review Flow

### Trigger
When a ride/favor is marked as completed:
1. Check if review already exists
2. Check if review was skipped
3. Show `ReviewPromptSheet` if neither

### Submit Review
1. User selects 1-5 stars
2. Optional text comment
3. `ReviewService.createReview()` submits to database
4. Updates `rides.reviewed = true` or `favors.reviewed = true`
5. Triggers notification to reviewee

### Skip Review
User can skip review (stored in `review_skipped` field).
Won't be prompted again for this request.

## Review Types

### As Poster (reviewing claimer)
- "How was [Claimer Name]?"
- Rate their helpfulness
- Rate their reliability

### As Claimer (reviewing poster)
- "How was [Poster Name]?"
- Rate their communication
- Rate accuracy of request description

## Integration

Reviews affect:
- **Leaderboard scores** - Higher ratings = more points
- **Profile reputation** - Average star rating displayed
- **Trust signals** - Users see past reviews before claiming

## Review Prompt Logic

Uses `PromptSideEffects.swift` to determine when to show prompts:
- Only after truly completed requests
- Not if already reviewed
- Not if skipped
- Respects prompt frequency limits

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
