# Tasks: Reviews & Ratings

Based on `prd-reviews-ratings.md`

## Affected Flows

- FLOW_REVIEW_001: Leave Review After Completion

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/ReviewService.swift` - Review operations
- `Core/Models/Review.swift` - Review data model (from profile)
- `Features/Reviews/Views/LeaveReviewView.swift` - Review submission screen
- `Features/Reviews/Views/ReviewPromptSheet.swift` - Post-completion prompt
- `Features/Reviews/ViewModels/LeaveReviewViewModel.swift`
- `UI/Components/Common/StarRatingInput.swift` - Interactive star rating

### Test Files
- `NaarsCarsTests/Core/Services/ReviewServiceTests.swift`
- `NaarsCarsTests/Features/Reviews/LeaveReviewViewModelTests.swift`

## Notes

- Reviews triggered after marking request complete
- Creates Town Hall post automatically
- Skip option with expiration (can't review after 7 days)
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/reviews-ratings`

- [ ] 1.0 Implement ReviewService
  - [ ] 1.1 Create ReviewService.swift with singleton
  - [ ] 1.2 Implement createReview(requestType:, requestId:, fulfillerId:, rating:, summary:)
  - [ ] 1.3 Update request reviewed = true after review
  - [ ] 1.4 Create Town Hall post for review
  - [ ] 1.5 🧪 Write ReviewServiceTests.testCreateReview_Success
  - [ ] 1.6 Implement skipReview(requestType:, requestId:)
  - [ ] 1.7 Set reviewSkipped = true, reviewSkippedAt = now
  - [ ] 1.8 🧪 Write ReviewServiceTests.testSkipReview_SetsTimestamp
  - [ ] 1.9 Implement canStillReview() checking 7-day window
  - [ ] 1.10 🧪 Write ReviewServiceTests.testCanStillReview_After7Days_ReturnsFalse

### 🔒 CHECKPOINT: QA-REVIEW-001
> Run: `./QA/Scripts/checkpoint.sh review-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ReviewService tests pass
> Must pass before continuing

- [ ] 2.0 Build Leave Review View
  - [ ] 2.1 Create LeaveReviewView.swift
  - [ ] 2.2 Display request summary
  - [ ] 2.3 Add StarRatingInput component (1-5 stars)
  - [ ] 2.4 Add TextField for review summary
  - [ ] 2.5 Add "Submit Review" button
  - [ ] 2.6 Add "Skip" button with confirmation
  - [ ] 2.7 Navigate to dashboard after submission

- [ ] 3.0 Implement LeaveReviewViewModel
  - [ ] 3.1 Create LeaveReviewViewModel.swift
  - [ ] 3.2 Implement validateAndSubmit()
  - [ ] 3.3 Validate rating is selected (1-5)
  - [ ] 3.4 Summary is optional
  - [ ] 3.5 🧪 Write LeaveReviewViewModelTests.testSubmit_NoRating_ReturnsError

- [ ] 4.0 Build ReviewPromptSheet
  - [ ] 4.1 Create ReviewPromptSheet.swift
  - [ ] 4.2 Show automatically after completing request
  - [ ] 4.3 "Leave Review" navigates to LeaveReviewView
  - [ ] 4.4 "Maybe Later" dismisses with skip

- [ ] 5.0 Build StarRatingInput
  - [ ] 5.1 Create StarRatingInput.swift component
  - [ ] 5.2 Display 5 tappable stars
  - [ ] 5.3 Fill stars based on selection
  - [ ] 5.4 Add haptic feedback on tap
  - [ ] 5.5 Add Xcode previews

- [ ] 6.0 Verify reviews implementation
  - [ ] 6.1 Test review submission flow
  - [ ] 6.2 Test skip functionality
  - [ ] 6.3 Test 7-day expiration
  - [ ] 6.4 Test Town Hall post creation
  - [ ] 6.5 Commit: "feat: implement reviews and ratings"

### 🔒 CHECKPOINT: QA-REVIEW-FINAL
> Run: `./QA/Scripts/checkpoint.sh review-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_REVIEW_001
> All review tests must pass
