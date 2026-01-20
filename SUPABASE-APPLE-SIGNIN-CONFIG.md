# Fix: Supabase Apple Sign-In Audience Error

## Error
```
An unexpected error occurred: Unacceptable audience in id_token: [com.NaarsCars]
```

## What This Means

This error occurs because:
1. ✅ Apple Sign-In is working correctly (no more error 1000!)
2. ✅ Apple is issuing a valid ID token with audience `com.NaarsCars` (your Bundle ID)
3. ❌ Supabase is **rejecting** the token because it expects a different audience

## Root Cause

For **native iOS apps**, Apple issues ID tokens with the **Bundle ID** as the audience. However, Supabase's Apple Sign-In provider is typically configured for **web OAuth flows**, which expect a **Service ID** as the audience.

## Solution Options

There are **two approaches** to fix this. **Option 1** is recommended for native iOS apps.

---

## ⭐ Option 1: Configure Supabase for Native iOS (Recommended)

This approach configures Supabase to accept your Bundle ID as the audience, which is the correct setup for native iOS apps.

### Step 1: Create Apple Service ID (if you don't have one)

Even though we're using native iOS, we still need a Service ID for Supabase configuration:

1. Go to [developer.apple.com](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **+** button
4. Select **Services IDs** and click **Continue**
5. Fill in:
   - **Description**: `Naar's Cars Auth Service`
   - **Identifier**: `com.NaarsCars.auth` (or any unique identifier)
6. Click **Continue** and **Register**

### Step 2: Configure the Service ID for Sign in with Apple

1. Click on your newly created Service ID
2. Check **Sign in with Apple**
3. Click **Configure**
4. Set:
   - **Primary App ID**: Select `com.NaarsCars`
   - **Website URLs**: (leave empty for now, we'll configure later if needed)
5. Click **Save** and **Continue**

### Step 3: Get Your Apple Team ID

You'll need this for Supabase:

1. In [developer.apple.com](https://developer.apple.com)
2. Go to **Membership** (in the sidebar)
3. Copy your **Team ID** (looks like: `ABC123XYZ`)

### Step 4: Create Apple Sign-In Key

1. In **Certificates, Identifiers & Profiles**
2. Click **Keys** in the sidebar
3. Click the **+** button
4. Enter a name: `Naar's Cars Sign in with Apple Key`
5. Check **Sign in with Apple**
6. Click **Configure** next to Sign in with Apple
7. Select your **Primary App ID**: `com.NaarsCars`
8. Click **Save** and **Continue**
9. Click **Register**
10. **Download the key file** (`.p8` file) - you can only download this **ONCE**!
11. Note the **Key ID** shown (looks like: `AB12CD34EF`)

### Step 5: Configure Supabase Dashboard

Now configure Supabase to accept native iOS tokens:

1. Go to your [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Navigate to **Authentication** → **Providers**
4. Find **Apple** in the list and click to expand
5. Enable Apple provider if not already enabled
6. Configure these fields:

   **For Native iOS Apps:**
   - **Authorized Client IDs**: Add your Bundle ID here!
     ```
     com.NaarsCars
     ```
     This is the critical field! Add additional ones if needed (comma-separated):
     ```
     com.NaarsCars, com.NaarsCars.auth
     ```
   
   **Standard Configuration:**
   - **Services ID (OAuth Client ID)**: `com.NaarsCars.auth` (your Service ID)
   - **Secret (OAuth Client Secret)**: (leave blank, we'll generate this)
   - **Team ID**: Your Apple Team ID (e.g., `ABC123XYZ`)
   - **Key ID**: The Key ID from Step 4 (e.g., `AB12CD34EF`)
   - **Private Key**: Open your `.p8` file in a text editor and paste the entire contents, including the BEGIN/END lines:
     ```
     -----BEGIN PRIVATE KEY-----
     ... key content ...
     -----END PRIVATE KEY-----
     ```

7. Click **Save**

### Step 6: Important - Redirect URLs (for future web support)

If you plan to support web later, also configure:

- **Site URL**: `https://yourapp.com` (or your actual domain)
- **Redirect URLs**: 
  ```
  https://<your-project-ref>.supabase.co/auth/v1/callback
  ```

For now, you can leave these blank since you're only using native iOS.

### Step 7: Test the Configuration

1. Clean build in Xcode: **Product > Clean Build Folder** (Shift+Cmd+K)
2. Delete app from device/simulator
3. Rebuild and run
4. Try Sign in with Apple again
5. Should work without audience error! ✅

---

## Option 2: Update iOS App to Use Service ID (Alternative)

If you want to use a Service ID instead of Bundle ID, you need to modify the iOS code. This is **NOT recommended** for native iOS apps.

### Modify `AuthService+AppleSignIn.swift`

Replace the `signInWithIdToken` calls to include the Service ID as the audience:

```swift
// Add this function to validate and modify the token
private func getServiceIDToken(from credential: ASAuthorizationAppleIDCredential) throws -> String {
    guard let identityTokenData = credential.identityToken,
          let identityToken = String(data: identityTokenData, encoding: .utf8) else {
        throw AppError.unknown("Failed to get Apple identity token")
    }
    
    // The token audience will be the Bundle ID by default
    // For Supabase, we might need to use a Service ID
    // Note: This requires additional configuration in Apple Developer Portal
    return identityToken
}
```

However, this approach has limitations and is not the standard way to handle native iOS Sign in with Apple.

---

## Verification Checklist

After completing the configuration:

- [ ] Service ID created and configured in Apple Developer Portal
- [ ] Sign in with Apple Key created and downloaded
- [ ] Supabase Apple provider enabled
- [ ] **Bundle ID added to "Authorized Client IDs" in Supabase** ← CRITICAL!
- [ ] Team ID, Key ID, and Private Key configured in Supabase
- [ ] Clean build and reinstall app
- [ ] Test Sign in with Apple (should work without audience error)

## Common Issues

### Issue: Still getting audience error

**Check:**
- Verify you added `com.NaarsCars` to **Authorized Client IDs** in Supabase
- Make sure there are no typos (exact match required)
- Try adding both Bundle ID and Service ID (comma-separated)
- Clear Supabase dashboard cache (logout and login again)

### Issue: "Invalid JWT" error

**Fix:**
- Verify your Private Key is pasted correctly (including BEGIN/END lines)
- Check Team ID and Key ID are correct
- Ensure the Key is enabled for Sign in with Apple in Developer Portal

### Issue: "Provider not enabled" error

**Fix:**
- Go to Supabase Dashboard → Authentication → Providers
- Make sure Apple toggle is ON (enabled)
- Click Save after making changes

## Important Notes

1. **Authorized Client IDs** is the key setting for native iOS apps
2. The Bundle ID must match exactly: `com.NaarsCars`
3. Private key can only be downloaded once - keep it safe!
4. Changes to Supabase config may take a few minutes to propagate

## Testing Different Flows

After configuration:

### Test 1: New User Sign Up with Apple
1. Ensure you have a valid invite code
2. Click "Sign in with Apple" on signup
3. Enter invite code when prompted
4. Should create account successfully ✅

### Test 2: Existing User Login with Apple  
1. Sign in with Apple on login screen
2. Should log in without asking for invite code ✅

### Test 3: Link Apple ID to Email Account
1. Sign in with email/password
2. Go to Settings
3. Tap "Link Apple ID"
4. Should link successfully ✅

## Troubleshooting

### Check Supabase Logs

1. Go to Supabase Dashboard
2. Navigate to **Logs** → **Auth Logs**
3. Look for recent Apple Sign-In attempts
4. Check for error messages that might provide more details

### Enable Supabase Debug Logging

Add to your `SupabaseService.swift`:

```swift
// When initializing client, add:
let client = SupabaseClient(
    supabaseURL: URL(string: supabaseURL)!,
    supabaseKey: supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: AuthClientOptions(
            logLevel: .verbose // Add this for debugging
        )
    )
)
```

### Test with cURL (Advanced)

You can test the token validation directly:

```bash
curl -X POST 'https://<your-project>.supabase.co/auth/v1/token?grant_type=id_token' \
  -H "apikey: <your-anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "apple",
    "id_token": "<your-apple-id-token>"
  }'
```

This will show you the exact error from Supabase.

## Summary

The "Unacceptable audience" error means Supabase doesn't recognize your Bundle ID as a valid audience. Fix it by:

1. ✅ Creating Apple Service ID and Key
2. ✅ Adding your Bundle ID to **Authorized Client IDs** in Supabase
3. ✅ Configuring Team ID, Key ID, and Private Key in Supabase
4. ✅ Clean build and test

The key field is **Authorized Client IDs** - this tells Supabase to accept tokens with your Bundle ID as the audience, which is what Apple issues for native iOS apps.

