# Step-by-Step Setup: send-message-push Edge Function

## Prerequisites Checklist

Before starting, make sure you have:
- [ ] Your Supabase project URL
- [ ] Your Supabase service role key (found in Settings → API)
- [ ] Your APNs key (.p8 file) from Apple Developer Portal
- [ ] Your APNs Key ID and Team ID from Apple Developer Portal
- [ ] Your app's Bundle ID (e.g., `com.naarscars.app`)

---

## Step 1: Deploy the Edge Function

### 1.1 Open Terminal

**Where**: On your Mac, open Terminal (or iTerm)

**Location**: Navigate to your project root directory:
```bash
cd /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs
```

### 1.2 Login to Supabase CLI

**Command** (run in Terminal):
```bash
supabase login
```

**What happens**: A browser window will open. Log in with your Supabase account.

### 1.3 Link to Your Project

**Command** (run in Terminal):
```bash
supabase link --project-ref YOUR_PROJECT_REF
```

**How to get YOUR_PROJECT_REF**:
1. Go to your Supabase Dashboard: https://app.supabase.com
2. Click on your project
3. In the URL bar, you'll see: `https://app.supabase.com/project/YOUR_PROJECT_REF`
4. Copy `YOUR_PROJECT_REF` from the URL

**Example**: If URL is `https://app.supabase.com/project/abcdefghijklmnop`, then `abcdefghijklmnop` is your project ref.

### 1.4 Deploy the Function

**Command** (run in Terminal):
```bash
supabase functions deploy send-message-push
```

**What happens**: The function will be uploaded to Supabase. Wait for "Deployed successfully" message.

---

## Step 2: Configure Environment Variables

### 2.1 Open Supabase Dashboard

**Where**: Open your web browser and go to:
```
https://app.supabase.com
```

**Click**: Your project name to open it

### 2.2 Navigate to Edge Functions

**Where in Supabase UI**:
1. In the left sidebar, click **"Edge Functions"** (it's in the main navigation menu)
2. You'll see a list of functions including `send-message-push`
3. **Click** on `send-message-push` to open its details page

### 2.3 Open Settings Tab

**Where in Supabase UI**:
1. At the top of the `send-message-push` page, you'll see tabs: **Overview**, **Logs**, **Settings**
2. **Click** on the **"Settings"** tab

### 2.4 Add Environment Variables

**Where in Supabase UI**:
1. In the Settings tab, scroll down to **"Secrets"** section
2. You'll see a list of existing secrets (may be empty)
3. **Click** the **"+ New Secret"** button (or "Add Secret" button)

**For each secret below, repeat these steps**:
- **Click** "+ New Secret"
- Enter the **Name** (exactly as shown below)
- Enter the **Value** (see instructions for each)
- **Click** "Save" or "Add"

#### Secret 1: APNS_TEAM_ID

**Name** (exactly): `APNS_TEAM_ID`

**Value**: Your Apple Team ID

**How to find it**:
1. Go to https://developer.apple.com/account
2. Click "Membership" in the left sidebar
3. Your Team ID is shown at the top (format: `ABC123DEF4`)
4. Copy it exactly

**Example Value**: `ABC123DEF4`

---

#### Secret 2: APNS_KEY_ID

**Name** (exactly): `APNS_KEY_ID`

**Value**: Your APNs Key ID

**How to find it**:
1. Go to https://developer.apple.com/account/resources/authkeys/list
2. Find the key you created for push notifications
3. The Key ID is shown in the list (format: `XYZ987ABC`)
4. Copy it exactly

**Example Value**: `XYZ987ABC`

---

#### Secret 3: APNS_KEY

**Name** (exactly): `APNS_KEY`

**Value**: Your APNs private key file content (base64 encoded)

**How to get it**:

**Option A: Using Terminal (Recommended)**

1. **Open Terminal** on your Mac
2. Navigate to where your `.p8` file is saved (usually Downloads):
   ```bash
   cd ~/Downloads
   ```
3. List files to find your key:
   ```bash
   ls *.p8
   ```
4. Base64 encode the file:
   ```bash
   base64 -i AuthKey_XYZ987ABC.p8
   ```
   (Replace `AuthKey_XYZ987ABC.p8` with your actual filename)
5. **Copy the entire output** (it will be a long string of characters)
6. Paste it into the **Value** field in Supabase

**Option B: Using Finder**

1. Find your `.p8` file in Finder
2. Right-click → "Open With" → "TextEdit"
3. Copy the entire contents (including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines)
4. Go to https://www.base64encode.org/
5. Paste the content and click "Encode"
6. Copy the encoded result
7. Paste it into the **Value** field in Supabase

**Example Value** (starts with): `LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t...`

**Important**: The key should include the PEM headers when you paste it:
```
-----BEGIN PRIVATE KEY-----
[base64 content here]
-----END PRIVATE KEY-----
```

---

#### Secret 4: APNS_BUNDLE_ID

**Name** (exactly): `APNS_BUNDLE_ID`

**Value**: Your app's bundle identifier

**How to find it**:
1. Open your Xcode project
2. Select your project in the left sidebar
3. Select your app target (usually "NaarsCars")
4. Go to the **"General"** tab
5. Look for **"Bundle Identifier"**
6. Copy it exactly

**Example Value**: `com.naarscars.app`

---

#### Secret 5: APNS_PRODUCTION

**Name** (exactly): `APNS_PRODUCTION`

**Value**: 
- `false` for testing/development (use sandbox APNs)
- `true` for production (use production APNs)

**For now, use**: `false`

**Example Value**: `false`

---

## Step 3: Get Your Service Role Key

### 3.1 Navigate to API Settings

**Where in Supabase UI**:
1. In the left sidebar, click **"Settings"** (gear icon at the bottom)
2. In the Settings page, click **"API"** in the left submenu

### 3.2 Copy Service Role Key

**Where in Supabase UI**:
1. Scroll down to find **"Project API keys"** section
2. Find the row labeled **"service_role"** (it has a red background warning)
3. **Click** the **"Copy"** button (or eye icon to reveal, then copy)
4. **Save this key** - you'll need it in Step 4

**Important**: Keep this key secret! Never commit it to git.

---

## Step 4: Create Database Webhook

### 4.1 Navigate to Database Webhooks

**Where in Supabase UI**:
1. In the left sidebar, click **"Database"**
2. In the Database submenu, click **"Webhooks"**

### 4.2 Create New Webhook

**Where in Supabase UI**:
1. **Click** the **"Create a new hook"** button (top right, or "New Webhook")

### 4.3 Configure Webhook

**Fill in the form** (field by field):

#### Name
**Field**: **Name**
**Value**: `message_push_webhook`
**Where**: Top text input field

---

#### Table
**Field**: **Table**
**Value**: `messages`
**Where**: Dropdown menu
- **Click** the dropdown
- Scroll or type to find **"messages"**
- **Click** on it

---

#### Events
**Field**: **Events**
**Value**: Check `INSERT` only
**Where**: Checkboxes
- **Check** the box next to **"INSERT"**
- **Uncheck** UPDATE and DELETE if they're checked

---

#### Type
**Field**: **Type**
**Value**: `HTTP Request`
**Where**: Dropdown menu
- **Click** the dropdown
- Select **"HTTP Request"**

---

#### URL
**Field**: **URL**
**Value**: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-message-push`

**How to construct it**:
- Replace `YOUR_PROJECT_REF` with your actual project ref (same one from Step 1.3)

**Example**: If your project ref is `abcdefghijklmnop`, then:
```
https://abcdefghijklmnop.supabase.co/functions/v1/send-message-push
```

**Where**: Text input field

---

#### HTTP Method
**Field**: **HTTP Method**
**Value**: `POST`
**Where**: Dropdown menu
- **Click** the dropdown
- Select **"POST"**

---

#### HTTP Headers
**Field**: **HTTP Headers**
**Where**: You'll see a table with "Key" and "Value" columns

**Add Header 1**:
1. **Click** "+ Add Header" or "+" button
2. **Key**: `Authorization`
3. **Value**: `Bearer YOUR_SERVICE_ROLE_KEY`
   - Replace `YOUR_SERVICE_ROLE_KEY` with the key you copied in Step 3.2
   - Include the word "Bearer" followed by a space before the key
4. **Click** Save or the checkmark

**Add Header 2**:
1. **Click** "+ Add Header" or "+" button again
2. **Key**: `Content-Type`
3. **Value**: `application/json`
4. **Click** Save or the checkmark

---

#### Request Body Template
**Field**: **Request Body Template** (or "Payload Template")
**Value**: Copy and paste exactly:
```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

**Where**: Large text area or code editor

**Important**: Copy it exactly, including the curly braces with `{{` and `}}`

---

### 4.4 Save Webhook

**Where in Supabase UI**:
1. Scroll to the bottom of the form
2. **Click** **"Create webhook"** or **"Save"** button

**What happens**: The webhook will be created and should show a success message.

---

## Step 5: Test the Setup

### 5.1 Send a Test Message

**In your iOS app**:
1. Open the app on a device or simulator
2. Send a message to another user
3. Make sure the recipient is NOT viewing the conversation (app closed or on different screen)

### 5.2 Check Edge Function Logs

**Where in Supabase UI**:
1. Go back to **Edge Functions** in left sidebar
2. **Click** on `send-message-push`
3. **Click** on **"Logs"** tab
4. Look for new log entries

**What to look for**:
- `📨 Processing push notification` - Function was called
- `✅ Sent push notifications` - Push was sent successfully
- `⏭️ Skipping push` - Push was skipped (user viewing or no tokens)
- Error messages in red if something failed

### 5.3 Verify Push Notification Arrived

**On recipient device**:
- Check if push notification appeared on lock screen or notification center
- If using simulator, push notifications may not work - use a real device

---

## Troubleshooting

### Function Not Receiving Requests

**Check**:
1. Webhook is enabled (toggle switch should be ON in webhooks list)
2. Webhook URL is correct (matches your project ref)
3. Service role key is correct in HTTP headers
4. Edge Function is deployed (shows in Edge Functions list)

**How to check webhook status**:
1. Go to **Database** → **Webhooks**
2. Find `message_push_webhook` in the list
3. Check if there's a green dot or "Active" status

---

### APNs Authentication Errors

**Check Edge Function logs** for errors like:
- "Missing APNs environment variables"
- "Invalid key" or "Authentication failed"

**Fix**:
1. Go to **Edge Functions** → `send-message-push` → **Settings**
2. Verify all 5 secrets are added correctly:
   - `APNS_TEAM_ID`
   - `APNS_KEY_ID`
   - `APNS_KEY`
   - `APNS_BUNDLE_ID`
   - `APNS_PRODUCTION`
3. Make sure values match exactly (no extra spaces)

---

### Push Notifications Not Arriving

**Check**:
1. Device token is registered in `push_tokens` table
2. Notification permissions are granted in iOS app
3. Using real device (simulator doesn't receive push)
4. `APNS_PRODUCTION` is set to `false` for testing

**How to check device token**:
1. Go to **Database** → **Table Editor**
2. Open `push_tokens` table
3. Verify there are rows with your user_id

---

### "No tokens found" in logs

**This means**: User doesn't have a push token registered

**Fix**: 
1. Make sure the iOS app has requested notification permissions
2. Make sure device token registration code is running
3. Check `PushNotificationService.registerDeviceToken()` is being called

---

## Quick Reference: Where to Find Things

| What You Need | Where in Supabase UI |
|---------------|---------------------|
| Edge Functions | Left sidebar → **Edge Functions** |
| Function Settings | Edge Functions → Click function → **Settings** tab |
| Function Logs | Edge Functions → Click function → **Logs** tab |
| Service Role Key | Left sidebar → **Settings** → **API** → "service_role" key |
| Database Webhooks | Left sidebar → **Database** → **Webhooks** |
| Project Ref | Look at URL: `app.supabase.com/project/YOUR_PROJECT_REF` |

---

## Success Checklist

After completing all steps, verify:
- [ ] Edge Function is deployed (shows in Edge Functions list)
- [ ] All 5 environment variables are set (check in Settings → Secrets)
- [ ] Webhook is created (shows in Database → Webhooks)
- [ ] Webhook is enabled (green/active status)
- [ ] Service role key is in webhook headers
- [ ] Test message triggers logs in Edge Function
- [ ] Push notification arrives on recipient device

---

## Need Help?

**Check logs first**:
1. Edge Function logs: **Edge Functions** → `send-message-push` → **Logs**
2. Database logs: **Database** → **Logs** (if available)

**Common issues**:
- Forgot to set environment variables? → Check Settings → Secrets
- Webhook not triggering? → Check webhook is enabled and URL is correct
- APNs errors? → Verify all 5 secrets are set correctly


