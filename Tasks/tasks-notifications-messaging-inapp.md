# Messaging In-App Delivery & Suppression (Epic)
- PRD: In-app Messages §§8–17; AC-1..6
- Scope: latest-only toast, thread suppression, incremental read, auto-scroll/affordance

## Tasks
1) Foreground handling rules (no banner in thread; latest-only toast on list; in-app UI on Messages tab but not thread)  
   - Why: R-THREAD-1, R-LIST-2, R-OUTSIDE-3, D-MSG-3/4, AC-1/2/6  
   - Files: `NaarsCars/Core/Services/PushNotificationService.swift`; push delegate; `ConversationsListViewModel`; `ConversationsListView`  
   - DB: none  
   - New types: toast view model/state (latest-only)  
   - Realtime: use `messages` insert subscription to trigger toast  
   - Anchors: `messages.conversationsList.inAppToast`, `messages.thread(conversationId)`  
   - ACs: AC-1, AC-2, AC-6  
   - QA: In thread, incoming message shows inline with no toast/banner; on list, only latest toast appears (replaces prior); on Messages tab but not thread, no OS banner—toast only.

2) Toast tap deep links to thread bottom  
   - Why: R-LIST-2, R-OUTSIDE-2, D-MSG-5, AC-5  
   - Files: `ConversationsListView`; `NavigationCoordinator`; deep-link handler  
   - DB: none  
   - New types: toast tap payload carrying conversation_id/message_id  
   - Realtime: none beyond existing  
   - Anchors: `messages.conversationsList.inAppToast`, `messages.thread(conversationId)`, `messages.thread.bottom`  
   - ACs: AC-5  
   - QA: Tap toast → Messages tab → thread → scrolled to bottom.

3) Incremental read bound to visible message rows  
   - Why: R-INCR-1/2/3, R-CLEAR-1/2, AC-4  
   - Files: `ConversationDetailView`; `ConversationDetailViewModel`; `MessageService.markAsRead`  
   - DB: none (unless backend needs per-message IDs)  
   - New fields: visible-message tracking in view model  
   - Realtime: none  
   - Anchors: `messages.thread.message(messageId)`, `messages.thread.bottom`  
   - ACs: AC-4  
   - QA: With 50 unread, only visible subset clears; scrolled-up state keeps new arrivals unread until seen.

4) Auto-scroll vs “new messages” affordance  
   - Why: R-THREAD-2, AC-6  
   - Files: `ConversationDetailView`; `ScrollToBottomButton`  
   - DB: none  
   - Realtime: none  
   - Anchors: `messages.thread.bottom`, `messages.thread.scrollToBottomButton`  
   - ACs: AC-6  
   - QA: At bottom auto-scrolls; when above, no force scroll—affordance appears to jump to bottom.


