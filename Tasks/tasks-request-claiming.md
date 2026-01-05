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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/request-claiming`

- [ ] 1.0 Implement ClaimService
  - [ ] 1.1 Create ClaimService.swift with singleton pattern
  - [ ] 1.2 Implement claimRequest(requestType:, requestId:, claimerId:)
  - [ ] 1.3 ⭐ Check rate limit (10 seconds between claims)
  - [ ] 1.4 Verify user has phone number before claiming
  - [ ] 1.5 Update request status to "confirmed"
  - [ ] 1.6 Call ConversationService to create/add to conversation
  - [ ] 1.7 Invalidate caches after claim
  - [ ] 1.8 🧪 Write ClaimServiceTests.testClaimRequest_NoPhone_ReturnsError
  - [ ] 1.9 🧪 Write ClaimServiceTests.testClaimRequest_Success_UpdatesStatus
  - [ ] 1.10 Implement unclaimRequest() to reset status to "open"
  - [ ] 1.11 🧪 Write ClaimServiceTests.testUnclaimRequest_Success
  - [ ] 1.12 Implement completeRequest() to set status "completed"
  - [ ] 1.13 🧪 Write ClaimServiceTests.testCompleteRequest_Success

### 🔒 CHECKPOINT: QA-CLAIM-001
> Run: `./QA/Scripts/checkpoint.sh claim-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: ClaimService tests pass
> Must pass before continuing

- [ ] 2.0 Build ClaimViewModel
  - [ ] 2.1 Create ClaimViewModel.swift
  - [ ] 2.2 Add @Published properties: isLoading, error, showPhoneRequired
  - [ ] 2.3 Implement checkCanClaim() to verify phone number
  - [ ] 2.4 Implement claim() method
  - [ ] 2.5 Implement unclaim() and complete() methods
  - [ ] 2.6 🧪 Write ClaimViewModelTests.testClaim_MissingPhone_ShowsSheet
  - [ ] 2.7 🧪 Write ClaimViewModelTests.testClaim_Success_NavigatesToConversation

- [ ] 3.0 Build Claim UI Components
  - [ ] 3.1 Create ClaimButton.swift component
  - [ ] 3.2 Show different states: "I Can Help!", "Unclaim", "Complete"
  - [ ] 3.3 Create ClaimSheet.swift confirmation dialog
  - [ ] 3.4 Create PhoneRequiredSheet.swift with navigation to profile
  - [ ] 3.5 Create UnclaimSheet.swift confirmation
  - [ ] 3.6 Create CompleteSheet.swift confirmation

- [ ] 4.0 Integrate claiming into detail views
  - [ ] 4.1 Add ClaimButton to RideDetailView
  - [ ] 4.2 Add ClaimButton to FavorDetailView
  - [ ] 4.3 Show appropriate button based on user role and status
  - [ ] 4.4 Navigate to conversation after successful claim

- [ ] 5.0 Implement ConversationService for claiming
  - [ ] 5.1 Create/update ConversationService.swift
  - [ ] 5.2 Implement createConversationForRequest()
  - [ ] 5.3 Add both users as participants

- [ ] 6.0 Verify claiming implementation
  - [ ] 6.1 Test claim without phone - verify prompt
  - [ ] 6.2 Test claim with phone - verify conversation created
  - [ ] 6.3 Test unclaim - verify status resets
  - [ ] 6.4 Test complete - verify status updates
  - [ ] 6.5 Commit: "feat: implement request claiming"

### 🔒 CHECKPOINT: QA-CLAIM-FINAL
> Run: `./QA/Scripts/checkpoint.sh claim-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_CLAIM_001, FLOW_CLAIM_002, FLOW_CLAIM_003
> All claiming tests must pass before starting Messaging
