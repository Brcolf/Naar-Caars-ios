# Graceful User Departure Request Handling

**Date:** 2026-03-03

## Problem

When a user deletes their account, in-flight requests they're involved in are not cleaned up properly:

- **Claimer leaves:** Rides/favors stay in `confirmed` status with a dangling `claimed_by` reference. Poster is stuck with a request no one can fulfill or complete. Completion reminders fire for a non-existent user.
- **Poster leaves:** Their requests are cascade-deleted, but claimers get no notification — the request just vanishes.
- **Completed but unreviewed:** Review notifications reference a deleted user, becoming permanently stuck (can't complete the action, can't dismiss).

## Design

All changes are in the `delete_user_account` SQL function. Four new cleanup steps run **before** existing cascade deletes.

### 1. Claimer Leaves — Reopen Claimed Requests

Reset `confirmed` rides/favors where departing user is `claimed_by` back to `open`. Notify each poster via `ride_unclaimed`/`favor_unclaimed` notification.

### 2. Poster Leaves — Notify Claimers Before Delete

Before cascade-deleting the poster's rides/favors, loop through any `confirmed` requests with a claimer and send `ride_unclaimed`/`favor_unclaimed` notification to the claimer with body "A request you claimed has been cancelled because the poster left."

### 3. Clean Up Orphaned Review Notifications

Mark `review_request` and `review_reminder` notifications as read where the departing user was the claimer on a completed request. Clear `claimed_by` on those completed requests.

### 4. Clean Up Completion Reminders

Delete completion reminders where `claimer_user_id` is the departing user.

## Files to Change

| File | Change |
|------|--------|
| Database migration (new) | Update `delete_user_account` function with 4 new cleanup steps |

## Notification Types Reused

- `ride_unclaimed` / `favor_unclaimed` — poster already understands these from normal unclaim flow
- Same types used for claimer notification when poster leaves (with different body text)
