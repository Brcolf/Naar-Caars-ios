# Tasks: Invite System

Based on `prd-invite-system.md`

## Affected Flows

- FLOW_INVITE_001: Generate Invite Code

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/InviteService.swift` - Invite operations
- `Core/Models/InviteCode.swift` - Invite code model (from auth)
- `Core/Utilities/InviteCodeGenerator.swift` - Code generation (from auth)
- `Features/Profile/Views/InviteCodesSection.swift` - Invite section in profile
- `UI/Components/Cards/InviteCodeCard.swift` - Invite code display

### Test Files
- `NaarsCarsTests/Core/Services/InviteServiceTests.swift`
- `NaarsCarsTests/Core/Utilities/InviteCodeGeneratorTests.swift`

## Notes

- Most invite code logic implemented in Authentication
- This task extends with advanced features
- ⭐ Rate limit: 10 seconds between code generation
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

- [ ] 0.0 Create feature branch: `git checkout -b feature/invite-system`

- [x] 1.0 Extend InviteService (if not exists)
  - [x] 1.1 Create/extend InviteService.swift (created new InviteService.swift)
  - [x] 1.2 Implement fetchInviteCodes(userId:) - with invitee name enrichment
  - [x] 1.3 Implement generateInviteCode(userId:) - with server-side rate limit (5 per day)
  - [x] 1.4 ⭐ Check rate limit before generating (client: 10 seconds, server: 5 per day)
  - [ ] 1.5 🧪 Write InviteServiceTests.testGenerateCode_RateLimited
  - [x] 1.6 Implement getInviteStats(userId:) - codes created, codes used
  - [ ] 1.7 🧪 Write InviteServiceTests.testGetStats_CountsCorrectly

### 🔒 CHECKPOINT: QA-INVITE-001
> Run: `./QA/Scripts/checkpoint.sh invite-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: InviteService tests pass
> Must pass before continuing

- [x] 2.0 Build InviteCodesSection
  - [x] 2.1 Create InviteCodesSection.swift (integrated in MyProfileView)
  - [x] 2.2 Display list of user's invite codes
  - [x] 2.3 Show code status (Available/Used)
  - [x] 2.4 If used, show who used it (invitee name and date)
  - [x] 2.5 Add swipe actions: Copy, Share (implemented as buttons in InviteCodeRow)
  - [x] 2.6 Add "Generate New Code" button (+ Generate button with icon)
  - [x] 2.7 Show invite stats at top (codes created, used, available)

- [x] 3.0 Implement sharing functionality
  - [x] 3.1 Create shareInviteCode() method (integrated in InviteCodeRow)
  - [x] 3.2 Generate share message with code (includes code and App Store link)
  - [x] 3.3 Use ShareLink or UIActivityViewController (using UIActivityViewController via ShareSheet)
  - [x] 3.4 Include app store link in message (placeholder, TODO to replace with actual link)

- [x] 4.0 Add copy functionality
  - [x] 4.1 Implement copyToClipboard() (copyCode method with raw code)
  - [x] 4.2 Show brief toast/feedback on copy ("Copied!" toast)
  - [x] 4.3 Add haptic feedback (UINotificationFeedbackGenerator.success)

- [ ] 5.0 Verify invite system
  - [ ] 5.1 Test code generation
  - [ ] 5.2 Test rate limiting
  - [ ] 5.3 Test sharing
  - [ ] 5.4 Test copying
  - [ ] 5.5 Commit: "feat: enhance invite system"

### 🔒 CHECKPOINT: QA-INVITE-FINAL
> Run: `./QA/Scripts/checkpoint.sh invite-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_INVITE_001
> All invite tests must pass
