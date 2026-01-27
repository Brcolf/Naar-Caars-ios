# Complete Apple Sign-In Setup Guide

This guide combines all the steps needed to get Apple Sign-In working from start to finish.

## Overview of Common Errors

| Error | Meaning | Fix Document |
|-------|---------|--------------|
| **Error 1000** | Apple Developer Portal not configured | `APPLE-SIGN-IN-ERROR-1000-FIX.md` |
| **Unacceptable audience** | Supabase not configured for iOS Bundle ID | `SUPABASE-APPLE-SIGNIN-CONFIG.md` |

---

## Complete Setup Checklist

### Phase 1: Apple Developer Portal Configuration ✅

- [ ] **1.1** Sign in to [developer.apple.com](https://developer.apple.com)
- [ ] **1.2** Go to **Certificates, Identifiers & Profiles**
- [ ] **1.3** Navigate to **Identifiers** → Select App ID `com.NaarsCars`
- [ ] **1.4** Enable **Sign in with Apple** capability
- [ ] **1.5** Click **Edit** and configure as primary App ID
- [ ] **1.6** Save changes
- [ ] **1.7** Go to **Profiles** and regenerate provisioning profiles
- [ ] **1.8** Download and install new profiles

**Expected Result:** No more Error 1000 ✅

---

### Phase 2: Apple Service ID and Key Creation 🔑

- [ ] **2.1** In [developer.apple.com](https://developer.apple.com), go to **Identifiers**
- [ ] **2.2** Click **+** → Select **Services IDs** → Continue
- [ ] **2.3** Create Service ID:
  - Description: `Naar's Cars Auth Service`
  - Identifier: `com.NaarsCars.auth`
- [ ] **2.4** Register the Service ID
- [ ] **2.5** Click on Service ID → Enable **Sign in with Apple**
- [ ] **2.6** Configure with Primary App ID: `com.NaarsCars`
- [ ] **2.7** Go to **Membership** and copy your **Team ID**
- [ ] **2.8** Go to **Keys** → Click **+**
- [ ] **2.9** Create key:
  - Name: `Naar's Cars Sign in with Apple Key`
  - Enable **Sign in with Apple**
  - Configure with App ID: `com.NaarsCars`
- [ ] **2.10** Register and **download the .p8 key file** (can only download once!)
- [ ] **2.11** Note the **Key ID** displayed

**Expected Result:** You now have Service ID, Team ID, Key ID, and Private Key ✅

---

### Phase 3: Supabase Configuration 🗄️

- [ ] **3.1** Go to [Supabase Dashboard](https://supabase.com/dashboard)
- [ ] **3.2** Select your project
- [ ] **3.3** Navigate to **Authentication** → **Providers**
- [ ] **3.4** Find and expand **Apple** provider
- [ ] **3.5** Enable Apple provider (toggle ON)
- [ ] **3.6** Configure these fields:

```
✅ Authorized Client IDs: com.NaarsCars
   (This is the CRITICAL field for native iOS!)
   
✅ Services ID: com.NaarsCars.auth
   
✅ Team ID: [Your Team ID from step 2.7]
   
✅ Key ID: [Your Key ID from step 2.11]
   
✅ Private Key: [Paste entire .p8 file contents including BEGIN/END lines]
```

- [ ] **3.7** Click **Save**
- [ ] **3.8** Wait 2-3 minutes for changes to propagate

**Expected Result:** Supabase accepts Apple tokens with Bundle ID as audience ✅

---

### Phase 4: Xcode Clean Build 🧹

- [ ] **4.1** Open Xcode
- [ ] **4.2** **Product** → **Clean Build Folder** (Shift+Cmd+K)
- [ ] **4.3** Delete app from device/simulator (long-press icon → delete)
- [ ] **4.4** **Product** → **Run** (Cmd+R)

**Expected Result:** App builds and installs with updated configuration ✅

---

### Phase 5: Testing 🧪

#### Test 1: New User Signup with Apple
- [ ] **5.1** Open app (not signed in)
- [ ] **5.2** Navigate to signup screen
- [ ] **5.3** Tap "Sign in with Apple"
- [ ] **5.4** Enter a valid invite code
- [ ] **5.5** Complete Apple authorization
- [ ] **5.6** Verify account is created and you're logged in

**Expected Result:** ✅ No errors, account created successfully

#### Test 2: Existing User Login with Apple
- [ ] **5.7** Sign out from the app
- [ ] **5.8** On login screen, tap "Sign in with Apple"
- [ ] **5.9** Complete Apple authorization
- [ ] **5.10** Verify you're logged in (no invite code required)

**Expected Result:** ✅ No errors, logged in successfully

#### Test 3: Link Apple ID to Email Account
- [ ] **5.11** Sign in with email/password
- [ ] **5.12** Go to Profile → Settings
- [ ] **5.13** Tap "Link Apple ID"
- [ ] **5.14** Complete Apple authorization
- [ ] **5.15** Verify Settings shows "Apple ID Linked" ✓

**Expected Result:** ✅ No errors, Apple ID linked successfully

---

## Quick Troubleshooting

### Still Getting Error 1000?

**Check:**
1. Did you enable Sign in with Apple in **App ID** (not just Service ID)?
2. Did you regenerate **provisioning profiles**?
3. Did you **clean build** and **delete app** before reinstalling?
4. Are you testing on a device with valid Apple ID signed in?

**Fix:** See `APPLE-SIGN-IN-ERROR-1000-FIX.md` for detailed steps

---

### Still Getting "Unacceptable audience" Error?

**Check:**
1. Did you add `com.NaarsCars` to **Authorized Client IDs** in Supabase?
2. Is the Bundle ID spelled exactly: `com.NaarsCars` (case-sensitive)?
3. Did you paste the **complete private key** including BEGIN/END lines?
4. Did you wait 2-3 minutes after saving Supabase config?

**Fix:** See `SUPABASE-APPLE-SIGNIN-CONFIG.md` for detailed steps

---

### Other Errors?

**Check Supabase Auth Logs:**
1. Supabase Dashboard → **Logs** → **Auth Logs**
2. Look for recent Apple Sign-In attempts
3. Review error messages for more details

**Check Xcode Console:**
1. Run app from Xcode
2. Open Console (Cmd+Shift+Y)
3. Filter for "Apple" or "Auth"
4. Look for detailed error messages

---

## Important Files in Your Project

| File | Purpose |
|------|---------|
| `NaarsCars/NaarsCars/NaarsCars.entitlements` | Sign in with Apple capability ✅ |
| `NaarsCars/Core/Services/AuthService+AppleSignIn.swift` | Apple Sign-In implementation ✅ |
| `NaarsCars/Features/Authentication/Views/AppleSignInButton.swift` | Apple button UI ✅ |
| `NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift` | Apple Sign-In logic ✅ |

All files are already implemented and correct! ✅

---

## Configuration Summary

### What You Need

| Item | Value | Where to Get It |
|------|-------|-----------------|
| Bundle ID | `com.NaarsCars` | Xcode project settings |
| Service ID | `com.NaarsCars.auth` | Apple Developer Portal → Create |
| Team ID | `ABC123XYZ` | Apple Developer Portal → Membership |
| Key ID | `AB12CD34EF` | Apple Developer Portal → Keys |
| Private Key | `.p8 file contents` | Download from Keys page (once!) |

### Where to Configure

| Setting | Location | Critical Field |
|---------|----------|----------------|
| Sign in with Apple capability | Apple Developer Portal → App ID | ✅ Enable checkbox |
| Provisioning Profiles | Apple Developer Portal → Profiles | ✅ Regenerate |
| Apple Provider | Supabase → Authentication → Providers | ✅ Authorized Client IDs |

---

## Success Criteria ✅

When everything is working correctly:

✅ No Error 1000 (Apple Developer Portal configured)  
✅ No "Unacceptable audience" error (Supabase configured)  
✅ Apple authorization sheet appears when clicking button  
✅ New users can sign up with Apple (with invite code)  
✅ Existing users can log in with Apple  
✅ Users can link Apple ID to email/password accounts  
✅ Settings shows "Apple ID Linked" when linked  

---

## Need Help?

1. **Error 1000**: Read `APPLE-SIGN-IN-ERROR-1000-FIX.md`
2. **Audience Error**: Read `SUPABASE-APPLE-SIGNIN-CONFIG.md`
3. **Configuration Check**: Run `./verify-apple-signin-config.sh`
4. **Still Stuck**: Check Supabase Auth Logs and Xcode Console

---

## Estimated Time to Complete

- **Phase 1** (Apple Developer Portal): 15-20 minutes
- **Phase 2** (Service ID and Key): 10-15 minutes
- **Phase 3** (Supabase): 5-10 minutes
- **Phase 4** (Clean Build): 2-3 minutes
- **Phase 5** (Testing): 10-15 minutes

**Total**: ~45-60 minutes for complete setup

---

*Last Updated: January 2026*


