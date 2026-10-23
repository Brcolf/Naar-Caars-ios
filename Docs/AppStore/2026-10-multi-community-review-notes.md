# App Review notes: multi-community build (Phase 2)

Prepared: 2026-10-18, for the first build that lets anyone create, invite to and join communities.

This file holds the text to paste into App Store Connect for that build, and the owner steps that have to be done first. It adds to `Docs/AppStore/RESUBMISSION_PACKET.md` and does not replace it: the review account, Sign in with Apple, privacy labels and account deletion notes there still apply.

## Owner steps before submitting

1. **Review account.** Keep the existing review account approved and an active member of the default community ("Naar's Cars Seattle"), so the reviewer lands in the app with content.
2. **Test invite code.** Sign in as a community admin (or the owner), open Explore (the search tab) > Test Community > Invite, and make an admin code with at least 5 uses and an expiry of at least 30 days. Put it where the notes say `<TEST CODE>`. A member code is single-use and lasts only 7 days, which is too short for review.
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

Existing account: sign in. You are a member of Naar's Cars Seattle. Explore (the search tab) lists your communities and has Start a community, Join a community and, for admins, Requests to join.

New account, three ways in (after signing up, the Get started screen offers all three):
1. Invite code: tap Enter an invite code and type <TEST CODE>. The preview shows the community's name, member count and what its admins will see before you join.
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

## Phase 3: community admin and moderation

Added 2026-10-18 for the build that lets community owners and admins run their community: members, settings, reports and announcements. If Phase 2 and Phase 3 ship in one build, use this section's text in place of the matching Phase 2 paragraphs and release notes above; otherwise paste it as the notes for the Phase 3 build.

### Owner steps (in addition to the Phase 2 steps)

1. **Reviewer's test community.** Sign in as the review account, create a test community (Explore > Start a community), so the review account is its owner. Profile > Admin Panel then offers that community, with Members, Reports and Settings.
2. **A report to look at (optional, writes).** From a second test account that belongs to the test community, report one of its Town Hall posts, so the community's Reports list is not empty. Remove the post, the report and the second account's membership after review.
3. **Legal pages.** The terms, privacy policy and FAQ changed again for Phase 3 (community moderation). Replace `<RELEASE DATE>` and copy both documents to the Notion pages the app opens (`Constants.swift`, privacy policy and terms URLs) before submitting.
4. **Review Notes size.** The Phase 3 paragraph below is about 920 bytes. It replaces one paragraph of the Phase 2 block, which leaves about 2,200 bytes, so the total is about 3,100 bytes before the account details are filled in, under the 4,000-byte limit.

### App Review Notes: Phase 3 paragraph (replaces only the last paragraph of "User-generated content and safety", the one that begins "Every report goes to the platform moderators"; keep "What community admins can and cannot see")

```text
Community moderation:
Owners and admins of a community can hide reported posts, comments, rides and favors in their community, restore what they hid, and dismiss reports. They never see who reported, and they never see email addresses or phone numbers. Reports about a community's owners and admins or their content, every message report and every report about a community go only to the platform moderators (the operator's admins).
Every report also stays in the platform moderators' queue until they review it, whatever a community admin decided. A community admin cannot undo a platform moderator's decision or the automatic hide after several reports. Platform moderators see every report and who filed it, can act in any community, and can archive any community.
To see it: the review account owns a test community. Profile > Admin Panel > choose the community > Reports. Members and Settings are on the same screen.
```

### Release notes (What's New), Phase 3

```text
Community owners and admins can now run their community from the Admin Panel: see members, make admins, review reports and hide reported posts, change the name, who can join and who can invite, and send announcements. Our terms, privacy policy and FAQ are updated to explain what community admins can do.

Community owners and admins: please update to this version. On an older version, tapping a report notification opens the wrong screen and shows an error. Platform admins can send up to 3 announcements a day in each community.
```

### Checks behind these notes

- Recipients and no reporter: `handle_new_report` (`20261018_0001` block 2) tells the community's active owners and admins with no source user and a push without the reporter; never the reporter, the reported person or the author; nobody in the community when the reported person or the author is one of its owners or admins. Message and community reports carry no community.
- The Reports list: `get_community_reports` (block 3) has no reporter column and leaves out reports about the caller and the community's owners and admins; `CommunityReport` has no reporter field (INV-P2).
- Hide, restore, dismiss and the platform-wins rules: `moderate_community_content` (block 4, D-S7). The decision goes to `reports.community_status`; `status` stays pending for the platform admins. The author gets the content-hidden notice.
- Settings, roles, transfer and archive are owner actions (`update_community`, `set_member_role`, `transfer_community_ownership`, `archive_community`, `20261017_0005` blocks 11, 24, 25, 13); removal and readmission are admin actions (blocks 22, 23).
- The announcement cap of 3 a day per community also binds platform admins (`send_community_broadcast`, `20261018_0002` block 10).
- In-app text: guideline 7 (`guidelines_7_body_moderation`) and the report sheet's second footer line (`report_note_visible_to_community_admins`, every report except a community report).

## Phase 4: links, time zones and announcements

Added 2026-10-19.

### Entitlement

The build adds the **Associated Domains** entitlement with `applinks:naarscars.com`. It only lets the app open `https://naarscars.com/join#<code>` links; it grants no new data access and uses no new permission, SDK or data type. **Owner step before archiving:** enable Associated Domains on the App ID `com.NaarsCars` in the developer account and regenerate the provisioning profile, or signing fails. Host `Docs/universal-links/apple-app-site-association` at `https://naarscars.com/.well-known/apple-app-site-association` (and serve a landing page at `/join`) before the release reaches users. Until then a link opens Safari.

### How a reviewer tests a join link

1. Sign in as the review account and create or open a community with an invite code (Explore > the community's page > Invite).
2. In Safari or Notes, open `https://naarscars.com/join#<code>`. The app opens Explore with the Join sheet for that community. Signed out, the Welcome screen shows "You have an invite. Sign up or sign in to use it." and the code is kept for after sign-in.
3. Join links are not required to review the app; every invite can also be entered by hand on the Join screen.

### Release notes (What's New), Phase 4

```text
Open invite links straight into the app, see which community a notification belongs to, and see how many requests another community has. Community owners can set their community's time zone.
```

Add this sentence only after the announcement server change (File B) is applied: "Announcements now reach every member who has not muted the community as a push notification."

### Checks behind these notes

- The announcement push and the `membership_update` notices are produced by server files that are NOT APPLIED (`20261019_0002`, `20261019_0003`); until they are, notification behaviour is unchanged.
- Account deletion, reporting and moderation are unchanged; no privacy manifest change.

## Community Release 1: Explore and the community page

Added 2026-10-21 as a draft for the owner to review before the build that adds the Explore tab. Nothing here has been pasted into App Store Connect. Replace the matching text of the earlier sections only if this build ships with them.

### App Review Notes: Release 1 paragraph (add after "Review access")

```text
Explore and community pages:
The Explore tab (magnifying glass, right end of the tab bar) lists the person's communities and public communities (the platform moderators decide which communities are public). Tapping one opens its community page. Anyone, including a guest, sees a listed community's name, description, member count, upcoming open requests without addresses or notes, recent Town Hall posts, and members' name, photo, car, rating and reviews. The bar at the bottom shows how to join: join, ask to join, or invite only. Joining, asking, entering an invite code and starting a community need an account; a guest is asked to sign in.
No account: on the welcome screen tap "Look around first". It opens Explore as a guest.
Reporting a community: Report this community is on the community page and in My communities. It goes to the platform moderators.
```

### Release notes (What's New), Release 1

```text
Find communities in the new Explore tab: see what a community offers before you join, then join, ask to join or enter an invite code. The Requests tab can show several communities at once, and Welcome has a new "Look around first" button. Our privacy policy and FAQ are updated.
```

### Owner steps and checks

1. Copy the changed `Legal/PRIVACY_POLICY.md` sentence ("Public communities") and the new FAQ entry to the Notion pages the app opens.
2. Check the byte size of the pasted Review Notes (limit 4,000 bytes); this paragraph adds about 1,000.
3. What a visitor reads is server-limited: `get_community_preview` (`20261021_0001`) returns listed, unarchived communities only, with no address, note or community description beyond the public one, and members' name, photo, car, rating and reviews.

## Community Release 2: search, Use my location, listing rules, merging and example content

Drafted 2026-10-22 for the owner to review before the build that adds discovery. Nothing here has been pasted into App Store Connect. Replace the matching text of the earlier sections only if this build ships with them.

### App Review Notes: Release 2 paragraph (add after the Release 1 paragraph)

```text
Searching communities: Explore has a search field. Type a community name (for example "Test") or a town or ZIP code (for example "98101") to see listed communities, nearest first for a place. No account is needed.
Use my location: a button in Explore, below the search field. The location permission prompt appears only after tapping it, once, and the location is used for that one search and not stored. If the permission is declined, typing a town or ZIP code works the same way. The permission is the existing "while using" permission; the purpose string now also names this use.
Test Community: the public community used for the review. It holds example requests and posts, marked Example, written for new people to explore. They cannot be claimed or answered. Search "Test" or the ZIP code 98101 to find it. The other test communities are not listed.
Starting a listed community: Explore > Start a community > Listed, then a service area (a place name and radius; never an address) and a nearby check. Merging two communities needs both owners to agree (Manage > Merge with another community). Neither is needed to review the app.
```

### Release notes (What's New), Release 2

```text
Find communities by name, town or ZIP code, or tap Use my location in Explore. Owners can list a community with a service area so neighbors can find it, and two communities can merge when both owners agree. Test Community now shows example requests so you can look around before joining. Our privacy policy, terms and FAQ are updated.
```

### Owner steps and checks

1. Copy the changed `Legal/PRIVACY_POLICY.md` (section 4.3), `Legal/TERMS_OF_SERVICE.md` (section 6.3a) and the new FAQ entries to the Notion pages the app opens.
2. In App Store Connect, confirm that the existing Location declaration (precise and coarse, App Functionality, linked, not tracking) covers community search (`Legal/PRIVACY-DISCLOSURES.md`).
3. The purpose string (`NSLocationWhenInUseUsageDescription`) changed in the build; the new text is in `Legal/PRIVACY-DISCLOSURES.md` section 2.1 and in `NaarsCars/Info.plist`.
4. The paragraph adds about 1,100 bytes: check the combined Review Notes against the 4,000-byte limit and drop earlier phase paragraphs the reviewer does not need.
5. Until the owner makes Test Community's example content permanent (S5b adds the two answered questions), the review account sees the 8 example requests and 3 posts the refresh job keeps current.
