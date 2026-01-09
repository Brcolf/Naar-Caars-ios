# Tasks: Request Claiming

Based on `prd-request-claiming.md`

## Affected Flows

- FLOW_CLAIM_001: Claim Request
- FLOW_CLAIM_002: Unclaim Request
- FLOW_CLAIM_003: Mark Request Complete

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/ClaimService.swift` - Claim operations service
- `Core/Services/ConversationService.swift` - Conversation creation
- `Features/Claiming/ViewModels/ClaimViewModel.swift` - Claim view model
- `Features/Claiming/Views/ClaimSheet.swift` - Claim confirmation sheet
- `Features/Claiming/Views/PhoneRequiredSheet.swift` - Phone number prompt
- `UI/Components/Buttons/ClaimButton.swift` - Reusable claim button

### Test Files
- `NaarsCarsTests/Core/Services/ClaimServiceTests.swift` - ClaimService unit tests
- `NaarsCarsTests/Features/Claiming/ClaimViewModelTests.swift` - ClaimVM tests
- `NaarsCarsIntegrationTests/Claiming/ClaimFlowTests.swift` - Full claim flow

## Notes

- Phone number required to claim (security measure)
- Creates conversation automatically on claim
- ⭐ Rate limiting on claim/unclaim actions
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

- [x] 0.0 Create feature branch: `git checkout -b feature/request-claiming`

- [x] 1.0 Implement ClaimService
  - [x] 1.1 Create ClaimService.swift with singleton pattern
  - [x] 1.2 Implement claimRequest(requestType:, requestId:, claimerId:)
  - [x] 1.3 ⭐ Check rate limit (10 seconds between claims)
  - [x] 1.4 Verify user has phone number before claiming
  - [x] 1.5 Update request status to "confirmed"
  - [x] 1.6 Call ConversationService to create/add to conversation
  - [x] 1.7 Invalidate caches after claim
  - [x] 1.8 🧪 Write ClaimServiceTests.testClaimRequest_NoPhone_ReturnsError
  - [x] 1.9 🧪 Write ClaimServiceTests.testClaimRequest_Success_UpdatesStatus
  - [x] 1.10 Implement unclaimRequest() to reset status to "open"
  - [x] 1.11 🧪 Write ClaimServiceTests.testUnclaimRequest_Success
  - [x] 1.12 Implement completeRequest() to set status "completed"
  - [x] 1.13 🧪 Write ClaimServiceTests.testCompleteRequest_Success

### 🔒 CHECKPOINT: QA-CLAIM-001
> Run: `./QA/Scripts/checkpoint.sh claim-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ClaimService tests pass
> Must pass before continuing

- [x] 2.0 Build ClaimViewModel
  - [x] 2.1 Create ClaimViewModel.swift
  - [x] 2.2 Add @Published properties: isLoading, error, showPhoneRequired
  - [x] 2.3 Implement checkCanClaim() to verify phone number
  - [x] 2.4 Implement claim() method
  - [x] 2.5 Implement unclaim() and complete() methods
  - [x] 2.6 🧪 Write ClaimViewModelTests.testClaim_MissingPhone_ShowsSheet
  - [x] 2.7 🧪 Write ClaimViewModelTests.testClaim_Success_NavigatesToConversation

- [x] 3.0 Build Claim UI Components
  - [x] 3.1 Create ClaimButton.swift component
  - [x] 3.2 Show different states: "I Can Help!", "Unclaim", "Complete"
  - [x] 3.3 Create ClaimSheet.swift confirmation dialog
  - [x] 3.4 Create PhoneRequiredSheet.swift with navigation to profile
  - [x] 3.5 Create UnclaimSheet.swift confirmation
  - [x] 3.6 Create CompleteSheet.swift confirmation

- [x] 4.0 Integrate claiming into detail views
  - [x] 4.1 Add ClaimButton to RideDetailView
  - [x] 4.2 Add ClaimButton to FavorDetailView
  - [x] 4.3 Show appropriate button based on user role and status
  - [x] 4.4 Navigate to conversation after successful claim (placeholder)

- [x] 5.0 Implement ConversationService for claiming
  - [x] 5.1 Create/update ConversationService.swift
  - [x] 5.2 Implement createConversationForRequest()
  - [x] 5.3 Add both users as participants

- [x] 6.0 Verify claiming implementation
  - [x] 6.1 Build and ensure zero compilation errors
  - [ ] 6.2 Test claim without phone - verify prompt (Manual testing required)
  - [ ] 6.3 Test claim with phone - verify conversation created (Manual testing required)
  - [ ] 6.4 Test unclaim - verify status resets (Manual testing required)
  - [ ] 6.5 Test complete - verify status updates (Manual testing required)
  - [ ] 6.6 Commit: "feat: implement request claiming"

### 🔒 CHECKPOINT: QA-CLAIM-FINAL
> Run: `./QA/Scripts/checkpoint.sh claim-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_CLAIM_001, FLOW_CLAIM_002, FLOW_CLAIM_003
> All claiming tests must pass before starting Messaging
