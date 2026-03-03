# Profile Settings Relocation & Debug Isolation

**Date:** 2026-03-03

## Problem

The profile page has a "Notifications" card that links to NotificationsListView — redundant with the bell icon in the toolbar. Settings are only accessible via a gear icon in the toolbar, which is less discoverable.

## Design

### 1. Profile Page (MyProfileView)

- **Remove** the `notificationsSection()` card (bell + "Notifications" NavigationLink)
- **Replace** with an "Account Settings" card (gear icon + "Account Settings" label) that sets `showSettings = true` to open SettingsView as a sheet
- **Remove** the gear icon from the toolbar trailing items
- Toolbar retains: bell icon + edit button

### 2. Debug Settings Isolation (SettingsView)

Already correctly gated behind `#if DEBUG`. No changes needed. Documented here for launch clarity:

**Production (always visible):** Biometric Auth, Notification Settings, Account Linking, Messaging Settings, Language, Appearance, Privacy, About/Legal

**Debug-only (behind #if DEBUG):** Notification Diagnostics, Test Crash, Test Non-Fatal Error, Performance Instrumentation, MetricKit, Verbose Logs

## Files to Change

| File | Change |
|------|--------|
| `MyProfileView.swift` | Replace `notificationsSection()` with settings card, remove gear from toolbar |
