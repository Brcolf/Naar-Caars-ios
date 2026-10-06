# What has been tested — NaarsCars, 2026-10-05

A plain inventory of every function exercised during the 2026-10-05 QA session, grouped by area of the app. It was compiled from the QA report (`Docs/qa/2026-10-05-simulator-ux-performance-review.md`), the session record and the final unit-test run, and each line was checked against that record by an independent reviewer.

Test setup: Debug builds from the working tree of `claude/quirky-gates-4bkmv4`, on the iPhone 16 simulator running iOS 26.5, against the live backend. One real account (an admin) was signed in; a second member's actions were simulated by writing to the database. Nothing was tested on a physical phone.

## Totals

| Result | Items |
|---|---|
| Tested and working | 151 |
| Was broken, fixed, re-tested and working | 67 |
| Was broken, fixed, not re-tested since | 44 |
| Tested and still not right | 27 |
| Not tested | 42 |
| **All items** | **331** |

Of the 218 items that work today, 124 were driven by hand on the simulator, 25 were checked against the live server, 55 are covered by automated tests, 12 were measured from logs and 2 were confirmed by reading the code.

How to read a line: the text in brackets says how it was tested. "Checked against the live server" means a database or server-log check, usually a probe run as a signed-in user and rolled back. "Code read only" means the change was made and compiled but that exact behaviour was not exercised.

## Launch and sign-in

**Tested and working**

- Signing in with email and password takes an approved account into the main app (the owner typed the password; the result was observed on screen and in the app log). [by hand on the simulator]
- You stay signed in after force-quitting and relaunching the app, after installing newer builds, and after restarting the simulator. [by hand on the simulator]
- Signing out returns to the Welcome screen within about 2 seconds. [by hand on the simulator]
- Sign-out clean-up (wipe the data stored on the phone, reset the refresh state) runs in the right order. [code read only]
- Welcome, Log In and Sign Up screens display, and you can move between them and back. [by hand on the simulator]
- Quitting and relaunching the app comes back cleanly to the Welcome screen (guest mode is not remembered across a relaunch). [by hand on the simulator]
- Tapping Create Account on an empty sign-up form is refused, with a clear 'required' message under each field (the button is not greyed out beforehand). [by hand on the simulator]
- The Sign in with Apple button looks right when the app is launched in dark mode. [by hand on the simulator]
- App launch finishes in the ready state (signed in or signed out decided) within the time limit. [automated test]

**Was broken, fixed, re-tested and working**

- The launch screen shows the logo centred in the same position as the in-app splash, with no visible jump (it used to show a cropped corner of the logo). [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- Signing out removes this phone's push registration so the previous user's pushes stop arriving (found not removed: 2 registrations before and after sign-out). [checked against the live server]
- The Sign in with Apple button updates when the phone switches between light and dark while the Welcome screen is showing (it turned black-on-black). [by hand on the simulator]
- Log-in and sign-up text fields are visible before you tap them in light mode (they were white on white). [by hand on the simulator]

**Tested and still not right**

- Sign Up with Email goes through an invite-code step (it goes straight to the account details form, so sign-up does not require an invite code). [by hand on the simulator]

**Not tested**

- Creating a new account (submitting the sign-up form) was not attempted.
- Sign in with Apple, and linking an Apple ID to an account, were not tested (needs a real device).
- The pending-approval screen for a new member, and an admin approving them, were not tested.
- The banned-account state was not tested.
- The launch screen as it appears on a real phone was not checked.

## Guest mode

**Tested and working**

- Entering the app as a guest from the Welcome screen. [by hand on the simulator]
- All four tabs open for a guest. [by hand on the simulator]
- The '+' menu opens for a guest, and choosing Create Ride shows a sign-in placeholder instead of the form. [by hand on the simulator]
- A guest tapping the notifications bell is asked to sign in. [by hand on the simulator]
- A guest trying to create a Town Hall post is asked to sign in. [by hand on the simulator]
- A guest tapping vote on a comment is asked to sign in with the correct wording. [by hand on the simulator]
- A guest trying to reply to a comment is asked to sign in. [by hand on the simulator]
- A guest tapping Send Message on a member's profile is asked to sign in. [by hand on the simulator]
- A guest tapping Log In on the Profile tab is taken to the Welcome screen (one extra tap before the login form). [by hand on the simulator]

**Was broken, fixed, re-tested and working**

- A guest tapping vote on a Town Hall post is asked to sign in, and the prompt is titled 'Sign In to Vote' (it used to say 'Sign In to Create a Post'). [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- Guests see only the Open Requests tile (the My Requests and Claimed tiles, always empty for a guest, were hidden). [code read only]

**Tested and still not right**

- The guest sign-in prompt has a solid background (it is see-through: the Send Message button shows through the title). [by hand on the simulator]

## Requests dashboard

**Tested and working**

- The Requests filters (Open, My Requests, Claimed) switch while signed in. [by hand on the simulator]
- A newly added future ride appears under Open Requests with a badge on the tile. [by hand on the simulator]
- The older separate rides-list and favors-list loaders (no longer used by the Requests screen) load, finish loading, and accept the 'Mine' filter. [automated test]

**Was broken, fixed, re-tested and working**

- Old past-dated requests no longer sit in the open list (all 71 open rides and 45 open favors were in the past, so the dashboard was empty for everyone; a server job now expires them). [checked against the live server]
- The empty-state card has padding and rounded corners, in light and dark mode. [by hand on the simulator]
- My Requests keeps a confirmed request after its time has passed, so Mark as Complete can be reached from the dashboard. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- Coming back to the Requests tab shows saved data without downloading everything again (it used to do a full reload on every return). [measured from logs]

## Rides and favors

**Tested and working**

- Ride Details shows the route card, savings, map, date, seats, time, notes, questions section, participants and Edit/Delete. [by hand on the simulator]
- Asking a question on a ride saves it and notifies the poster. [by hand on the simulator]
- An answer added on the server shows on the ride the next time it is opened. [by hand on the simulator]
- A new ride triggers notifications to the other members (18 in-app notifications and 18 pushes). [checked against the live server]
- The Edit Ride form opens with its fields and time picker (it was cancelled, not saved). [by hand on the simulator]
- The Past Requests screen opens with its 'mine' and 'helped with' lists. [by hand on the simulator]
- Creating a ride: a missing pickup and a past date are rejected, and a valid ride is saved to the server. [automated test]
- Creating a favor: a missing location is rejected, and a valid favor is saved to the server. [automated test]
- Questions can be asked on a ride or favor while it is unclaimed and are closed once it is claimed. [automated test]
- Ride and favor records from the server are read and written correctly, including status and dates. [automated test]
- Ride cost estimate: rush-hour and late-night multipliers, the highest pricing zone, combined multipliers and the minimum fare. [automated test]
- Flight numbers in ride notes (AS587, DL 123, 'Flight: UA12') are recognised, and addresses, highway numbers, order numbers and times are not mistaken for flights. [automated test]
- Directions for a ride are built with the right stops, and nothing is opened when the pickup or drop-off is missing. [automated test]

**Was broken, fixed, not re-tested since**

- Ride times show as a readable clock time (9:00 AM) instead of the raw 09:00:00. [automated test]
- Editing a ride or favor notifies the person who claimed it (the notification was silently rejected before; only the server side was checked, saving an edit from the app was not exercised). [checked against the live server]

**Tested and still not right**

- Past Requests shows a correct status on past rides and has one way to close the screen (past rides were labelled 'Open', and there is both a back arrow and a Close button). [by hand on the simulator]
- Ride Details opens straight to the saved ride instead of a full-screen loading placeholder. [by hand on the simulator]

**Not tested**

- Creating a ride or favor through the in-app form was not tested on the device (test rides were added directly in the database).
- Saving edits to a ride, and deleting a ride, were not tested.
- Favor screens (create, details, claim, complete) were not opened on the device; every device request test used a ride.
- Ride and favor list caching was not tested (those automated tests are switched off as obsolete).

## Claiming and completion

**Tested and working**

- Claiming a ride (I Can Help, then confirm) marks it confirmed and notifies the poster. [by hand on the simulator]
- A claimed ride shows the 'Claimed by' card with Message Participants and Unclaim buttons. [by hand on the simulator]
- Unclaiming a ride reopens it, notifies the poster and removes the completion reminder. [by hand on the simulator]
- Claiming a ride schedules a completion reminder for one hour after the ride time. [checked against the live server]
- The add-to-calendar offer appears after claiming a ride. [by hand on the simulator]
- Answering 'Yes' to a completion reminder completes the ride, closes the reminder, sends the review request and awards XP. [checked against the live server]
- Claiming a ride against a simulated server succeeds without creating a conversation (the other claim, unclaim and complete test cases only check that nothing crashes). [automated test]
- Completion and review prompts are shown oldest first with no duplicates, a prompt already on screen is not queued again, and its notifications are marked read at the right moment. [automated test]
- The signed-in member's due completion prompts and pending review prompts load from the server without error; an expired review request is marked read instead of shown; a review is allowed straight after the event. [automated test]
- After leaving a review, the link to the review opens the matching Town Hall post and does nothing when there is no post. [automated test]

**Was broken, fixed, re-tested and working**

- The person who claimed a ride can tap Mark as Complete once the ride time has passed: the ride becomes Completed, the reminder closes, and the poster gets a review request (there was no such button before). [by hand on the simulator]
- The person who posted a ride can tap Mark as Complete: the ride becomes Completed, the reminder closes, and a 'Leave a Review' row appears. [by hand on the simulator]
- Tapping a completion reminder in the in-app notifications list opens the Yes/No completion prompt. [by hand on the simulator]
- Answering 'Not yet' on the completion prompt snoozes the reminder for one hour without using up one of the reminder sends. [by hand on the simulator]
- The scheduled server job sends the first completion reminder by itself and schedules the next one 30 minutes later. [checked against the live server]
- A helper can only mark complete a request that is confirmed and claimed by them, and cannot point a reminder at someone else's request. [checked against the live server]

**Was broken, fixed, not re-tested since**

- The calendar offer is shown only to the person who claimed, and not again on every visit (it re-appeared 3 times in 10 minutes and on an unclaimed ride). [by hand on the simulator]
- Claiming finishes without an error in the app log (the app made an unneeded extra push request that the server refused on every claim; the real push still went out). [measured from logs]
- Completion reminders stop after three sends (one request had produced 44 pushes in a day). [checked against the live server]

**Not tested**

- Writing and submitting a review after a completed request was not tested (only the 'Leave a Review' row was seen).

## Messages list

**Tested and working**

- The conversation list loads and shows your threads, including after the evening's server privacy changes. [by hand on the simulator]
- After you send a message, that thread's preview and time update in the list. [by hand on the simulator]
- Swiping a conversation row reveals its actions (Pin and Mute on one side, Delete on the other). [by hand on the simulator]
- Pinning a conversation moves it into a Pinned section. [by hand on the simulator]
- Muting a conversation from its swipe action is saved on the server and shows the muted bell and a grey badge. [by hand on the simulator]
- The list only redraws when something changed, keeps member names when an update arrives without them, hides empty duplicate or member-less threads, and does not start listening until the screen appears. [automated test]
- Syncing the list removes conversations that no longer exist on the server, keeps older ones outside the fetched page, and writes nothing when nothing changed. [automated test]
- Unread counts: an incoming unread message raises the count, your own or already-read messages do not, reading lowers it, and it never drops below zero. [automated test]

**Was broken, fixed, re-tested and working**

- A new unread message puts a badge on the Messages tab and an unread count on its row, and both clear once the thread has been opened. [by hand on the simulator]
- Conversation rows show iMessage-style times (clock time today, then Yesterday, weekday, short date) and unread rows in bold. [by hand on the simulator]
- Empty duplicate threads and member-less 'Unknown' rows are hidden from the list. [by hand on the simulator]
- Scrolling to the end of the list loads every conversation and the list simply ends, with no leftover 'No more conversations' caption. [by hand on the simulator]
- The 'Pinned' and 'All Messages' labels scroll away with the rows instead of floating over avatars. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- The Pinned section header disappears when its only pinned conversation is hidden by a block. [by hand on the simulator]
- The Messages tab badge stops counting unread messages from a blocked person's hidden thread. [by hand on the simulator]

**Tested and still not right**

- Older duplicate threads with the same person that contain real messages still appear as separate rows until the server-side merge is run. [by hand on the simulator]

**Not tested**

- Unpinning a conversation.
- Deleting a conversation from the list.
- Searching from the search bar on the conversation list.

## Conversation thread

**Tested and working**

- Opening a conversation shows its messages as bubbles with date and time separators. [by hand on the simulator]
- A message from the other person appears live at the bottom of the open conversation, under the correct date (the message was inserted on the server as the other user). [by hand on the simulator]
- When the other person's read is simulated by a database update, 'Delivered' changes to 'Read' in the open conversation without reopening it. [by hand on the simulator]
- Searching inside a conversation finds matches, shows the count and steps through them with the arrows (10 matches for 'push'). [by hand on the simulator]
- The media gallery opens with Photos, Audio and Links tabs. [by hand on the simulator]
- Opening a conversation connects its live updates before loading messages, and leaving it disconnects them. [measured from logs]
- An open conversation starts listening once its screen has appeared, and a newly arrived live message is added to the open conversation. [automated test]
- Read receipts in an open conversation: another member's read update is applied and only the echo of your own read is ignored. [automated test]
- The status under your own messages (Sending, Delivered, Read, Failed) is worked out correctly, and a group shows Read only when every other member has read. [automated test]
- Live message events (new, edited, deleted) are read correctly across the date formats and read-list shapes the server sends, and an event missing required fields is rejected. [automated test]
- Dropping all live conversation connections runs without crashing. [automated test]
- Marking messages as read sends the list of message ids to the server in the correct format (regression check for the read-receipt bug). [automated test]

**Was broken, fixed, re-tested and working**

- Opening a conversation shows the person's name in the title straight away instead of a generic 'Chat'. [by hand on the simulator]
- On first opening a conversation, including one with unread messages, the newest message sits clear of the message box rather than hidden behind it. [by hand on the simulator]
- Opening a conversation marks the other person's messages as read on the server. [by hand on the simulator]
- Messages that arrived while you were on the list are marked read when you then open the conversation. [by hand on the simulator]
- A message that arrives while the conversation is open is marked read on the server. [by hand on the simulator]
- 'Delivered' appears as text under the newest message you sent. [by hand on the simulator]
- An edited message shows the label 'Edited' in full (it was previously cut off at the edge). [by hand on the simulator]
- An unsent message shows as a small centred grey line, and 'Delivered' moves back to the previous message you sent. [by hand on the simulator]
- Date and time headers read correctly (for example 'Today 3:45 PM') instead of showing a raw text key. [by hand on the simulator]
- Messages sent more than a minute apart show as separate bubbles (grouping window shortened to one minute). [by hand on the simulator]
- In a one-to-one conversation, a typing bubble appears as the newest item when the other person is typing and disappears by itself (typing was simulated on the server). [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- Tapping a message bubble reveals its time for two seconds. [code read only]
- The current search match is clearly highlighted in the conversation. [by hand on the simulator]

**Not tested**

- 'Read' appearing under your message when a real second account reads it on its own device.
- Bubble regrouping at the one-minute boundary when the server's timestamp replaces the phone's own.
- The live typing bubble in a group while a real second member types.
- Reconnecting an open conversation after the app goes to the background and comes back.

## Composer

**Tested and working**

- Sending a text message shows the bubble immediately and the server then confirms it. [by hand on the simulator]
- The attachment menu opens and offers Location, Voice Note, Photo and Take Photo. [by hand on the simulator]

**Was broken, fixed, re-tested and working**

- The message box has a grey '+' button, a 'Message' placeholder, and a send button inside the field that appears only when there is something to send. [by hand on the simulator]
- After sending a multi-line message, the message box shrinks back to one line. [by hand on the simulator]
- A brand-new, empty conversation shows the message box, and a first message can be sent from it. [by hand on the simulator]
- Choosing Reply or Edit puts the cursor in the message box straight away (Edit prefilled with the cursor at the end). [by hand on the simulator]
- Choosing Voice Note with microphone access denied shows an explanation with an Open Settings button. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- The reply banner shows the right person's name (not 'Unknown') for a message that arrived live, and a one-line preview. [by hand on the simulator]

**Not tested**

- Recording and sending a voice note (recording banner, timer, Cancel, and exactly one message sent).
- Sending a photo from the library or sharing a location in a message.
- Taking a photo with the camera and sending it.
- Retrying a message that failed to send.
- On-screen keyboard behaviour in the conversation and its search field (the simulator used a hardware keyboard, so the software keyboard never appeared).

## Message actions

**Tested and working**

- Long-pressing a message shows the reaction bar and the action menu (Reply, Copy, Delete for Me, Report, plus Edit and Unsend on your own recent messages). [by hand on the simulator]
- Adding a heart reaction from the long-press menu saves it, shows the badge at the top of the bubble, and the details show who reacted. [by hand on the simulator]
- Replying to a message from the long-press menu sends a reply that quotes the original and is saved as a reply on the server. [by hand on the simulator]
- Starting to edit a message shows the editing banner and prefills the message box with its text. [by hand on the simulator]
- Unsend is only offered on recent messages (a message older than 15 minutes showed Delete but no Unsend). [by hand on the simulator]
- When an edit to your own message arrives as a live update, the message keeps its sent status and sender details. [automated test]
- Replies show the quoted original with the right sender name, including when the sender has to be looked up, and existing reply details are not overwritten. [automated test]
- The 'Haha' reaction is recognised and its artwork is produced at each badge size. [automated test]

**Was broken, fixed, re-tested and working**

- Long-pressing the newest message at the bottom of the screen shows the menu without covering the bubble. [by hand on the simulator]
- Long-pressing a message while the message box is in use puts the box away first and shows the whole menu. [by hand on the simulator]
- Swiping right on a message, yours or theirs, starts a reply. [by hand on the simulator]
- Tapping a reply opens the reply thread view with a single message box, not two stacked. [by hand on the simulator]
- Editing your own message saves the new text on the server and the message shows 'Edited'. [by hand on the simulator]
- After you edit your own message, its status stays as sent/delivered instead of switching back to 'sending'. [by hand on the simulator]
- Unsending your own message removes it on the server and leaves a 'You unsent a message' line. [by hand on the simulator]
- The conversation's message box hides under the reply thread view and the details sheet and comes back afterwards without the conversation jumping. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- When swiping to reply on an incoming message, the reply arrow shows in the space the bubble leaves behind. [code read only]
- The conversation no longer drops down while the Unsend confirmation is showing. [by hand on the simulator]
- The conversation's message box steps aside under the image viewer, the report sheet and the location sheet. [code read only]

**Not tested**

- Copy, Delete for Me and Report on a message.

## Groups and participants

**Tested and working**

- Searching for a person in New Message finds them, even when the name typed is not exact. [by hand on the simulator]
- Unmute from the conversation details sheet turns notifications back on and stays set. [by hand on the simulator]
- The participants list keeps showing the current members when the profile lookup fails. [automated test]

**Was broken, fixed, re-tested and working**

- Starting a new conversation from New Message creates a thread that contains both people and can be written in. [by hand on the simulator]
- 'Message Participants' on a claimed ride opens a conversation that contains both people, with the system line showing. [by hand on the simulator]
- Tapping 'Message Participants' again reopens the existing thread with those people instead of creating another one. [by hand on the simulator]
- The info button in a one-to-one conversation opens a details sheet showing the participants and the mute control. [by hand on the simulator]

**Not tested**

- Creating a group conversation and managing it (rename, add or remove people, leave).
- Finding the right existing group conversation after someone has left the group.

## Notifications and push

**Tested and working**

- After sign-in the app shows its push pre-prompt, then the system permission prompt, and saves the push token. [by hand on the simulator]
- Badge counts sync after sign-in. [measured from logs]
- The notifications bell lists your notifications, and tapping a 'ride claimed' row opens that ride's details. [by hand on the simulator]
- A simulated message push arriving while the app is open shows an in-app banner. [by hand on the simulator]
- A simulated message push refreshes the conversation list and the badge counts and updates the app icon badge. [measured from logs]
- A simulated 'ride claimed' push arriving while the app is in the background shows a banner, and tapping it opens that ride's details. [by hand on the simulator]
- Tapping the in-app banner for a ride push while the app is open opens that ride. [by hand on the simulator]
- A 'ride claimed' push arriving in the background triggers a refresh of the requests dashboard and the badges. [measured from logs]
- A completion-reminder push refreshes the badges and the requests dashboard. [measured from logs]
- Creating a Town Hall post sends push notifications to other members (18 went out). [checked against the live server]
- Asking a question on a ride sends the poster a notification and a push. [checked against the live server]
- Claiming a ride sends the poster a notification and a push. [checked against the live server]
- Unclaiming a ride sends the poster a notification and a push and removes the completion reminder. [checked against the live server]
- A tapped push is translated into the right destination for ride, favor, message, profile, Town Hall post, admin, review request, account-approved and notification-list types, and unknown or malformed ones are handled safely. [automated test]
- Push payloads in the shape the server sends them (message, ride, favor, Town Hall comment, announcement, pending approval) resolve to the correct destination. [automated test]
- Opening from a notification switches to the correct tab and target, clears the pending destination once used, and ignores a target meant for a different request. [automated test]
- Every notification type is recognised, maps to the right notification setting (mandatory ones cannot be switched off) and refreshes the right part of the app; unknown types are ignored. [automated test]
- Review pushes lead to the review prompt, completion-reminder pushes lead to the completion prompt and are not auto-marked read, and other push types do neither. [automated test]
- The push permission request reports granted or denied correctly (simulated), and a device token can be saved to and removed from the server for the signed-in member. [automated test]
- Notifications load from the server with pinned ones first, the unread count matches, and 'mark all as read' leaves none unread. [automated test]
- The notifications screen finishes loading, refreshing and 'mark all as read', and tapping a review-request notification opens the review prompt. [automated test]
- The in-app banner component builds a banner with the sender's name for an incoming message (component check only). [automated test]
- Badge counts start at zero, the four tab badges are distinct, and the total matches the sum of its parts (no server count fetched). [automated test]

**Was broken, fixed, not re-tested since**

- The bell reaches back 90 days (up to 200 items) so it is not empty for an account with only older notifications. [by hand on the simulator]
- Tapping a completion-reminder push itself opens the Yes / Not yet prompt. [code read only]

**Not tested**

- Opening a push from the lock screen or Notification Center.
- Tapping a push while on a different tab switches to the right tab and screen.
- Push notification banners on a real phone.
- Marking a single notification as read.

## Town Hall

**Tested and working**

- The Town Hall feed loads and a post's comments sheet opens for a guest. [by hand on the simulator]
- Creating a Town Hall post saves it and notifies members (18 pushes). [by hand on the simulator]
- Upvoting a post saves and the count updates. [by hand on the simulator]
- Commenting on a post, upvoting a comment, and replying to a comment in a thread. [by hand on the simulator]
- Writing a post: empty, blank and over-long posts are blocked, the character counter is correct, and an attached image can be removed. [automated test]
- Posts come back newest first, a new post is saved to the live server, and empty or over-500-character posts are refused. [automated test]
- The feed loads, loads more and refreshes without error, and deleting your own post removes it from the feed. [automated test]
- The server makes the same person wait 30 seconds between posts. [automated test]
- Posts from the server are read correctly, with and without optional fields. [automated test]

**Was broken, fixed, re-tested and working**

- A short post shows once on its card, in full, in light mode, dark mode and at the largest text size (it used to repeat the text as title and body, then cut it off). [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- A new post appears in the feed straight after posting, without pulling to refresh. [by hand on the simulator]
- The reply banner names the person being replied to (it said only 'Replying to'). [by hand on the simulator]

**Tested and still not right**

- A just-posted comment shows a sensible time label (it read 'in 0 seconds'). [by hand on the simulator]
- The feed downloads its 20 posts once per visit (it downloads them twice). [measured from logs]
- Creating a 'review'-type system post through a helper the app never calls: the post is saved as an ordinary post, so the test fails. [automated test]

**Not tested**

- The second automated delete-your-own-post check did not run to the end: its set-up post was refused by the 30-second posting limit, so the test failed before reaching the delete.
- Reporting or deleting a Town Hall post from the device was not tested.

## Leaderboard

**Tested and working**

- The leaderboard opens for a guest and switches time period (the report says all four periods; the session shows This Month and All Time being selected). [by hand on the simulator]
- The This Month leaderboard reflects XP earned that day straight away (5 XP for a request, 5 XP for a fulfilment). [by hand on the simulator]
- Leaderboard from the live server: entries are ordered by points, spotlights are valid with no member repeated, the signed-in member's rank lookup works, a member's leaderboard badges match their profile badges, and the this-month and this-year date ranges are right. [automated test]
- A repeat leaderboard load reuses the saved list, at most two badges show per row, and every badge has a name, emoji and icon. [automated test]

**Was broken, fixed, not re-tested since**

- Switching between Town Hall and Leaderboard keeps the loaded results and the selected period (it reset to This Month and reloaded every time). [by hand on the simulator]
- Long names on leaderboard rows stay to two lines (they wrapped to five; numbered rows were also misaligned with medal rows). [by hand on the simulator]

## Profile

**Tested and working**

- A guest can open another member's public profile from a leaderboard row. [by hand on the simulator]
- Your own profile shows badges, reviews and stats. [by hand on the simulator]
- The Edit Profile screen opens (nothing was changed or saved). [by hand on the simulator]
- The signed-in member's own profile loads from the server without error. [automated test]
- Editing a profile: an empty name and an invalid phone number are rejected (nothing is saved to the server by these tests). [automated test]
- A saved profile is reused without a new download, and the saved copy is cleared after an update. [automated test]
- Phone numbers: valid US and international numbers are accepted, too-short and too-long ones are rejected, they are stored in standard international format, and they display in full or masked to the last four digits. [automated test]

**Tested and still not right**

- The stats card labels fit on one line ('My Savings' wraps and misaligns the row). [by hand on the simulator]

**Not tested**

- Saving profile changes (name, phone, car, photo) was not tested.

## Settings

**Tested and working**

- Settings opens and every section displays; the push switch shows On once loaded. [by hand on the simulator]
- Settings shows the Apple ID as linked, and the language and appearance pickers are present (they were not changed). [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- The Push Notifications section has no stray blank row (one was seen twice). [by hand on the simulator]

**Tested and still not right**

- Pulling down on Settings does nothing (a refresh spinner appears although nothing refreshes). [by hand on the simulator]
- Opening Settings produces no background-thread warnings in the app log (six fired). [measured from logs]

**Not tested**

- Changing settings (notification switches, language, appearance) was not tested.
- Unlinking an Apple ID was not tested.

## Admin

**Tested and working**

- The Admin Panel shows stats, the announcement tool, members and pending approvals. [by hand on the simulator]
- The Reports screen shows pending, resolved and dismissed lists with Hide and Dismiss actions. [by hand on the simulator]
- An admin dismisses a report through a confirmation sheet with an optional note; the report is marked dismissed with reviewer and time, and a moderation record is written. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- The admin 'Active' request count leaves out past-dated requests (it showed 124-125 including them). [by hand on the simulator]

**Tested and still not right**

- The Reports list shows a simple time-ago label (it shows two units ticking every second, e.g. '5 min, 27 sec'). [by hand on the simulator]
- The pending-members check runs only when needed (it ran five times in a few minutes, on every Profile visit). [measured from logs]

**Not tested**

- Approving or rejecting members, hiding content, banning, and broadcast announcements were not tested.

## Moderation, reporting, blocking

**Tested and working**

- Report a ride: tap the flag, choose Spam and submit; the report is saved and the admins are notified. [by hand on the simulator]
- Block a member from their public profile; the block is saved and the menu changes to 'User Blocked'. [by hand on the simulator]
- After blocking someone, their conversations disappear from the Messages list. [by hand on the simulator]
- Settings > Blocked Users lists the blocked person with their avatar. [by hand on the simulator]
- Unblock someone from Blocked Users after a confirmation; the block is removed and the list shows its empty state. [by hand on the simulator]

**Was broken, fixed, re-tested and working**

- The server accepts a report against a person, message, post, comment, ride or favor, and ignores an immediate repeat of the same report (repeats against a person or message used to notify every admin each time). [checked against the live server]
- You cannot report a message from a conversation you are not in, or file a report in someone else's name. [checked against the live server]

**Was broken, fixed, not re-tested since**

- The Send Message button on a blocked person's profile stayed usable; it is now disabled. [by hand on the simulator]
- The Blocked Users row read 'Blocked on 2m ago'; the wording was corrected. [by hand on the simulator]
- The report sheet was titled 'Report Message' when reporting a ride; the title now follows what is being reported. [by hand on the simulator]
- Reports are limited to 20 per person per hour. [code read only]
- Banned members, and members removed from a conversation, cannot edit their old messages. [code read only]
- Banned or not-yet-approved members cannot send messages through the reply route. [code read only]
- A message hidden by moderation no longer shows as the preview line in the conversation list. [code read only]

**Tested and still not right**

- A reported member can read who reported them and what was written; the fix is written but must be run by the owner. [code read only]

**Not tested**

- Reporting a message, Town Hall post, comment or person from the app's own screens (only a ride was reported by hand; the other kinds were checked on the server only).
- An admin hiding reported content or banning a member, and what a banned member then sees.

## Accessibility and appearance

**Tested and working**

- Dark mode on every screen a guest can reach. [by hand on the simulator]
- Largest accessibility text size on Welcome, Requests, Community, Leaderboard and Profile: every screen scrolls and everything can be reached. [by hand on the simulator]
- Dark mode in a conversation: messages and the message box display correctly. [by hand on the simulator]
- A conversation opened at the largest text size: message bubbles, the Delivered/Read line and the message box are readable. [by hand on the simulator]

**Was broken, fixed, re-tested and working**

- Requests filter tiles at the largest text size were cut down to 'O…', 'M…', 'Cl…'; they now stack and show their full names. [by hand on the simulator]
- Request cards at the largest text size: name, date and status stack and stay readable. [by hand on the simulator]
- Ride Details at the largest text size: the header and Route card stack and stay readable. [by hand on the simulator]
- Town Hall post header at the largest text size broke names mid-word; the author row now stacks. [by hand on the simulator]
- Conversation list at the largest text size showed '…' instead of the contact's name; the name now shows on its own lines with the time beneath. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- Ride Details at the largest text size: the time row broke apart ('7:00 A M'); a fix was made afterwards. [by hand on the simulator]
- Ride Details at the largest text size: the 'Estimated Rideshare Savings' line and amount broke mid-word; fixed. [by hand on the simulator]
- Leaderboard empty-state message was cut off at the largest text size; fixed. [by hand on the simulator]
- Leaderboard names wrapped to five lines at large text sizes; names are now limited to two lines (the row misalignment noted with it is not mentioned in the fix). [by hand on the simulator]
- Dark-mode backgrounds were three different blacks across Requests, Profile and Leaderboard; they now use one standard set. [by hand on the simulator]
- Fourteen labels in messaging showed raw placeholder codes (Today/Yesterday, undo send, reply counts, image failed, several screen-reader labels); wording was added in six languages. [by hand on the simulator]

**Tested and still not right**

- Changing the text size while a conversation is already open: visible messages keep the old size until the conversation is reopened. [by hand on the simulator]
- Sign-up, Edit Profile and Edit Ride fields have no visible labels, only placeholder text. [by hand on the simulator]

**Not tested**

- Landscape orientation.

## Performance and stability

**Tested and working**

- No crashes and no layout or runtime warnings in the app log during the whole guest pass. [measured from logs]
- Message send speed measured: the bubble appears in 27 ms and the server confirms in 770 ms. [measured from logs]
- Cold launch time measured: usable about 2.1 seconds after launch (debug build on the simulator). [measured from logs]
- Memory use measured: about 178 MB as an idle guest before the fixes; about 47 MB on the Messages list and about 109 MB inside a conversation afterwards. [measured from logs]
- Refresh rules: data is fetched when never loaded or stale and not when fresh, a refresh already in progress is not interrupted, and sign-out clears everything. [automated test]
- Duplicate requests are merged, rapid repeated taps are blocked, failed network calls are retried with growing delays, and cancelled work stops. [automated test]
- Temporary saved copies of profiles, rides, favors and conversations are returned until they expire or are cleared. [automated test]

**Was broken, fixed, re-tested and working**

- The app sits at about 0% processor use when idle on Requests, Community, the Messages list and inside an open conversation (it was pinned near 100% on every screen, with taps landing seconds late). [measured from logs]
- Opening a conversation makes two reaction requests and then stops (it was about 2,000 a minute from one phone). [measured from logs]
- Opening a brand-new, empty conversation crashed the app during the evening work (caused by a debugging line added that evening); fixed, and the empty conversation then opened with a working message box. [by hand on the simulator]

**Was broken, fixed, not re-tested since**

- The app froze completely after about 90 minutes of use; the cause was fixed, but no long session was repeated afterwards. [by hand on the simulator]
- The app crashed once moving between a conversation, its media gallery and in-thread search; a fix was applied, but that sequence was not run again. [by hand on the simulator]
- Returning to the Requests tab forced a full reload from the server every time; it now reloads only on first load and on pull-to-refresh. [measured from logs]
- Switching between Town Hall and Leaderboard reloaded the leaderboard and reset its selected period each time; fixed. [measured from logs]

**Tested and still not right**

- Opening Settings produced six 'updating the screen from a background thread' warnings in the app log. [measured from logs]
- Town Hall downloads the same page of 20 posts twice on each visit. [measured from logs]
- An open conversation receives every reaction made anywhere in the community and discards the ones that are not its own. [measured from logs]
- Visiting a conversation's media gallery and coming back disconnects the conversation and reloads its 50 messages. [measured from logs]
- The admin pending-approvals check is repeated on every Profile visit and return to the app (five times in a few minutes). [measured from logs]

## Backend and security

**Tested and working**

- After the evening's security fixes, the real app can still load the conversation list, send, reply, edit, unsend and mute. [by hand on the simulator]
- Ordinary signed-in users are not allowed to queue push notifications directly. [checked against the live server]
- All 56 privileged server routines the app can call were read through; 35 were judged safe as they stood. [code read only]
- The app's server address and public key are present in the expected format and the server connection object starts up. [automated test]

**Was broken, fixed, re-tested and working**

- Nobody, signed in or not, can change or delete other people's profiles through the public member listing any more; guests can still read it. [checked against the live server]
- A new user can no longer make themselves an admin or pre-approved when their profile is created. [checked against the live server]
- A signed-in user cannot add themselves to someone else's conversation, change their join date or take over ownership; members can still send, mute and rename, and the creator can still add members. [checked against the live server]
- Creating a conversation now records its members (the server used to reject this, leaving empty 'Chat' conversations). [checked against the live server]
- Loading the conversation list no longer sends other members' email, phone number, ban status or admin flag to the phone. [checked against the live server]
- Read receipts cannot be faked on conversations you are not a member of; marking your own conversation as read still works. [checked against the live server]
- A claimer cannot alter their completion reminder or mark a request complete unless it is confirmed and claimed by them; the normal 'Not yet' and 'Completed' answers still work. [checked against the live server]
- Notification wording is written by the server: a claimer can no longer push their own text to a poster, and a repeated update notice is not duplicated. [checked against the live server]
- The server no longer reveals other people's notification settings or admin status, and you can only check for a block between yourself and one other person. [checked against the live server]
- Lookups of who is banned, who is an admin and who is in which conversation answer only about the person asking; admins still see all members and guests can still browse. [checked against the live server]
- You can edit your own message, but not another member's message or a system announcement line. [checked against the live server]
- The moderation history now allows the one clean-up step needed when deleting the account of an admin who moderated or a member whose report was actioned (this step only, not a full account deletion). [checked against the live server]

**Was broken, fixed, not re-tested since**

- Open requests whose time has passed are set to expire automatically every night at 03:15 (favors with no time expire from midnight of their date); the job is installed but was not seen running. [code read only]

**Tested and still not right**

- Deleting an account fails for every user on the live backend today; the fix is written but must be run by the owner. (The deletion routine was also read and leaves some kinds of data behind.) [checked against the live server]
- A freshly signed-up account can delete every pending applicant; the fix is written but must be run by the owner. [code read only]
- Linking an Apple identity trusts values supplied by the app; an interim fix is written but was not applied because it needs a real-device Sign in with Apple test. [code read only]
- Two low-severity items were left open: sign-up accepts an email and inviter chosen by the caller (shown to admins on the approval screen), and the leaderboard highlights do heavy work for guests. [code read only]
- The database's built-in health checks were run: 30 overlapping access-rule warnings, 49 unused indexes, and leaked-password protection still switched off. [checked against the live server]

**Not tested**

- Deleting an account from start to finish, and linking or unlinking Sign in with Apple, were never run against the live backend.

## Unit tests

**Tested and working**

- Full automated suite on the final code, with a user signed in on the simulator: 376 checks, 364 passed, 2 failed, 10 skipped. [automated test]
- New automated checks for the day's messaging fixes pass: the conversation list and an open conversation only start listening once their screen appears, lists of message ids reach the server in the right format, and an edited message keeps its sent status. [automated test]
- New automated checks for the evening's messaging changes pass: Delivered/Read status, conversation-list time labels, and hiding empty duplicate threads. [automated test]

**Tested and still not right**

- Side effect of the three signed-in automated runs: they left real test content in the live app (3 open 'Test Pickup' rides, 3 open 'Test Favor' requests, 4 Town Hall posts) and sent 108 new-request notifications to 18 members. None of it has been removed yet; the delete SQL is in the QA report, section 8.7. [checked against the live server]

**Not tested**

- Ten automated checks were skipped in the final run (ride, favor, message and notification service checks).
- No automated check covers signing in or out, guest mode, the Requests filter tiles, the message box or actually sending a message, adding or removing reactions, Town Hall voting and comments, admin actions, reporting and blocking, settings, or account deletion.

## Other

**Tested and working**

- The app builds with zero errors (43 builds across the day; no new warnings recorded against the starting baseline). [measured from logs]
- A red 'No Internet Connection' banner appears when the connection drops. [by hand on the simulator]
- Photos are shrunk before upload: avatar, message-image and full-size settings stay under their size limits and keep their proportions, and small images are left alone. [automated test]

**Not tested**

- Things that need a real phone: the camera and vibration feedback (also push banners and the launch screen on a device).
