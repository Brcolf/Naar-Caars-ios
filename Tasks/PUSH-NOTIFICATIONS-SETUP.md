# Push Notifications Setup Guide

## Task 1.0: Configure Push Notification Capabilities

This document outlines the manual steps required to configure push notifications in Xcode and Apple Developer Portal.

### 1.1 Enable Push Notifications in Xcode

1. Open the project in Xcode
2. Select the **NaarsCars** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Verify it appears in the capabilities list

### 1.2 Enable Background Modes > Remote notifications

1. In the same **Signing & Capabilities** tab
2. Click **+ Capability**
3. Add **Background Modes**
4. Check the box for **Remote notifications**

### 1.3 Create APNs Key in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Go to **Keys** section
4. Click **+** to create a new key
5. Enter a name (e.g., "Naars Cars APNs Key")
6. Check **Apple Push Notifications service (APNs)**
7. Click **Continue** then **Register**
8. **Download the key file** (.p8) - you can only download it once!
9. Note the **Key ID** shown on the page

### 1.4 Upload APNs Key to Supabase Dashboard

1. Go to your Supabase project dashboard
2. Navigate to **Settings** → **Push Notifications**
3. Upload the .p8 key file
4. Enter the **Key ID** from step 1.3
5. Enter your **Team ID** (found in Apple Developer Portal → Membership)
6. Save the configuration

### Verification

After completing these steps:
- ✅ Push Notifications capability should appear in Xcode
- ✅ Background Modes > Remote notifications should be enabled
- ✅ APNs key should be uploaded to Supabase
- ✅ App should be able to register for remote notifications

### Notes

- The APNs key (.p8 file) can only be downloaded once from Apple Developer Portal
- Keep the key file secure - it's used to send push notifications to all users
- The Team ID is found in your Apple Developer account membership page


