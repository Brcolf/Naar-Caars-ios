# Admin Dashboard Stats Overhaul Design

**Date:** 2026-03-02

## Summary

Replace the current Admin Panel stats cards (Pending users / Members / Active) with operational metrics: Requests Fulfilled, Total Savings, and Active Rides. Each card is tappable, opening a sheet overlay with time-period breakdowns.

## Stats Cards

| Card | Label | Icon | Value | Color |
|------|-------|------|-------|-------|
| 1 | Fulfilled | checkmark.circle.fill | Count of completed rides + favors | Green |
| 2 | Savings | dollarsign.circle.fill | Sum of `estimated_cost` across all rides with a value | Green |
| 3 | Active | clock.fill | Count of rides with status open/pending/confirmed | Orange |

All cards are tappable, opening a sheet modal overlay.

## Overlay: Requests Fulfilled

- Segmented picker: Week / Month / Year (default: Month)
- Prominent total for selected period at top
- Breakdown list: each period with completed ride count + favor count subtotals

## Overlay: Total Savings

- Segmented picker: Week / Month / Year (default: Month)
- Prominent total formatted as currency
- Breakdown list: each period with savings subtotal

## Overlay: Active Rides

- Simple list of all unfinished rides (open + pending + confirmed)
- Each row: poster name, claimer name (if claimed), pickup -> destination, date, status badge
- No time-period pivot - live snapshot

## Data Architecture

### Supabase RPC Functions

1. **`admin_dashboard_stats()`** - Returns top-level card values in a single call:
   - `fulfilled_count`: count of completed rides + favors
   - `total_savings`: sum of `estimated_cost` from all rides with a value
   - `active_rides_count`: count of rides with status in (open, pending, confirmed)

2. **`admin_stats_fulfilled(p_period TEXT, p_count INT)`** - Returns completed request counts grouped by time period (week/month/year)

3. **`admin_stats_savings(p_period TEXT, p_count INT)`** - Returns savings sums grouped by time period

4. **`admin_stats_active_rides()`** - Returns all unfinished rides with poster/claimer profile joins

All RPCs require `is_admin = true` on the calling user's profile.

## Presentation

- Overlays use `.sheet()` presentation (swipe to dismiss)
- Consistent with existing admin modal patterns (AdminInviteView)

## Scope

- Modify: `AdminPanelView`, `AdminPanelViewModel`, `AdminService`
- New: 3 overlay views, 4 Supabase RPC functions, corresponding migration
- No changes to existing data models or non-admin views
