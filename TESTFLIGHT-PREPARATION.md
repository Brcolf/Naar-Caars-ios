# TestFlight Beta Testing Preparation Guide

This guide outlines all steps needed to prepare the NaarsCars iOS app for TestFlight beta testing.

## Current Project Configuration

- **Bundle Identifier**: `com.NaarsCars`
- **Development Team**: `WT4DGUYKL4`
- **Marketing Version**: `1.0`
- **Current Project Version**: `1`
- **Deployment Target**: iOS 17.0
- **Code Signing**: Automatic

---

## Prerequisites Checklist

### ✅ Already Configured
- [x] Bundle identifier set
- [x] Development team configured
- [x] Privacy permission descriptions added
- [x] Push notification service implemented
- [x] App icon structure in place

### ⚠️ Needs Attention
- [ ] App icon images (1024x1024 required)
- [ ] Push notification entitlements
- [ ] App Store Connect app record
- [ ] Export compliance declaration
- [ ] Version/build number strategy
- [ ] App Store metadata

---

## Step-by-Step Preparation

### 1. App Store Connect Setup

#### 1.1 Create App Record
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **My Apps** → **+** → **New App**
3. Fill in:
   - **Platform**: iOS
   - **Name**: Naar's Cars (or your preferred name)
   - **Primary Language**: English
   - **Bundle ID**: `com.NaarsCars` (must match exactly)
   - **SKU**: `naars-cars-ios` (unique identifier, can be anything)
   - **User Access**: Full Access (or appropriate level)

#### 1.2 App Information
- **Category**: Social Networking
- **Subcategory**: (optional)
- **Privacy Policy URL**: (required for TestFlight) - Add your privacy policy URL

#### 1.3 Pricing and Availability
- Set to **Free** (or your pricing model)
- Select countries for availability

---

### 2. App Icon Requirements

#### 2.1 Create App Icon
- **Size**: 1024x1024 pixels
- **Format**: PNG (no transparency)
- **Color Space**: sRGB
- **No rounded corners** (iOS will add them)

#### 2.2 Add to Xcode
1. Open `NaarsCars/NaarsCars/Assets.xcassets/AppIcon.appiconset/`
2. Add the 1024x1024 image to the universal iOS slot
3. Ensure it's named correctly in Contents.json

**Current Status**: App icon structure exists but needs actual image files.

---

### 3. Push Notification Setup

#### 3.1 Create Entitlements File
1. In Xcode: **File** → **New** → **File** → **Property List**
2. Name it: `NaarsCars.entitlements`
3. Add to target: **NaarsCars**
4. Add key: `aps-environment` with value `production` (or `development` for testing)

#### 3.2 Enable Capabilities in Xcode
1. Select project → **NaarsCars** target → **Signing & Capabilities**
2. Click **+ Capability**
3. Add **Push Notifications**
4. Add **Background Modes** → Check **Remote notifications**

#### 3.3 APNs Key Setup (for Production)
1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create new **Key** (if not exists)
3. Enable **Apple Push Notifications service (APNs)**
4. Download `.p8` key file (save Key ID and Team ID)
5. Upload to Supabase Dashboard → Settings → Push Notifications

---

### 4. Version and Build Numbers

#### 4.1 Current State
- **Marketing Version**: `1.0`
- **Build Number**: `1`

#### 4.2 Strategy for TestFlight
- **Marketing Version**: Increment for major releases (1.0, 1.1, 2.0, etc.)
- **Build Number**: Increment for each TestFlight upload (1, 2, 3, etc.)

**Recommendation**: 
- First TestFlight: `1.0 (1)`
- Subsequent builds: `1.0 (2)`, `1.0 (3)`, etc.
- Major update: `1.1 (1)`, `1.1 (2)`, etc.

#### 4.3 Update in Xcode
1. Select project → **NaarsCars** target
2. **General** tab
3. Update **Version** and **Build** numbers
4. Or set in **Build Settings**:
   - `MARKETING_VERSION = 1.0`
   - `CURRENT_PROJECT_VERSION = 1` (increment for each build)

---

### 5. Export Compliance

#### 5.1 Encryption Declaration
Apple requires export compliance information for apps using encryption.

**Options:**
1. **No encryption** (if app doesn't use encryption beyond standard HTTPS)
2. **Uses encryption** (if using custom encryption)

**For NaarsCars**: Likely **"No encryption"** since we use standard HTTPS/TLS.

#### 5.2 Set in Xcode
1. Select project → **NaarsCars** target → **Info** tab
2. Add key: `ITSAppUsesNonExemptEncryption` = `NO` (if no custom encryption)
3. Or answer in App Store Connect when uploading

---

### 6. Build Configuration for Distribution

#### 6.1 Archive Build
1. In Xcode: **Product** → **Scheme** → **Edit Scheme**
2. Select **Archive** → Set **Build Configuration** to **Release**
3. Select **Any iOS Device** (not simulator) in device selector
4. **Product** → **Archive**

#### 6.2 Validate Archive
1. After archive completes, **Window** → **Organizer**
2. Select archive → **Validate App**
3. Fix any issues before uploading

#### 6.3 Distribute to App Store Connect
1. In Organizer, select archive → **Distribute App**
2. Choose **App Store Connect**
3. Select **Upload**
4. Follow wizard (automatic signing recommended)
5. Wait for processing (can take 10-60 minutes)

---

### 7. TestFlight Configuration

#### 7.1 Internal Testing
1. In App Store Connect → **TestFlight** tab
2. Add **Internal Testers** (up to 100, must be in your App Store Connect team)
3. Add tester emails
4. Select build → **Enable for Testing**

#### 7.2 External Testing
1. Create **Test Information**:
   - **What to Test**: Brief description of what testers should focus on
   - **Feedback Email**: Your email for beta feedback
   - **Marketing URL**: (optional) Link to your website
   - **Privacy Policy URL**: Required
2. Create **Test Group** (e.g., "Beta Testers")
3. Add external testers (up to 10,000)
4. Submit for **Beta App Review** (required for external testing)
   - Review typically takes 24-48 hours
   - Apple checks for crashes, guideline violations, etc.

#### 7.3 Beta App Review Requirements
- App must function without crashes
- Must comply with App Store Review Guidelines
- Must have privacy policy URL
- Must have contact information
- Must not be a demo/test app

---

### 8. Required Assets for App Store Connect

#### 8.1 Screenshots (Required for External Testing)
- **iPhone 6.7"** (iPhone 14 Pro Max, 15 Pro Max, etc.):
  - 1290 x 2796 pixels
  - At least 1 screenshot (up to 10)
- **iPhone 6.5"** (iPhone 11 Pro Max, XS Max):
  - 1242 x 2688 pixels
- **iPhone 5.5"** (iPhone 8 Plus):
  - 1242 x 2208 pixels

**Note**: For TestFlight, you can start with just one device size, but all are recommended.

#### 8.2 App Preview Video (Optional)
- 15-30 seconds
- Show key features
- Can be added later

#### 8.3 App Description
- **Name**: Naar's Cars (or your choice)
- **Subtitle**: Brief tagline (optional)
- **Description**: Full app description
- **Keywords**: Search keywords (comma-separated, max 100 characters)
- **Support URL**: Your support website
- **Marketing URL**: (optional) Your marketing website

---

### 9. Privacy Information

#### 9.1 Privacy Policy
- **Required**: Must have a privacy policy URL
- Must cover:
  - What data is collected
  - How data is used
  - Data sharing practices
  - User rights

#### 9.2 Privacy Practices (App Store Connect)
Answer questions about:
- Data collection (location, contacts, photos, etc.)
- Data usage
- Data tracking
- Third-party sharing

**For NaarsCars**:
- ✅ Location data (for map features)
- ✅ Photos (for profile and messages)
- ✅ Contacts (if used)
- ✅ User content (messages, posts)
- ❌ Tracking (if not using tracking)

---

### 10. Pre-Upload Checklist

Before creating archive:

- [ ] **App Icon**: 1024x1024 PNG added to Assets
- [ ] **Version Number**: Set appropriately (1.0)
- [ ] **Build Number**: Incremented from previous (1, 2, 3...)
- [ ] **Code Signing**: Automatic signing enabled with correct team
- [ ] **Entitlements**: Push notifications enabled (if using)
- [ ] **Privacy Descriptions**: All present in Info.plist
- [ ] **Bundle ID**: Matches App Store Connect exactly (`com.NaarsCars`)
- [ ] **Deployment Target**: iOS 17.0 (matches requirements)
- [ ] **Build Configuration**: Release mode
- [ ] **No Debug Code**: Remove print statements or use proper logging
- [ ] **Secrets**: Ensure production API keys/URLs are used (not test)
- [ ] **Database Migrations**: All run in production Supabase instance

---

### 11. Post-Upload Steps

#### 11.1 Wait for Processing
- Archive upload: ~5-10 minutes
- Processing: ~10-60 minutes
- Check App Store Connect → **TestFlight** → **Builds**

#### 11.2 Enable Build for Testing
1. Once processing completes, build appears in TestFlight
2. Click build → **Enable for Testing**
3. Add to test group
4. Testers receive email invitation

#### 11.3 Monitor Feedback
- Check **TestFlight** → **Feedback** tab
- Monitor crash reports in **Analytics**
- Review tester comments

---

### 12. Common Issues and Solutions

#### Issue: "Invalid Bundle"
- **Solution**: Ensure Bundle ID matches App Store Connect exactly
- Check for typos in `com.NaarsCars`

#### Issue: "Missing Compliance"
- **Solution**: Answer export compliance question in App Store Connect
- Or add `ITSAppUsesNonExemptEncryption = NO` to Info.plist

#### Issue: "Missing App Icon"
- **Solution**: Ensure 1024x1024 icon is in AppIcon asset catalog
- Verify it's assigned to the correct slot

#### Issue: "Push Notifications Not Working"
- **Solution**: Ensure entitlements file includes `aps-environment`
- Verify APNs key is uploaded to Supabase
- Check device token registration in logs

#### Issue: "Build Processing Failed"
- **Solution**: Check email from Apple for specific error
- Common causes: missing icons, invalid entitlements, code signing issues

---

### 13. Testing Checklist

Before submitting to TestFlight:

- [ ] **Core Features Work**:
  - [ ] User authentication (sign up, login, sign out)
  - [ ] Request creation (rides and favors)
  - [ ] Request claiming
  - [ ] Messaging
  - [ ] Notifications
  - [ ] Profile management
  - [ ] Town Hall/Community features

- [ ] **No Crashes**: Test on physical device
- [ ] **Performance**: App loads and responds quickly
- [ ] **Permissions**: All permission prompts work correctly
- [ ] **Deep Links**: Push notification navigation works
- [ ] **Localization**: Test in different languages (if applicable)

---

### 14. Quick Start Commands

#### Create Archive
```bash
# In Xcode:
# 1. Select "Any iOS Device" as target
# 2. Product → Archive
# 3. Wait for archive to complete
```

#### Check Build Settings
```bash
# Verify in Xcode:
# Project → Target → Build Settings
# Search for: MARKETING_VERSION, CURRENT_PROJECT_VERSION
```

#### Validate Bundle ID
```bash
# In Xcode:
# Project → Target → General → Bundle Identifier
# Should be: com.NaarsCars
```

---

### 15. Recommended Timeline

**Week 1: Preparation**
- Day 1-2: App Store Connect setup, create app record
- Day 3-4: Create app icon, screenshots
- Day 5: Configure entitlements, test build locally

**Week 2: First Upload**
- Day 1: Create archive, validate
- Day 2: Upload to App Store Connect
- Day 3: Wait for processing, enable for internal testing
- Day 4-5: Internal testing, fix critical issues

**Week 3: External Beta**
- Day 1: Submit for Beta App Review
- Day 2-3: Wait for review approval
- Day 4-5: Invite external testers, collect feedback

---

### 16. Important Notes

1. **Bundle ID Cannot Change**: Once set in App Store Connect, it's permanent
2. **Version Numbers**: Must always increment (can't go backwards)
3. **Build Numbers**: Must always increment for same version
4. **TestFlight Expiration**: Builds expire after 90 days
5. **Beta Review**: Required for external testing, not for internal
6. **Privacy Policy**: Required for external testing
7. **APNs**: Production builds need production APNs key

---

### 17. Next Steps After TestFlight

Once beta testing is complete:

1. **Collect Feedback**: Review all tester feedback
2. **Fix Critical Issues**: Address crashes and major bugs
3. **Prepare for App Store**: Complete all metadata, screenshots
4. **Submit for Review**: When ready for public release
5. **Monitor**: Track analytics, crash reports, user feedback

---

## Files to Create/Update

### Required Files
1. **NaarsCars.entitlements** (create if not exists)
   - Location: `NaarsCars/NaarsCars/NaarsCars.entitlements`
   - Content: Push notification entitlements

### Files to Update
1. **AppIcon.appiconset**: Add 1024x1024 icon image
2. **project.pbxproj**: Ensure version numbers are correct
3. **Info.plist**: Verify all privacy descriptions

---

## Support Resources

- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

## Quick Reference

| Item | Current Value | Required |
|------|--------------|----------|
| Bundle ID | `com.NaarsCars` | ✅ |
| Team ID | `WT4DGUYKL4` | ✅ |
| Version | `1.0` | ✅ |
| Build | `1` | ✅ |
| Deployment Target | iOS 17.0 | ✅ |
| App Icon | Structure exists, needs image | ⚠️ |
| Entitlements | Not found | ⚠️ |
| Privacy Policy URL | Not set | ⚠️ |

---

**Last Updated**: January 2025
**Status**: Ready for TestFlight preparation


