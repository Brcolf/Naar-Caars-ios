# Apple Sign-In Error 1000 Fix

## Error Description
```
Error An unexpected error occurred: The operation couldn't be completed. 
(com.apple.authenticationservices.authorizationError error 1000.)
```

## Root Cause
Error 1000 from `ASAuthorizationError` typically occurs due to configuration mismatches between your Xcode project and Apple Developer Portal settings.

## Current Configuration
- **Bundle ID**: `com.NaarsCars`
- **Entitlements**: Sign in with Apple capability is present (`NaarsCars.entitlements`)
- **Implementation**: Native iOS Sign in with Apple using AuthenticationServices

## Step-by-Step Fix

### 1. Verify Bundle Identifier in Xcode

1. Open Xcode and select the `NaarsCars` project in the navigator
2. Select the `NaarsCars` target
3. Go to the **Signing & Capabilities** tab
4. Verify the **Bundle Identifier** is exactly: `com.NaarsCars`
5. Ensure you have a valid team selected under **Team**

### 2. Check Sign in with Apple Capability in Xcode

1. In the **Signing & Capabilities** tab
2. Look for **Sign in with Apple** capability
3. If it's not there:
   - Click the **+ Capability** button
   - Search for "Sign in with Apple"
   - Add it to your project
4. Verify it shows as enabled with no errors

### 3. Configure Apple Developer Portal

This is the most critical step. Go to [developer.apple.com](https://developer.apple.com):

#### a. Configure the App ID

1. Navigate to **Certificates, Identifiers & Profiles**
2. Click **Identifiers** in the sidebar
3. Find your App ID `com.NaarsCars`
4. Click on it to edit
5. Scroll down to **Sign in with Apple**
6. **Check the box** to enable "Sign in with Apple"
7. Click **Edit** next to Sign in with Apple
8. Configure as:
   - ☑️ Enable as a primary App ID
   - Group with: (leave blank for primary)
9. Click **Save**
10. Click **Continue** and **Save** again to update the App ID

#### b. Create/Verify App ID Configuration (Important!)

For Sign in with Apple to work, you need both an App ID AND properly configured certificates:

1. In **Identifiers**, click the **+** button
2. Select **App IDs** and click Continue
3. Select **App** and click Continue
4. Fill in:
   - **Description**: Naar's Cars
   - **Bundle ID**: Select "Explicit" and enter `com.NaarsCars`
5. Under **Capabilities**, check:
   - ☑️ Sign in with Apple
   - ☑️ Push Notifications (if you use them)
6. Click **Continue** and then **Register**

#### c. Regenerate Provisioning Profiles

After enabling Sign in with Apple, your provisioning profiles need to be updated:

1. Go to **Profiles** in the sidebar
2. Find your development and distribution profiles for `com.NaarsCars`
3. Click on each profile
4. Click **Edit**
5. Click **Generate** to regenerate the profile
6. Download and install the new profiles

### 4. Update Xcode Provisioning

1. In Xcode, go to **Xcode > Settings > Accounts**
2. Select your Apple ID
3. Select your team
4. Click **Download Manual Profiles** or **Manage Certificates**
5. Close and reopen Xcode
6. In your project's **Signing & Capabilities**:
   - Either let Xcode manage signing automatically (recommended for development)
   - Or manually select the updated provisioning profiles

### 5. Clean Build and Reinstall

**IMPORTANT**: After making configuration changes, you must:

1. Clean the build folder:
   - In Xcode: **Product > Clean Build Folder** (Shift+Cmd+K)
2. Delete the app from your device/simulator:
   - Long press the app icon and delete it
3. Rebuild and install:
   - **Product > Run** (Cmd+R)

### 6. Test on Physical Device

Sign in with Apple sometimes behaves differently between simulator and device:

1. **Test on a physical device** running iOS 13.0 or later
2. Ensure you're signed in to iCloud on the device
3. The device should have Sign in with Apple enabled in Settings

### 7. Verify Entitlements File

Check that your entitlements file is properly configured:

**File**: `NaarsCars/NaarsCars/NaarsCars.entitlements`

Should contain:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

✅ This is already correct in your project.

### 8. Check Info.plist (Optional but Recommended)

Add a usage description for better UX:

```xml
<key>NSAppleIDUsageDescription</key>
<string>Sign in to Naar's Cars with your Apple ID</string>
```

## Common Causes of Error 1000

| Issue | Solution |
|-------|----------|
| Bundle ID mismatch | Ensure Xcode and Developer Portal use exact same Bundle ID |
| Sign in with Apple not enabled in Portal | Enable in App ID configuration |
| Outdated provisioning profiles | Regenerate and download new profiles |
| Testing on simulator without proper setup | Test on physical device signed into iCloud |
| App not deleted after config changes | Delete app and reinstall |
| Team mismatch | Ensure same team in Xcode and Portal |
| Missing entitlements | Add Sign in with Apple capability in Xcode |

## Verification Steps

After completing the fixes above:

1. **Build succeeds without entitlement errors**
2. **App installs on device**
3. **Clicking "Sign in with Apple" shows the Apple authorization sheet**
4. **No error 1000 appears**

## Current Implementation Details

### Files Affected by This Fix
- ✅ `AuthService+AppleSignIn.swift` - Updated linking logic to use user metadata
- ✅ `NaarsCars.entitlements` - Already has correct configuration
- ⚠️ Apple Developer Portal - Needs manual configuration

### What Was Fixed in Code
1. **Removed OAuth redirect flow** - The previous `linkIdentity(provider: .apple)` was trying to use web OAuth flow
2. **Implemented metadata-based linking** - Now stores Apple user ID in user metadata
3. **Proper session handling** - Doesn't invalidate current session during linking

### Testing the Fix

After applying the Developer Portal configuration:

1. **Sign in with regular email/password**
2. **Go to Settings**
3. **Tap "Link Apple ID"**
4. **You should see the Apple authorization sheet** (no error 1000)
5. **Complete authorization with Face ID/Touch ID**
6. **Settings should show "Apple ID Linked" ✓**

## Still Having Issues?

If error 1000 persists after following all steps:

1. **Check your Apple Developer account status**
   - Ensure your membership is active
   - Verify you have proper permissions

2. **Try a different device**
   - Some devices may have cached credential issues

3. **Check Xcode console logs**
   - Look for more detailed error messages

4. **Verify Supabase configuration**
   - Ensure Apple Sign-In provider is enabled in Supabase Dashboard
   - Check that your Supabase project has the correct Apple bundle ID configured

5. **Contact Apple Developer Support**
   - If configuration is correct but still failing, it may be an Apple-side issue

## Additional Resources

- [Apple Sign in with Apple Documentation](https://developer.apple.com/documentation/sign_in_with_apple)
- [Supabase Apple Sign-In Guide](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [ASAuthorizationError Codes](https://developer.apple.com/documentation/authenticationservices/asauthorizationerror)

## Summary

The error 1000 is almost always a configuration issue between Xcode and Apple Developer Portal. The most critical steps are:

1. ✅ Enable "Sign in with Apple" in your App ID on Apple Developer Portal
2. ✅ Regenerate your provisioning profiles
3. ✅ Clean build and reinstall the app
4. ✅ Test on a physical device

The code changes I made fix the linking implementation to properly handle the Apple credential without causing session invalidation.

## Next Step: Supabase Configuration

After fixing error 1000, you may encounter an **audience error**:
```
Unacceptable audience in id_token: [com.NaarsCars]
```

This means Supabase needs to be configured to accept your Bundle ID. See **`SUPABASE-APPLE-SIGNIN-CONFIG.md`** for the complete Supabase setup guide.

