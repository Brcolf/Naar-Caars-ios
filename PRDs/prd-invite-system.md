# PRD: Invite System

## Document Information
- **Feature Name**: Invite System
- **Phase**: 4 (Administration)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`, `prd-user-profile.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

The invite system ensures Naar's Cars remains a trusted, invite-only community. Users generate invite codes to share with friends and neighbors.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Generate invite codes | Codes created |
| Track code usage | Used/unused status |
| Share codes easily | Copy/share functionality |
| View invite history | See who used codes |

---

## 3. Functional Requirements

### 3.1 Invite Code Model

```swift
struct InviteCode: Codable, Identifiable {
    let id: UUID
    let code: String
    let createdBy: UUID
    var usedBy: UUID?
    var inviteeName: String?
    var inviteePhone: String?
    var smsSentAt: Date?
    let createdAt: Date
    
    var isUsed: Bool { usedBy != nil }
    
    enum CodingKeys: String, CodingKey {
        case id, code
        case createdBy = "created_by"
        case usedBy = "used_by"
        case inviteeName = "invitee_name"
        case inviteePhone = "invitee_phone"
        case smsSentAt = "sms_sent_at"
        case createdAt = "created_at"
    }
}
```

### 3.2 Code Generation

**Format:** `NC` + 6 alphanumeric characters
- Example: `NC7X9K2A`
- Always uppercase
- Unique per code

### 3.3 Invite Codes in Profile

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   ðŸŽŸï¸ Invite Codes      [+ Generate] â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ NC7X9K2A        [Available] â”‚   â”‚
â”‚   â”‚         [Copy] [Share]      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ NCAB3DEF           [Used]   â”‚   â”‚
â”‚   â”‚ Used by: Jane D.            â”‚   â”‚
â”‚   â”‚ Jan 3, 2025                 â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ NC9Z2YBC           [Used]   â”‚   â”‚
â”‚   â”‚ Used by: Bob M.             â”‚   â”‚
â”‚   â”‚ Dec 20, 2024                â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 3.4 Code Actions

**Copy:**
- Tap "Copy" â†’ copies code to clipboard
- Haptic feedback + brief "Copied!" toast

**Share:**
- Opens iOS share sheet with message:
```
Join me on Naar's Cars! ðŸš—

Use invite code: NC7X9K2A
Sign up at: https://naarscars.com/signup?code=NC7X9K2A
```

### 3.5 Generate Flow

1. User taps "+ Generate"
2. Code generated and saved
3. New code appears at top of list
4. Ready to share

### 3.6 Code Limit (Optional)

Consider limiting codes per user if abuse becomes an issue:
- e.g., Max 10 unused codes at a time
- Show "You have too many unused codes" error

---

## 4. Non-Goals

- SMS sending from iOS app (web feature only)
- Code expiration
- Revoking codes
- Code customization

---

## 5. Future Enhancement: SMS Invites

The web app supports sending SMS invites. For iOS, this could be implemented later using:
- `MessageUI` framework for SMS
- Or server-side SMS via Twilio

---

## 6. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`
- `prd-user-profile.md`

---

*End of PRD: Invite System*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 3.2 - Code Generation

**Replace existing code generation with strengthened format:**

```markdown
### 3.2 Code Generation

**Requirement INV-FR-001**: Invite code format (updated):

```
NC + 8 alphanumeric characters (uppercase)
Example: NC7X9K2ABQ
```

| Property | Value |
|----------|-------|
| Prefix | "NC" (Naar's Cars identifier) |
| Random portion | 8 characters |
| Character set | A-Z, 0-9 (excluding confusing: 0/O, 1/I/L) |
| Effective character set | 32 characters |
| Total combinations | 32^8 = ~1.1 trillion |

**Requirement INV-FR-001a**: Use character set that avoids confusion:

```swift
// Core/Services/InviteCodeGenerator.swift
enum InviteCodeGenerator {
    // Exclude confusing characters: 0 (zero), O, 1 (one), I, L
    private static let characters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    
    static func generate() -> String {
        var code = "NC"
        for _ in 0..<8 {
            let randomIndex = Int.random(in: 0..<characters.count)
            code.append(characters[randomIndex])
        }
        return code
    }
}
```

**Requirement INV-FR-001b**: Code validation MUST be case-insensitive:

```swift
func validateCodeFormat(_ input: String) -> String? {
    // Normalize: uppercase, trim whitespace
    let code = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Must start with NC
    guard code.hasPrefix("NC") else { return nil }
    
    // Accept both 6-char (legacy) and 8-char (new) codes
    // NC + 6 = 8 total, NC + 8 = 10 total
    guard code.count == 8 || code.count == 10 else { return nil }
    
    // Random portion must be alphanumeric
    let randomPortion = code.dropFirst(2)
    guard randomPortion.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
    
    return code
}
```

**Requirement INV-FR-001c**: Backward compatibility with 6-character codes:
- Existing codes (NC + 6 chars) remain valid
- New codes generated with 8 characters
- Validation accepts both lengths

### 3.2a Code Generation Rate Limiting

**Requirement INV-FR-002**: Invite code generation MUST be rate-limited:

| Layer | Limit | Behavior |
|-------|-------|----------|
| Client-side | 10 seconds between generations | Disable button |
| Server-side | 5 codes per user per 24 hours | Show limit message |

**Requirement INV-FR-002a**: Client-side implementation:

```swift
func generateInviteCode() async {
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "generate_invite",
        minimumInterval: 10
    ) else {
        HapticFeedback.warning()
        return
    }
    
    isGenerating = true
    defer { isGenerating = false }
    
    do {
        let code = try await InviteCodeService.shared.generateCode()
        inviteCodes.insert(code, at: 0)
        HapticFeedback.success()
    } catch AppError.rateLimited {
        showDailyLimitAlert = true
    } catch {
        self.error = .unknown("Failed to generate code")
    }
}
```

**Requirement INV-FR-002b**: Daily limit alert:
- Title: "Daily Limit Reached"
- Message: "You can generate up to 5 invite codes per day. Try again tomorrow!"
- Action: "OK"

**Requirement INV-FR-002c**: Server-side daily limit check:

```sql
-- Check if user has generated too many codes today
CREATE OR REPLACE FUNCTION check_invite_limit(user_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    today_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO today_count
    FROM invite_codes
    WHERE created_by = user_uuid
    AND created_at > CURRENT_DATE;
    
    RETURN today_count < 5;
END;
$$ LANGUAGE plpgsql;
```
```

---

## ADD: Section 4.3 - Code Display and Sharing

**Insert after code management section**

```markdown
### 4.3 Code Display and Sharing

**Requirement INV-FR-010**: Display codes with clear formatting:

```
┌─────────────────────────────────────┐
│   Your Invite Code                  │
│                                     │
│   NC7X · 9K2A · BQ                  │
│                                     │
│   [Copy]     [Share]                │
│                                     │
│   Valid until used                  │
└─────────────────────────────────────┘
```

**Requirement INV-FR-010a**: Format code for readability:

```swift
func formatCodeForDisplay(_ code: String) -> String {
    // NC7X9K2ABQ → NC7X · 9K2A · BQ
    guard code.count == 10 else {
        // Legacy 8-char code: NC7X9K2A → NC7X · 9K2A
        let chars = Array(code)
        return "\(String(chars[0...3])) · \(String(chars[4...7]))"
    }
    
    let chars = Array(code)
    return "\(String(chars[0...3])) · \(String(chars[4...7])) · \(String(chars[8...9]))"
}
```

**Requirement INV-FR-010b**: Copy removes formatting:

```swift
func copyCode(_ code: String) {
    // Copy raw code without dots/spaces
    UIPasteboard.general.string = code.replacingOccurrences(of: " · ", with: "")
    HapticFeedback.success()
    showCopiedToast = true
}
```

**Requirement INV-FR-010c**: Share message:

```swift
func shareCode(_ code: String) {
    let message = """
    Join me on Naar's Cars! 🚗
    
    Use my invite code: \(code)
    
    Download the app: [App Store Link]
    """
    
    let activityVC = UIActivityViewController(
        activityItems: [message],
        applicationActivities: nil
    )
    
    // Present share sheet
}
```
```

---

## ADD: Section 6.1 - Security Considerations

**Insert in Security section or create new**

```markdown
### 6.1 Security Considerations

**Requirement INV-SEC-001**: Brute force protection:

1. **Strong codes**: 32^8 = ~1.1 trillion combinations
2. **Rate limiting**: 5 validation attempts per hour (see prd-authentication.md)
3. **Uniform errors**: Don't reveal if code exists but is used

**Requirement INV-SEC-002**: Code cannot be used by creator:

```swift
func validateAndUseCode(_ code: String, forUser userId: UUID) async throws {
    let inviteCode = try await fetchCode(code)
    
    // Can't use own code
    guard inviteCode.createdBy != userId else {
        throw AppError.invalidInviteCode
    }
    
    // ... rest of validation
}
```

**Requirement INV-SEC-003**: Code usage is atomic:

```sql
-- Use transaction to prevent race condition
BEGIN;
    SELECT * FROM invite_codes WHERE code = $1 AND used_by IS NULL FOR UPDATE;
    -- If found, mark as used
    UPDATE invite_codes SET used_by = $2, used_at = NOW() WHERE code = $1;
COMMIT;
```

**Requirement INV-SEC-004**: Monitoring for abuse:

```swift
// Log suspicious patterns
if validationFailureCount > 3 {
    Log.security("Multiple invite code failures from device: \(DeviceIdentifier.current)")
}
```

See `SECURITY.md` for complete security requirements.
```

---

*End of Invite System Addendum*
