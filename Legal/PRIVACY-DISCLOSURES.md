# Naar's Cars Privacy Disclosures

## Document Information
- **Type**: Privacy Requirements & App Store Compliance
- **Last Updated**: 2026-10-18 (content review date; reviewed for the multi-community Phase 2 build)
- **Status**: Maintained; must be re-verified before each release that changes data collection

---

## 1. Overview

This document defines all privacy-related requirements for the Naar's Cars iOS application, including:
- Info.plist privacy keys
- App Store Connect Privacy Nutrition Labels
- User consent flows
- Data retention policies

**CRITICAL**: App Store will REJECT the app if privacy disclosures don't match actual data collection.

---

## 2. Info.plist Required Keys

The following keys MUST be added to Info.plist with user-friendly descriptions:

### 2.1 Required Keys

| Key | Description | When Triggered |
|-----|-------------|----------------|
| `NSCameraUsageDescription` | "Naar's Cars uses your camera to take profile photos." | Profile photo capture (if camera option offered) |
| `NSPhotoLibraryUsageDescription` | "Naar's Cars accesses your photos to set your profile picture and share images in messages." | Photo picker for avatar or message images |
| `NSLocationWhenInUseUsageDescription` | "Naar's Cars shows your location on the map to help you find nearby requests." | Map view (Phase 5) |
| `NSFaceIDUsageDescription` | "Naar's Cars uses Face ID to quickly and securely unlock the app." | Biometric auth (Phase 5) |

### 2.2 Info.plist XML

```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>Naar's Cars uses your camera to take profile photos.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Naar's Cars accesses your photos to set your profile picture and share images in messages.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Naar's Cars shows your location on the map to help you find nearby requests.</string>

<key>NSFaceIDUsageDescription</key>
<string>Naar's Cars uses Face ID to quickly and securely unlock the app.</string>
```

### 2.3 Implementation Requirements

**Requirement PRIV-INFO-001**: All Info.plist keys MUST be added before implementing features that require those permissions.

**Requirement PRIV-INFO-002**: Descriptions MUST be:
- Clear and specific about why the permission is needed
- Written in plain language (no technical jargon)
- Honest about how the data will be used

---

## 3. App Store Connect Privacy Labels

### 3.1 Data Linked to You

Select the following in App Store Connect → App Privacy:

| Data Type | Collection | Usage | Linked to Identity |
|-----------|------------|-------|-------------------|
| **Contact Info - Email Address** | Yes | App Functionality | Yes |
| **Contact Info - Phone Number** | Yes | App Functionality | Yes |
| **Contact Info - Name** | Yes | App Functionality | Yes |
| **User Content - Photos or Videos** | Yes | App Functionality | Yes |
| **User Content - Other User Content** | Yes | App Functionality | Yes |
| **Identifiers - Device ID** | Yes | App Functionality | Yes |
| **Location - Precise Location** | Yes (Phase 5) | App Functionality | Yes |

### 3.2 Detailed Breakdown

#### Contact Info - Email Address
- **Collected**: Yes
- **Purpose**: App Functionality (account creation, login)
- **Linked to User**: Yes
- **Used for Tracking**: No

#### Contact Info - Phone Number
- **Collected**: Yes (optional, but required for claiming)
- **Purpose**: App Functionality (ride coordination)
- **Linked to User**: Yes
- **Used for Tracking**: No

#### Contact Info - Name
- **Collected**: Yes
- **Purpose**: App Functionality (display to other users)
- **Linked to User**: Yes
- **Used for Tracking**: No

#### User Content - Photos or Videos
- **Collected**: Yes (profile photos, message images)
- **Purpose**: App Functionality
- **Linked to User**: Yes
- **Used for Tracking**: No

#### User Content - Other User Content
- **Collected**: Yes (ride requests, favor requests, messages, reviews, Town Hall posts, communities created, per-community application answers, invite redemptions, admin removal notes, owned-community limit requests)
- **Note (multi-community, 2026-10-18)**: no new data *type*. The application answers were already collected; they are now stored per community and shown to that community's owners and admins (ordinary users). Re-check the App Store Connect answers against this list before submitting the Phase 2 build.
- **Purpose**: App Functionality
- **Linked to User**: Yes
- **Used for Tracking**: No

#### Identifiers - Device ID
- **Collected**: Yes (push notification tokens)
- **Purpose**: App Functionality (push notifications)
- **Linked to User**: Yes
- **Used for Tracking**: No

#### Location - Precise Location (Phase 5 only)
- **Collected**: Yes (when using map view)
- **Purpose**: App Functionality (show nearby requests)
- **Linked to User**: Yes (only while using feature)
- **Used for Tracking**: No
- **Note**: Location is NOT stored server-side; used only for real-time map display

### 3.3 Data NOT Collected

Confirm "No" for:
- Health & Fitness
- Financial Info
- Sensitive Info
- Contacts (address book)
- Browsing History
- Search History
- Diagnostics (unless crash reporting added)
- Advertising Data

### 3.4 Data Used for Tracking

- Select: **No, we do not use data for tracking**

### 3.5 Summary Statement

For App Store Connect description:

> Naar's Cars collects personal information (name, email, phone number) to facilitate ride and favor sharing within the communities members create and join. Profile photos and user-generated content (requests, messages, reviews) are stored to enable app functionality. Push notification tokens are collected to deliver notifications. Location data is used only for the map feature and is not stored. No data is sold to third parties or used for advertising.

---

## 4. User Consent Flows

### 4.1 Location Permission

**When triggered**: First time user opens Map View (Phase 5)

**Flow**:
1. User taps Map tab or map icon
2. System dialog appears with Info.plist description
3. User selects "Allow While Using App" or "Don't Allow"

**If denied**:
- Map still displays without user location dot
- Functionality still works (can browse requests)
- Show subtle banner: "Enable location in Settings to see requests near you"

**Implementation**:
```swift
// Check authorization before showing map
switch locationManager.authorizationStatus {
case .notDetermined:
    locationManager.requestWhenInUseAuthorization()
case .denied, .restricted:
    showLocationDisabledBanner = true
case .authorizedWhenInUse, .authorizedAlways:
    showUserLocation = true
@unknown default:
    break
}
```

### 4.2 Photo Library Permission

**When triggered**: First time user taps to change avatar or share image in message

**Flow**:
1. User taps "Change Photo" or image attachment button
2. System dialog appears with Info.plist description
3. User selects "Select Photos..." or "Allow Full Access" or "Don't Allow"

**If denied**:
- Photo picker not available
- Show alert:
  - Title: "Photo Access Required"
  - Message: "To add photos, please enable photo access in Settings."
  - Actions: "Open Settings" (deep link), "Cancel"

**Implementation**:
```swift
// Using PhotosPicker (iOS 16+) handles permissions automatically
// But check for full denial
if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .denied {
    showPhotoAccessDeniedAlert = true
}
```

### 4.3 Camera Permission

**When triggered**: First time user chooses "Take Photo" option (if offered)

**Flow**:
1. User taps "Take Photo" option
2. System dialog appears with Info.plist description
3. User selects "OK" or "Don't Allow"

**If denied**:
- "Take Photo" option hidden or disabled
- User can still select from library

### 4.4 Push Notification Permission

**When triggered**: After first successful login (see prd-notifications-push.md PUSH-FR-013)

**Flow**:
1. User logs in successfully (approved user)
2. Custom explanation screen appears:
   ```
   ┌─────────────────────────────────────┐
   │            🔔                       │
   │                                     │
   │    Stay in the Loop!                │
   │                                     │
   │    Get notified when:               │
   │    • Someone claims your request    │
   │    • You receive a new message      │
   │    • Community posts new requests   │
   │                                     │
   │   ┌─────────────────────────────┐   │
   │   │   Enable Notifications      │   │
   │   └─────────────────────────────┘   │
   │                                     │
   │           Maybe Later               │
   │                                     │
   └─────────────────────────────────────┘
   ```
3. If user taps "Enable Notifications", system dialog appears
4. If user taps "Maybe Later", skip and don't ask again for 7 days

**If denied**:
- User can still use app fully
- In Settings, show how to enable:
  - Title: "Notifications Disabled"
  - Message: "You won't receive alerts for new messages or when someone claims your requests."
  - Button: "Enable in Settings" (deep link)

### 4.5 Face ID / Touch ID Permission (Phase 5)

**When triggered**: First time user enables biometric unlock in Settings

**Flow**:
1. User toggles "Use Face ID" in app settings
2. System dialog appears with Info.plist description
3. User completes Face ID/Touch ID verification
4. If successful, biometric unlock enabled

**If denied**:
- Biometric option remains off
- No error shown (user made choice)

---

## 5. Phone Number Visibility Disclosure

### 5.1 In-App Disclosure

**Requirement PRIV-PHONE-001**: When user first adds phone number, show disclosure:

```
┌─────────────────────────────────────┐
│   Phone Number                      │
│   ┌─────────────────────────────┐   │
│   │ (206) 555-1234              │   │
│   └─────────────────────────────┘   │
│   ⓘ Your phone number will be      │
│   visible to community members      │
│   for ride coordination.            │
└─────────────────────────────────────┘
```

### 5.2 First-Time Confirmation

**Requirement PRIV-PHONE-002**: First time saving phone number, show confirmation:

- Title: "Phone Number Visibility"
- Message: "Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?"
- Actions: "Yes, Save Number", "Cancel"

### 5.3 Phone Masking on Public Profiles (historical requirement)

**Requirement PRIV-PHONE-003**: Phone numbers masked by default on public profiles:
- Display: `(•••) •••-4321`
- "Reveal Number" button to show full number
- Auto-reveal if users are in active conversation or same request

### 5.4 Current server behaviour (verified 2026-10-18)

The requirements above predate the 2026-04 profiles split. What the server does today:

- `phone_number` and `email` are readable only from `profiles`, whose SELECT policies are `profiles_select_own` and `profiles_select_admin` (platform admins) (`20260416_0002`). `public_profiles` exposes `id, name, avatar_url, car, approved, created_at, updated_at` only. No community RPC returns email or phone (`get_community_members`, `20261017_0005` block 29).
- So a phone number is visible to its owner and to platform admins only. The in-app copy (`edit_profile_phone_disclosure`: "only visible to members who you are in an active ride or favor with") promises at most that; the privacy policy states the server behaviour. If a counterpart-visible phone path is ever added, update both.

## 5A. Community Visibility Disclosures (multi-community, Phase 2)

Who sees what, as stated in `Legal/PRIVACY_POLICY.md` §6.1, with the server source:

| Viewer | Sees | Never sees | Source |
|--------|------|-----------|--------|
| Members of a community you belong to | Name, photo, car, role, join date; your requests, Q&A and Town Hall posts in that community | Email, phone, application answers | `public_profiles` / `my_visible_profile_ids` (`20261017_0002` V3, `20261017_0001` 1c.8); `get_community_members` non-admin branch |
| Owners and admins of a community you apply to, belong to, left or were removed from | The above plus application answers, who invited you, request and join dates, removal note | Email, phone, who reported content | `get_community_members` admin branch (`20261017_0005` block 29); reports SELECT policies (`20261005_0022`) |
| Guests (no account) | Public communities only: requests without addresses, their Q&A and reviews, Town Hall posts, members' name, photo, car | Everything in private communities | `guest_rides` / `guest_favors`, anon policies A17 / A24, `public_profiles` anon branch (`20261017_0002`) |
| Platform admins | Admin access to every live community (including private), every report and its reporter, email and phone | n/a | `my_admin_community_ids` (`20261017_0001`), `handle_new_report` recipients (`20261017_0003` call 10), `profiles_select_admin` |

In-app sentences that carry this disclosure: `community_join_disclosure` (join sheet), the report sheet's reporter-privacy line, and guideline 7 (`guidelines_7_title` / `guidelines_7_body`).

---

## 6. Data Retention

### 6.1 Retention Periods

| Data Type | Retention Period | Deletion Method |
|-----------|------------------|-----------------|
| User profile | Until account deletion | Admin-initiated |
| Email address | Until account deletion | Admin-initiated |
| Phone number | Until user removes or account deletion | User or admin |
| Profile photo | Until user changes or account deletion | User or admin |
| Ride/Favor requests | Indefinite | Admin-initiated |
| Messages | Indefinite | Not currently supported |
| Reviews | Indefinite | Admin-initiated |
| Push tokens | Until logout or 90-day cleanup | Automatic |
| Community memberships, application answers, removal notes | Until account deletion (a left or removed membership keeps its row) | Cascade on account deletion |
| Invite redemptions, invite code attempts, owned-limit requests | Until account deletion | Cascade on account deletion |
| Invite codes created | Until revoked or expired | Revoked and unlinked on the creator's account deletion |
| Membership event log | Indefinite (append-only) | Anonymised on account deletion (user and reason nulled) |
| Location data | Not stored | N/A (real-time only) |

### 6.2 Account Deletion

**Current state**: Self-service in the app (My Profile → Delete Account), through `delete_user_account` (`20261017_0004`), which has no precondition (App Store 5.1.1(v)).

**Communities (decision A3)**: a community whose only owner deletes their account passes to its longest-standing other admin; with no other admin it is archived and every member is told. The default community is never archived while a member remains (ownership passes to a member, platform admins first). The app lists the communities that would close and asks for confirmation before the final step; the server applies the rules either way.

### 6.3 Data Export

Not currently implemented. Future consideration for GDPR/CCPA compliance if expanding internationally.

---

## 7. Third-Party Data Sharing

### 7.1 Current Third Parties

| Service | Data Shared | Purpose |
|---------|-------------|---------|
| Supabase | All app data | Backend infrastructure |
| Apple (APNs) | Device tokens, notification content | Push notifications |

### 7.2 Data Sale

**Statement**: Naar's Cars does NOT sell user data to third parties.

### 7.3 Advertising

**Statement**: Naar's Cars does NOT use user data for advertising purposes.

---

## 8. Settings Deep-Links

### 8.1 Implementation

**Requirement PRIV-SETTINGS-001**: Provide deep-link to Settings for re-enabling permissions:

```swift
func openAppSettings() {
    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString),
          UIApplication.shared.canOpenURL(settingsUrl) else {
        return
    }
    UIApplication.shared.open(settingsUrl)
}
```

### 8.2 When to Offer

Show "Open Settings" button when:
- Photo access denied and user tries to add photo
- Location denied and user opens map (Phase 5)
- Notifications denied and user wants to enable

---

## 9. Pre-Submission Checklist

### 9.1 Info.plist

- [ ] `NSCameraUsageDescription` added (if camera used)
- [ ] `NSPhotoLibraryUsageDescription` added
- [ ] `NSLocationWhenInUseUsageDescription` added (Phase 5)
- [ ] `NSFaceIDUsageDescription` added (Phase 5)
- [ ] All descriptions are clear and accurate

### 9.2 App Store Connect

- [ ] Privacy Nutrition Labels completed
- [ ] All data types accurately declared
- [ ] "Data Linked to You" correctly selected
- [ ] "Data Used to Track You" set to No
- [ ] Privacy policy URL provided

### 9.3 In-App

- [ ] Phone number visibility disclosure implemented
- [ ] First-time phone confirmation alert implemented
- [ ] Push notification pre-permission screen implemented
- [ ] Settings deep-links work for denied permissions
- [ ] Permission denial handled gracefully (no crashes)

### 9.4 Testing

- [ ] Tested granting each permission
- [ ] Tested denying each permission
- [ ] Verified app works with all permissions denied
- [ ] Verified Settings deep-link opens correct screen

---

## 10. Privacy Policy

### 10.1 Requirements

A privacy policy URL is REQUIRED for App Store submission.

### 10.2 Policy Must Include

- What data is collected
- How data is used
- Data sharing practices
- Data retention periods
- User rights (access, deletion)
- Contact information

### 10.3 Hosting

Privacy policy should be hosted at a stable URL, e.g.:
- `https://naarscars.com/privacy`
- Or a simple hosted page on Notion, GitHub Pages, etc.

---

*End of Privacy Disclosures*
