# Naars Cars App Store Resubmission Packet

Prepared: 2026-05-12

This packet is for the next App Store Connect submission. It summarizes what was checked locally, what was adjusted in the repo, what to paste into App Review, and what still needs owner access outside the repo.

## Official Review Requirements Checked

- App Review Guidelines: full reviewer access, live backend, complete metadata, UGC moderation, reporting, blocking, and contact information.
  https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: privacy labels must include data collected by the app and third-party partners, even when used only for app functionality.
  https://developer.apple.com/app-store/app-privacy-details/
- App Review Information: Review Notes can include testing details and are limited to 4000 bytes.
  https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Third-party SDK requirements: FirebaseCore and FirebaseCrashlytics are on Apple's SDK list that requires privacy manifests and signatures.
  https://developer.apple.com/support/third-party-SDK-requirements/

## Repo Changes Made

- Updated `NaarsCars/Info.plist` location purpose text to match all current location use cases: nearby requests, directions, and one-time message location sharing.
- Updated `NaarsCars/PrivacyInfo.xcprivacy` to include:
  - Physical Address
  - Emails or Text Messages
  - User ID
  - Other Diagnostic Data as linked to the user
- Updated invite share text in `NaarsCars/Core/Utilities/InviteCodeFormatter.swift` to remove the currently non-resolving `https://naarscars.com/signup?...` link. Invite shares now use the App Store link plus the invite code.

## App Review Notes Draft

Paste this into App Store Connect after filling in the bracketed fields.

```text
Naars Cars is a private community app for coordinating ride and favor requests, messaging, reviews, and Town Hall posts.

Review access:
Email: [REVIEW_ACCOUNT_EMAIL]
Password: [REVIEW_ACCOUNT_PASSWORD]
Invite code if needed: [REVIEW_INVITE_CODE]

Please ensure this account is pre-approved before submitting. If the reviewer starts from signup, use the invite code above and then sign in with the review account.

Suggested review path:
1. Sign in with the review account.
2. Open Requests to view ride/favor requests.
3. Create a ride or favor request, then view its detail screen.
4. Open Messages to view conversations, image/audio/location message surfaces, and report/block controls.
5. Open Community > Town Hall to view posts/comments and report controls.
6. Open Profile > Settings to view privacy controls, blocked users, community guidelines, privacy policy, terms, Sign in with Apple linking, and account deletion.

User-generated content and safety:
Users can report messages, Town Hall posts/comments, ride requests, favor requests, and profiles. Users can block other users from message reporting flows and public profiles, and manage blocked users in Profile > Settings > Messaging > Blocked Users. Admins can review reports and hide, restore, dismiss, ban, or unban content/users.

Account deletion:
Users can delete their account from Profile > Delete Account. Banned users also have a Delete Account option. If the account uses Sign in with Apple, the app attempts Apple token revocation/unlinking before deleting account data.

Privacy:
The app does not sell data, serve ads, or use cross-app tracking. Firebase Crashlytics is optional and controlled by Profile > Settings > Privacy > Share Crash Reports.

Backend:
Supabase, APNs push functions, and Firebase Crashlytics must remain live and reachable during review.
```

## App Privacy Label Draft

Use this as the App Store Connect privacy questionnaire baseline. All listed categories should be marked "Linked to User", "Not Used for Tracking", and "App Functionality" unless noted otherwise.

| App Store Category | Data Type | Notes |
| --- | --- | --- |
| Contact Info | Name | Profile/display name |
| Contact Info | Email Address | Account auth and support |
| Contact Info | Phone Number | Optional profile/coordination, required for claiming flows |
| Contact Info | Physical Address | Ride/favor pickup, destination, and location text entered in requests |
| Location | Precise Location | User-granted location for maps/directions/one-time message location |
| Location | Coarse Location | Location-derived map/request context |
| User Content | Photos or Videos | Avatars, message images, Town Hall/review images |
| User Content | Emails or Text Messages | In-app messages, including sender/recipient/content |
| User Content | Audio Data | Audio messages |
| User Content | Other User Content | Requests, posts, comments, reviews, ratings, Q&A, reports |
| Identifiers | User ID | Supabase/auth/profile UUIDs and app user ID context |
| Identifiers | Device ID | Push token/device identifier |
| Diagnostics | Crash Data | Optional Firebase Crashlytics |
| Diagnostics | Other Diagnostic Data | Optional Crashlytics non-fatal/error context |

Recommended "Data Used to Track You": No.

Do not mark advertising data, contacts, financial info, health/fitness, browsing history, search history, or purchase history unless App Store Connect's generated privacy report or future code changes show those are collected.

## Manual QA Checklist

- Fresh install, existing user login, logout, relaunch.
- Signup with invite code, including invalid/expired code.
- Sign in with Apple signup, login, link, unlink, and delete-account path.
- Pending approval screen, banned account screen, and contact support.
- Push permission prompt, push token registration, foreground notification, background notification, badge count clear.
- Create, edit, claim, unclaim, complete, and delete ride/favor requests.
- Open directions with Apple Maps and Google Maps fallback.
- Messages: send text, image, audio, location, reactions, edit/unsend, report, block, leave conversation, muted conversation.
- Town Hall: create post/comment, vote, report post/comment.
- Profile: edit profile photo/name/phone/car, privacy settings, notification settings, blocked users, privacy policy, terms, community guidelines.
- Permissions denied: location, camera, photo library, microphone, calendar, notifications.
- Guest mode surfaces do not expose private addresses or actions that require account access.
- Dynamic Type, dark mode, and VoiceOver spot check on signup, requests, messages, profile, and report/block flows.
- Airplane mode/offline launch and cached dashboard/messages behavior.
- Account deletion removes access and signs out cleanly.

## Owner Tasks Before Submission

- Create or verify a non-expiring review account and record its email/password above.
- Generate a fresh invite code for App Review, or pre-approve the review account so no approval wait blocks review.
- Confirm Supabase migrations and edge functions are deployed to production, especially notification, report/moderation, delete account, and revoke Apple token functions.
- Confirm Supabase edge secrets are set for APNs and Apple token revocation.
- Confirm Apple Developer capabilities for the App ID: Push Notifications, Sign in with Apple, WeatherKit, and any Associated Domains if universal links are re-enabled.
- Archive from a clean environment that has local-only files available: `NaarsCars/Core/Utilities/Secrets.swift` and `NaarsCars/NaarsCars/GoogleService-Info.plist`.
- In Xcode Organizer, generate the privacy report for the archive and compare it against the privacy label draft above.
- Upload the build, select the exact build in App Store Connect, paste the App Review Notes, add contact info, and submit.

## Known External Blockers

- `https://naarscars.com` did not resolve during this audit. Universal/invite links should stay out of user-facing share text until DNS is fixed and an Apple `apple-app-site-association` file is hosted with no redirects.
- `GoogleService-Info.plist` and `Secrets.swift` are intentionally gitignored. They must be present locally for archive, but must not be committed.
