# Badge Truth & Reconciliation (Epic)
- PRD: Realtime/Caching §§7–9, CONST-POLL-INTERVAL; AC-CNT-1..5
- Scope: counts RPC, periodic polling, post-action reconcile, cache policy

## Tasks
1) Server-authoritative counts RPC (optionally returns per-conversation/per-request detail)  
   - Why: D-CNT-1, R-COUNTS-1..3, AC-CNT-1  
   - Files: `database/` new migration; `BadgeCountManager` client wrapper  
   - DB: RPC/view returning totals + optional per-conversation/per-request; RLS: scoped to `auth.uid()`; service role allowed  
   - Realtime: none  
   - Anchors: badge consumers (messages/requests/bell)  
   - ACs: AC-CNT-1  
   - QA: RPC matches expected counts for fixtures; respects RLS.

2) Periodic polling cadence (10s connected, 90s disconnected)  
   - Why: CONST-POLL-INTERVAL, R-RECON-4/5, AC-CNT-3  
   - Files: `BadgeCountManager`; lifecycle hooks  
   - DB: none  
   - Realtime: needs connection status flag to choose interval  
   - Anchors: badge displays  
   - ACs: AC-CNT-3  
   - QA: Timer interval switches on disconnect/reconnect; counts overwrite optimistic state.

3) Post-action reconciliation after read/seen actions  
   - Why: R-RECON-3, AC-CNT-1/5  
   - Files: `BadgeCountManager`; message read flows; request read flows; bell read flows  
   - DB: uses counts RPC  
   - Realtime: none  
   - Anchors: badge displays  
   - ACs: AC-CNT-1, AC-CNT-5  
   - QA: After marking read, badges refresh from RPC and ignore cached lists.

4) Cache policy enforcement (counts not derived from cached lists)  
   - Why: R-CACHE-1..3, AC-CNT-5  
   - Files: `NotificationService.fetchNotifications`; `MessageService.fetchConversations`; cache layers  
   - DB: none  
   - Realtime: none  
   - Anchors: n/a  
   - ACs: AC-CNT-5  
   - QA: With stale cache, badges correct after reconcile; cached lists cannot override RPC counts.



