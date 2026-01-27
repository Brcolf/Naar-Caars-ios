# Bell Surface Enablement (Epic)
- PRD: Notifications Surface §§7–10, 8.3 table; AC-BELL-1..5
- Scope: chrome bell entry, feed exclusion/grouping, deep links, announcements read-on-tap

## Tasks
1) Bell icon/badge in main chrome and navigation to bell list  
   - Why: R-BELL-1/2/3, AC-BELL-1  
   - Files: tab headers (Requests/Messages/Community/Profile); `NavigationCoordinator`  
   - DB: none  
   - New types: anchor mapping for chrome badge  
   - Realtime: consume bell count from badge store  
   - Anchors: `app.chrome.bellIcon`, `app.chrome.bellBadge`, `bell.notificationsList`  
   - ACs: AC-BELL-1  
   - QA: Bell visible on all main pages; tap opens bell list; badge shows non-message count.

2) Enforce feed exclusion and grouping (subject-based; announcements grouped by notification id)  
   - Why: R-FEED-1/2, R-GROUP-1/2, AC-BELL-2/4  
   - Files: `NotificationService.fetchNotifications`; `NotificationsListViewModel`  
   - DB: query/view filter to exclude message types; grouping logic updates  
   - Realtime: subscription filter for non-message notification inserts  
   - Anchors: `bell.notificationsList.row(notificationId)`  
   - ACs: AC-BELL-2, AC-BELL-4  
   - QA: Message events never appear; entries grouped per subject; announcements grouped strictly by notification id.

3) Deep-link mapping per notification type to anchors  
   - Why: R-DEEPLINK-1/2, §8.3 table, AC-BELL-3  
   - Files: `NotificationsListViewModel.handleNotificationTap`; `NavigationCoordinator`  
   - DB: ensure subject IDs available in payloads  
   - Realtime: none  
   - Anchors: e.g., `community.townHall.postCard(postId)`, `profile.admin.pendingUsersList`, `bell.announcements.row(notificationId)`, `app.entry.enterApp`  
   - ACs: AC-BELL-3  
   - QA: Each notification type navigates to correct anchor; highlight where applicable.

4) Announcements surfaces and read-on-tap behavior  
   - Why: R-ANN-1..3, R-ANN-READ-1/2, AC-BELL-3/4  
   - Files: `NotificationsListView`; new `AnnouncementsView`; `NotificationService` read handling  
   - DB: query for announcement types  
   - Anchors: `bell.announcements`, `bell.announcements.row(notificationId)`  
   - ACs: AC-BELL-3, AC-BELL-4  
   - QA: Opening announcements list does not mark read; tapping an announcement marks that row read; bell badge updates accordingly.



