# App Review notes: multi-community build (Phase 2)

Prepared: 2026-10-18, for the first build that lets anyone create, invite to and join communities.

This file holds the text to paste into App Store Connect for that build, and the owner steps that have to be done first. It adds to `Docs/AppStore/RESUBMISSION_PACKET.md` and does not replace it: the review account, Sign in with Apple, privacy labels and account deletion notes there still apply.

## Owner steps before submitting

1. **Review account.** Keep the existing review account approved and an active member of the default community ("Naar's Cars Seattle"), so the reviewer lands in the app with content.
2. **Test invite code.** Sign in as a community admin (or the owner), open Profile > My communities > Naar's Cars Seattle > Invite people, and make an admin code with at least 5 uses and an expiry of at least 30 days. Put it where the notes say `<TEST CODE>`. A member code is single-use and lasts only 7 days, which is too short for review.
3. **Legal pages.** Replace `<RELEASE DATE>` in `Legal/PRIVACY_POLICY.md` and `Legal/TERMS_OF_SERVICE.md` with the release date, then copy both documents to the Notion pages the app opens (`Constants.swift`, privacy policy and terms URLs). The app shows the Notion copies, not the files in this repository.
4. **Release notes.** Paste the release notes below, and tell the platform admins directly to update with this build (decision D10: on the previous build they can neither approve nor reject applicants to other communities).
5. **Review Notes size.** App Store Connect limits Review Notes to 4,000 bytes. The block below is about 2,600 bytes before the account details are filled in.

## App Review Notes (paste after filling the bracketed fields)

```text
Naars Cars is a community app for coordinating rides and favors between neighbors, with messaging, reviews and Town Hall posts. This version adds communities: anyone can create one, invite people with a code, and approve requests to join.

Review access:
Email: [REVIEW_ACCOUNT_EMAIL]
Password: [REVIEW_ACCOUNT_PASSWORD]
Test invite code: <TEST CODE>

Existing account: sign in. You are a member of Naar's Cars Seattle. Profile > My communities lists your communities and has Create a community, Join a community and, for admins, Requests to join.

New account, three ways in (after signing up, the Get started screen offers all three):
1. Invite code: tap Enter an invite code and type <TEST CODE>. The preview shows the community's name, description and what its admins will see before you join.
2. Ask to join a public community: answer two questions; the request waits for that community's admins.
3. Create a community: enter a name. You become its owner and enter the app at once. The invite sheet then shows a code you can share.
A new community is private by default, and its owners and admins approve who joins.

What community admins can and cannot see:
Owners and admins of a community see an applicant's name, photo, car, answers and who invited them. They never see email addresses or phone numbers, and they do not see who filed a report.

User-generated content and safety:
- Content: messages, Town Hall posts and comments, ride and favor requests and reviews have a Report action (long-press or the menu).
- People: Report and Block from a person's profile; blocked users are managed in Profile > Settings.
- Communities: a community's name and description are new user content. Report this community is on its preview (invite code or public community) and in My communities. A guest browsing the Town Hall is asked to sign in to report the community.
Every report goes to the platform moderators (the operator's admins), who see who reported it and can act in any community, including private ones. They can hide content, ban accounts, archive any community, and make a public community private (Admin Panel > Communities). Community guidelines section 7 covers communities and their admins.

Account deletion:
Profile > Delete Account. If the account is the only owner of a community, the app first lists the communities that would close; ownership passes to another admin when there is one. Deletion always completes.

Backend:
Supabase, the push functions and Firebase Crashlytics stay live during review.
```

## Release notes (What's New)

```text
Communities are here. Create your own community, invite neighbors with a code, or ask to join a public one, and switch between your communities from the Community tab. Community owners and admins approve who joins. Our privacy policy and terms are updated to explain who can see what.

Admins: please update to this version.
```

## Checks behind these notes

- Report paths: content and people as in the resubmission packet; communities through `ReportContentSheet` with the community context (Task 4), routed only to platform admins (`report_community`, `20261017_0005` block 31; `handle_new_report`, `20261017_0003` call 10).
- Admin visibility: `get_community_members` returns answers and inviter to admins only and never email or phone (`20261017_0005` block 29).
- Creation: any signed-in, unbanned account; one a day, three owned by default (`create_community`, block 7). The creator is the active owner at once.
- Platform moderators: admin of every live community (`my_admin_community_ids`, `20261017_0001`), archive (`archive_community`, block 13) and make private (`set_community_public`, block 12).
- Account deletion: `delete_user_account` STEP A (`20261017_0004`), decision A3; the warning is Task 15.
