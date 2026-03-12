---
color: orange
position:
  x: 329
  y: -1078
isContextNode: false
agent_name: Amy
---

# Rides & Favors Module

Community rideshare and favor request system with claiming workflow.

## Architecture

### Views
**Rides:**
- `RidesDashboardView` - List of open/claimed rides with filters
- `CreateRideView` - Form to post new ride requests
- `RideDetailView` - View/claim/message about a ride
- `EditRideView` - Modify existing rides

**Favors:**
- `FavorsDashboardView` - List of open/claimed favors
- `CreateFavorView` - Form to post new favor requests
- `FavorDetailView` - View/claim/message about a favor

**Shared:**
- `RequestsDashboardView` - Unified view with tab switching between rides/favors
- `ClaimSheet` - Confirmation dialog for claiming
- `UnclaimSheet` - Confirmation for unclaiming
- `RequestMapView` - Map visualization for rides

### ViewModels
- **RequestsDashboardViewModel** - Loads rides/favors, syncs to SwiftData
- **CreateRideViewModel** - Validates and creates rides, calculates estimated cost
- **CreateFavorViewModel** - Validates and creates favors
- **ClaimViewModel** - Handles claim/unclaim with rate limiting

### Services
- **RideService** - CRUD for rides, cost estimation via MapKit
- **FavorService** - CRUD for favors
- **ClaimService** - Claim/unclaim logic with RLS updates
- **ReviewService** - Post-completion reviews

## Features

✅ **Ride Requests**: Pickup/destination, date/time, seats, estimated cost
✅ **Favor Requests**: Title/description, location, duration, requirements
✅ **Claiming**: Users can claim open requests
✅ **Participants**: Co-requestors can join rides/favors
✅ **Gifts**: Optional thank-you gifts for helpers
✅ **Reviews**: Star ratings after completion
✅ **Q&A**: Thread of questions/answers on requests
✅ **Cost Estimation**: Background MapKit routing for ride costs

## Critical Issues (BROKEN AS OF FEB 6, 2026)

### 🔴🔴🔴 CLAIM/UNCLAIM COMPLETELY BROKEN

Per `Docs/REQUESTS-MODULE-BROKEN-STATE-REPORT.md`:

**Root Cause: RLS Policy Bug**
```sql
-- Current policy BLOCKS claimers:
-- USING: auth.uid() = user_id OR auth.uid() = claimed_by
-- Problem: When claimed_by is NULL, claimer can't "see" row for UPDATE
```

**User Experience:**
1. User taps "Claim" → sees ClaimSheet
2. Taps "Confirm" → sees green checkmark ✅
3. Sheet dismisses immediately (doesn't wait for API)
4. Request detail still shows as "Open" ❌
5. No error message shown ❌

**Impact:** Claiming appears to work (success UI) but silently fails server-side.

### 🔴 Claim Sheet Doesn't Wait for API
`ClaimSheet.swift` shows success and dismisses without awaiting the claim API call:
```swift
Button("Confirm") {
    onConfirm()  // Starts async Task
    showSuccess = true  // ❌ Immediate, not awaiting
}
```

### 🔴 Claim Errors Never Shown
`ClaimViewModel.error` is set on failure but:
- Not displayed in ClaimSheet
- Not displayed in RideDetailView/FavorDetailView
- User has no feedback on why claim failed

### 🟡 Post Navigation May Fail
After successful post, navigation to detail view uses binding during sheet dismissal. SwiftUI timing may prevent push in some cases.

## Required Fixes

### 1. Fix RLS Policies (Database)
Add policy allowing UPDATE when `claimed_by IS NULL`:
```sql
CREATE POLICY "Users can claim open rides"
ON rides FOR UPDATE TO authenticated
USING (claimed_by IS NULL AND status = 'open')
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');
```

### 2. Make Claim Sheet Await API
Change ClaimSheet to:
- Show loading state while API call runs
- Only show success checkmark AFTER server confirms
- Display errors in sheet if claim fails
- Keep sheet open on error for retry

### 3. Surface Create Errors
Move error display to top of form or use alert so users see post failures.

## Complexity Score: 7/10
**High complexity due to:**
- Multi-step claiming workflow with race conditions
- RLS policy interactions between client and server
- Optimistic UI with reconciliation needs
- Background cost estimation tasks that may conflict with edits

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
