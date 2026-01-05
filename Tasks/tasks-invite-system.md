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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/invite-system`

- [ ] 1.0 Extend InviteService (if not exists)
  - [ ] 1.1 Create/extend InviteService.swift
  - [ ] 1.2 Implement fetchInviteCodes(userId:)
  - [ ] 1.3 Implement generateInviteCode(userId:)
  - [ ] 1.4 ⭐ Check rate limit before generating
  - [ ] 1.5 🧪 Write InviteServiceTests.testGenerateCode_RateLimited
  - [ ] 1.6 Implement getInviteStats(userId:) - codes created, codes used
  - [ ] 1.7 🧪 Write InviteServiceTests.testGetStats_CountsCorrectly

### 🔒 CHECKPOINT: QA-INVITE-001
> Run: `./QA/Scripts/checkpoint.sh invite-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: InviteService tests pass
> Must pass before continuing

- [ ] 2.0 Build InviteCodesSection
  - [ ] 2.1 Create InviteCodesSection.swift
  - [ ] 2.2 Display list of user's invite codes
  - [ ] 2.3 Show code status (Available/Used)
  - [ ] 2.4 If used, show who used it
  - [ ] 2.5 Add swipe actions: Copy, Share
  - [ ] 2.6 Add "Generate New Code" button
  - [ ] 2.7 Show invite stats at top

- [ ] 3.0 Implement sharing functionality
  - [ ] 3.1 Create shareInviteCode() method
  - [ ] 3.2 Generate share message with code
  - [ ] 3.3 Use ShareLink or UIActivityViewController
  - [ ] 3.4 Include app store link in message

- [ ] 4.0 Add copy functionality
  - [ ] 4.1 Implement copyToClipboard()
  - [ ] 4.2 Show brief toast/feedback on copy
  - [ ] 4.3 Add haptic feedback

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
