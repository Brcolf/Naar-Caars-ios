 # Ride estimated cost retry (design)
 
 ## Summary
 Add a lightweight, bounded background retry for ride estimated cost calculation and update to smooth out transient network or service hiccups without changing user-facing behavior.
 
 ## Goals
 - Keep ride creation non-blocking and silent on failure.
 - Retry calculation + update up to two additional times.
 - Minimize overhead and avoid new dependencies.
 
 ## Non-goals
 - No UI changes or user notifications.
 - No persistent retry queue or background task scheduler.
 - No backend architectural changes.
 
 ## Proposed approach
 Keep the existing fire-and-forget task launched after ride creation. Wrap the cost calculation and database update in a bounded retry loop that attempts the full workflow up to three times total (initial attempt plus two retries). Use short exponential backoff delays of 2 seconds and 5 seconds between retries. If any attempt succeeds, log success and return immediately. If all attempts fail, log and return without user-visible effects.
 
 ## Data flow
 1. Ride is created and returned immediately.
 2. Background task begins.
 3. Attempt 1: calculate cost, update `rides.estimated_cost`.
 4. On failure, wait 2s and retry.
 5. Attempt 2: calculate cost, update.
 6. On failure, wait 5s and retry.
 7. Attempt 3: calculate cost, update.
 8. If still failing, exit silently after logging.
 
 ## Error handling and logging
 - Log attempt failures with attempt count and error reason.
 - Respect task cancellation to avoid wasted work during shutdown.
 - Preserve silent failure behavior; no user-facing errors.
 
 ## Testing
 - No new tests planned for this change.
