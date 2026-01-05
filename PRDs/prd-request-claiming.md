# PRD: Request Claiming

## Document Information
- **Feature Name**: Request Claiming
- **Phase**: 1 (Core Experience)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`, `prd-ride-requests.md`, `prd-favor-requests.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the claiming functionality for ride and favor requests. Claiming is how community members volunteer to help with a request.

### Why does this matter?
Claiming is the core interaction that connects requesters with helpers. It transforms a request from "I need help" to "Someone is helping me."

### What problem does it solve?
- Users need a way to indicate they'll help
- Posters need to know who is helping
- The system needs to track request status
- Prevents multiple people from duplicating effort

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can claim open requests | Status changes to claimed |
| Phone number required for claiming | Enforced before claim |
| Posters notified when claimed | Notification received |
| Claimers added to conversation | Can message poster |
| Users can unclaim requests | Request returns to open |
| Posters can mark complete | Status changes, review triggered |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| CLAIM-01 | User | Claim an open request | I volunteer to help |
| CLAIM-02 | User | Know phone number is required | I understand requirements |
| CLAIM-03 | Poster | Be notified when claimed | I know help is coming |
| CLAIM-04 | Claimer | Unclaim if needed | I can back out gracefully |
| CLAIM-05 | Poster | Mark request complete | I close out the request |
| CLAIM-06 | Poster | Leave a review | I thank my helper |

---

## 4. Functional Requirements

### 4.1 Phone Number Requirement

**Requirement CLAIM-FR-001**: Users MUST have a phone number to claim.

**Requirement CLAIM-FR-002**: Show alert if missing phone number with link to profile settings.

### 4.2 Claiming Flow

**Requirement CLAIM-FR-003**: Claiming a request MUST:
1. Verify phone number exists
2. Update status to "confirmed"
3. Set `claimed_by` to claimer's ID
4. Add claimer to conversation
5. Send notification to poster

### 4.3 Unclaiming Flow

**Requirement CLAIM-FR-004**: Unclaiming MUST:
1. Show confirmation dialog
2. Reset status to "open"
3. Clear `claimed_by`
4. Notify poster

### 4.4 Completing Flow

**Requirement CLAIM-FR-005**: Only POSTER can mark complete.

**Requirement CLAIM-FR-006**: Completing MUST:
1. Show confirmation
2. Update status to "completed"
3. Trigger review prompt

### 4.5 UI States

| State | Viewer | Actions |
|-------|--------|---------|
| Open | Poster | Edit, Delete |
| Open | Other | "I Can Help!" |
| Claimed | Poster | Message, Complete |
| Claimed | Claimer | Message, Unclaim |
| Claimed | Other | View only |
| Completed | Any | View only |

---

## 5. Non-Goals

- Multiple claimers per request
- Bidding system
- Automatic claim expiration

---

## 6. Design Considerations

- Haptic feedback on claim/unclaim
- Confirmation dialogs for destructive actions
- Loading states on buttons

---

## 7. Dependencies

### Depends On
- `prd-ride-requests.md`
- `prd-favor-requests.md`

### Used By
- `prd-messaging.md`
- `prd-reviews-ratings.md`

---

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Claim ride | Status changes |
| Claim favor | Status changes |
| Unclaim | Returns to open |
| Complete | Triggers review |

---

*End of PRD: Request Claiming*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.1 - Phone Number Requirement

**Replace/enhance existing phone requirement section with:**

```markdown
### 4.1 Phone Number Requirement

**Requirement CLAIM-FR-001**: Users MUST have a phone number on their profile to claim requests.

**Requirement CLAIM-FR-001a**: When prompting to add phone number, include visibility notice:

```
┌─────────────────────────────────────┐
│                                     │
│   📞 Phone Number Required          │
│                                     │
│   To claim requests, you need to    │
│   add a phone number so the poster  │
│   can coordinate with you.          │
│                                     │
│   ⓘ Your number will be visible    │
│   to other community members.       │
│                                     │
│   ┌─────────────────────────────┐   │
│   │     Add Phone Number        │   │
│   └─────────────────────────────┘   │
│                                     │
│            Not Now                  │
│                                     │
└─────────────────────────────────────┘
```

**Requirement CLAIM-FR-001b**: Implementation:

```swift
func attemptClaim(request: any ClaimableRequest) async {
    // Check for phone number first
    guard let profile = AuthService.shared.currentProfile,
          profile.phoneNumber != nil else {
        showPhoneRequiredSheet = true
        return
    }
    
    // Proceed with claim
    await claimRequest(request)
}
```

**Requirement CLAIM-FR-001c**: Phone required sheet:

```swift
struct PhoneRequiredSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigateToProfile: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Phone Number Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("To claim requests, you need to add a phone number so the poster can coordinate with you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Privacy notice
            HStack {
                Image(systemName: "info.circle")
                Text("Your number will be visible to other community members.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            Button("Add Phone Number") {
                dismiss()
                navigateToProfile = true
            }
            .buttonStyle(.borderedProminent)
            
            Button("Not Now") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
    }
}
```
```

---

## REVISE: Section 4.2 - Claim Action

**Enhance existing claim action with rate limiting:**

```markdown
### 4.2 Claim Action

**Requirement CLAIM-FR-003**: Claim action implementation with rate limiting:

```swift
func claimRequest(_ request: any ClaimableRequest) async {
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "claim",
        minimumInterval: 5
    ) else {
        HapticFeedback.warning()
        showRateLimitedFeedback = true
        return
    }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
        try await ClaimService.shared.claim(request)
        HapticFeedback.success()
        
        // Invalidate caches
        await CacheManager.shared.invalidateRides()
        await CacheManager.shared.invalidateFavors()
    } catch {
        self.error = .unknown("Failed to claim request")
        HapticFeedback.error()
    }
}
```

**Requirement CLAIM-FR-003a**: Claiming MUST be rate-limited:

| Layer | Limit | Behavior |
|-------|-------|----------|
| Client-side | 5 seconds between claim/unclaim | Silent prevention with haptic |
| Server-side (recommended) | 3 claim operations per minute | Reject with error |

**Requirement CLAIM-FR-003b**: If user attempts to claim while rate-limited:
- Button shows brief disabled state
- Warning haptic feedback
- No error dialog (avoid annoyance)
- Subtle text: "Please wait..." (optional, auto-dismisses)

**Requirement CLAIM-FR-003c**: Rate limit applies to BOTH claim AND unclaim:
- Same 5-second interval for both actions
- Prevents rapid toggle (claim → unclaim → claim)
- Tracked under same key: `"claim"`
```

---

## ADD: Section 4.3 - Unclaim Action

**Insert after section 4.2**

```markdown
### 4.3 Unclaim Action

**Requirement CLAIM-FR-006**: Unclaim action with same rate limiting:

```swift
func unclaimRequest(_ request: any ClaimableRequest) async {
    // Same rate limit as claim
    guard await RateLimiter.shared.checkAndRecord(
        action: "claim", // Same key - prevents rapid toggle
        minimumInterval: 5
    ) else {
        HapticFeedback.warning()
        return
    }
    
    // Show confirmation
    showUnclaimConfirmation = true
    pendingUnclaimRequest = request
}

func confirmUnclaim() async {
    guard let request = pendingUnclaimRequest else { return }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
        try await ClaimService.shared.unclaim(request)
        HapticFeedback.success()
        
        await CacheManager.shared.invalidateRides()
        await CacheManager.shared.invalidateFavors()
    } catch {
        self.error = .unknown("Failed to unclaim request")
    }
    
    pendingUnclaimRequest = nil
}
```

**Requirement CLAIM-FR-006a**: Unclaim confirmation dialog:
- Title: "Unclaim Request?"
- Message: "The poster will be notified that you're no longer available."
- Actions: "Unclaim" (destructive), "Cancel"
```

---

## ADD: Section 6.1 - Security Considerations

**Insert in Security section or create new section**

```markdown
### 6.1 Security Considerations

**Requirement CLAIM-SEC-001**: Claim operations controlled by RLS:
- Users can only claim if they're not the poster
- Users can only unclaim requests they've claimed
- See `SECURITY.md` for RLS policy details

**Requirement CLAIM-SEC-002**: Client-side validation:

```swift
func canClaim(_ request: any ClaimableRequest) -> Bool {
    guard let currentUserId = AuthService.shared.currentUserId else {
        return false
    }
    
    // Can't claim own request
    guard request.userId != currentUserId else {
        return false
    }
    
    // Can't claim if already claimed by someone else
    guard request.claimedBy == nil else {
        return false
    }
    
    // Must have phone number
    guard AuthService.shared.currentProfile?.phoneNumber != nil else {
        return false
    }
    
    return true
}
```

**Requirement CLAIM-SEC-003**: Server-side rate limiting (recommended for production):

```sql
-- Database function to enforce rate limit
CREATE OR REPLACE FUNCTION check_claim_rate_limit(user_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    recent_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO recent_count
    FROM claim_audit_log
    WHERE user_id = user_uuid
    AND created_at > NOW() - INTERVAL '1 minute';
    
    RETURN recent_count < 3;
END;
$$ LANGUAGE plpgsql;
```
```

---

*End of Request Claiming Addendum*
