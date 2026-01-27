# Cross-Cutting Refactors for Correctness (Epic)
- PRD: Realtime/Caching §§7.1–7.4; anchor registries across PRDs
- Scope: centralized badge state, anchor-aligned routing, realtime subscription audit

## Tasks
1) Central badge state store for tabs + bell icon  
   - Why: Prevent divergence; supports AC-CNT-1..5  
   - Files: `BadgeCountManager`; shared state consumers (tab bars, chrome)  
   - DB: none  
   - Realtime: listeners update store  
   - Anchors: `app.chrome.bellBadge`  
   - ACs: AC-CNT-1..5 (indirect)  
   - QA: All badges reflect same source; tab switches do not recompute ad hoc.

2) Deep-link coordinator aligned to anchor registry (messages, bell, requests)  
   - Why: Anchor usage requirements; supports AC-5, AC-BELL-3, AC-REQ-6/7  
   - Files: `NavigationCoordinator`; push handler; in-app toast taps  
   - DB: none  
   - Realtime: none  
   - Anchors: `messages.*`, `bell.*`, `requests.*` as defined  
   - ACs: AC-5, AC-BELL-3, AC-REQ-6, AC-REQ-7  
   - QA: Each anchor resolves; invalid anchor handled safely (log, no crash).

3) Realtime subscriptions audit (message vs notification channels)  
   - Why: R-RT-1/2; keep message events out of bell feed; supports AC-CNT-2, AC-BELL-2  
   - Files: Supabase realtime setup; message/notification channel configs  
   - DB: none  
   - Realtime: ensure filters by type/user are correct  
   - Anchors: n/a  
   - ACs: AC-CNT-2, AC-BELL-2  
   - QA: Message events update list/badge only; bell feed not updated by message events; subscriptions reconnect cleanly.



