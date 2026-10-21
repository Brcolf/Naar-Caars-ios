# Persistent test data

Test data on the live backend that test passes may use instead of real communities. Set up on 2026-10-21 at the owner's request.

**Nothing real goes in these communities.** No real addresses, names, phone numbers or photos, and no real members other than platform admins testing a flow. Do not archive, delete, rename or change the type of any of them; if a pass needs a different setup, create a new test community instead.

## Test owner

| Display name | Id (first 8) | Platform admin | Where it is signed in |
|---|---|---|---|
| NC Test Owner | `eebf5514` | no | the simulator "iPhone 17 (26.5)" |

The account was made through the app's Sign Up. Its sign-in details are kept only on the owner's Mac in `build/test-data/test-accounts.local` (gitignored, mode 600), together with the full community ids. They never go in the repository.

## Test communities

All four are owned by NC Test Owner, who is their only member. Time zone America/Los_Angeles.

| Name | Type | Stored as | Id (first 8) | Purpose |
|---|---|---|---|---|
| Test Public A | public: listed, ask to join | `is_public = true`, `join_policy = 'approve'` | `86916d6c` | ask-to-join and approval flows; created in the app |
| Test Public B | public: listed, ask to join | `is_public = true`, `join_policy = 'approve'` | `b546bf31` | a second public community, for anything that needs two |
| Test Private A | private: hidden, invite only | `is_public = false`, `join_policy = 'invite'` | `9dac5e11` | invite codes and links; a code admits at once |
| Test Private B | private: hidden, invite only | `is_public = false`, `join_policy = 'invite'` | `e84d026f` | a second private community, for anything that needs two |

Open-join communities do not exist yet, so there is no test community of that type.

## How to use them

- **Join a public one as a platform admin.** On your own account, open the onboarding screen or Profile → My communities → Join a community, and ask to join Test Public A or B. Then, on the iPhone 17 as NC Test Owner, open Profile → My communities → the community's menu → Requests to join, and approve or decline.
- **Join a private one.** On the iPhone 17 as NC Test Owner, open Profile → My communities → the community's menu → Invite people. Use the code (or link) it shows on the other account. A private community never appears in the public list, so a code is the only way in.
- **Leave afterwards** if the test does not need the membership any more, so the communities stay small.
- Platform admins can read every community row, private ones included (D9), but the "Ask to join a public community" list shows only the public ones.

## How they were made

- **Test Public A** was created in the app on the iPhone 17 (Start your own community, "Approve new members manually" on). That ran `create_community`, which wrote the community, the owner's active membership, the "created the community" membership event, and an `announcement` bell row (no push) for each platform admin. The Invite sheet that opens after creation also made one single-use invite code that expires after 7 days. Listing a community is a platform-admin action (`set_community_public`, D7) and the Create sheet does not offer it to other accounts, so `is_public` was then set to true with the same single update that RPC makes.
- **The other three** were written in SQL because an account can create only one community a day. Each copies the app-made row column for column (only id, name, description, `is_public`, `join_policy` and timestamps differ) and writes the same owner membership and membership event as `create_community`, with the same suppression of the "you've been approved" notice. The bell rows to platform admins were left out on purpose.
- NC Test Owner now owns 4 communities and its limit is 3, so Create is refused with the owned-communities limit. This state is possible in the app as well (taking over ownership does not check the limit), and it is a ready-made case for testing "Request a higher limit".
