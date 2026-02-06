# Notification System Overhaul - Implementation Plan

## Overview

This document outlines the complete notification system overhaul for Naar's Cars iOS app, covering both in-app notifications and Apple Push Notifications (APNs).

**Date**: January 2026  
**Status**: Implementation Ready

---

## Design Decisions Summary

Based on requirements discussion:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| New request notifications | All users, cannot disable | Small community, everyone is potential fulfiller |
| Q&A participants | Requestor + co-requestors only | Q&A stops once claimed; use messages after |
| Completion reminders | Supabase pg_cron | Server-side reliability, ~1 min granularity |
| Actionable notifications | Yes/No from notification | "No" resets 1-hour timer |
| Town Hall vs Announcements | Separate types | Announcements cannot be disabled, Town Hall can be batched |
| Town Hall batching | 3-5 minutes | Reduce notification spam |
| Admin approval notifications | Push + in-app + badge | All admins notified |
| Push permission timing | On pending approval page | Allows approval push to be delivered |
| Communication Notifications | Deferred | Requires significant Apple-side setup |

---

## Phase 1: Database Schema & Notification Types

### 1.1 Update NotificationType Enum (iOS)

Add these new notification types to `AppNotification.swift`:

```swift
enum NotificationType: String, Codable {
    // Existing
    case message = "message"
    case rideUpdate = "ride_update"
    case rideClaimed = "ride_claimed"
    case rideUnclaimed = "ride_unclaimed"
    case favorUpdate = "favor_update"
    case favorClaimed = "favor_claimed"
    case favorUnclaimed = "favor_unclaimed"
    case review = "review"
    case reviewReceived = "review_received"
    case reviewReminder = "review_reminder"
    case announcement = "announcement"           // Admin announcements (cannot disable)
    case adminAnnouncement = "admin_announcement"
    case broadcast = "broadcast"
    case userApproved = "user_approved"
    case qaActivity = "qa_activity"
    case other = "other"
    
    // NEW TYPES
    case newRide = "new_ride"                    // New ride posted (cannot disable)
    case newFavor = "new_favor"                  // New favor posted (cannot disable)
    case townHallPost = "town_hall_post"         // New Town Hall post
    case townHallComment = "town_hall_comment"   // Comment on Town Hall post
    case townHallReaction = "town_hall_reaction" // Reaction on Town Hall post
    case completionReminder = "completion_reminder" // Ask if request completed
    case pendingUserApproval = "pending_user_approval" // Admin: new user awaiting approval
    case addedToConversation = "added_to_conversation" // Added to a message thread
}
```

### 1.2 Update AppNotification Model

Add new linked IDs:

```swift
struct AppNotification {
    // ... existing fields ...
    
    // NEW: Additional linked IDs
    let townHallPostId: UUID?
    let requestType: String?  // "ride" or "favor" for new request notifications
}
```

### 1.3 Database Migration: Notifications Table

```sql
-- Migration: Add new columns to notifications table
ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS town_hall_post_id UUID REFERENCES town_hall_posts(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS request_type TEXT; -- 'ride' or 'favor'

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_notifications_town_hall_post_id ON notifications(town_hall_post_id);
```

### 1.4 Add User Preference: Town Hall Notifications

```sql
-- Migration: Add town hall notification preference
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS notify_town_hall BOOLEAN DEFAULT true;
```

Update `Profile.swift` model to include `notifyTownHall`.

---

## Phase 2: Database Triggers for Notification Creation

### 2.1 New Request Trigger (Rides)

```sql
CREATE OR REPLACE FUNCTION notify_new_ride()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert notification for ALL users (except poster)
    INSERT INTO notifications (user_id, type, title, body, ride_id, request_type)
    SELECT 
        p.id,
        'new_ride',
        'New Ride Request',
        NEW.posted_by_name || ' needs a ride to ' || NEW.destination,
        NEW.id,
        'ride'
    FROM profiles p
    WHERE p.approved = true
      AND p.id != NEW.posted_by;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_ride_created
AFTER INSERT ON rides
FOR EACH ROW
EXECUTE FUNCTION notify_new_ride();
```

### 2.2 New Request Trigger (Favors)

```sql
CREATE OR REPLACE FUNCTION notify_new_favor()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert notification for ALL users (except poster)
    INSERT INTO notifications (user_id, type, title, body, favor_id, request_type)
    SELECT 
        p.id,
        'new_favor',
        'New Favor Request',
        NEW.posted_by_name || ' needs help: ' || LEFT(NEW.title, 50),
        NEW.id,
        'favor'
    FROM profiles p
    WHERE p.approved = true
      AND p.id != NEW.posted_by;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_favor_created
AFTER INSERT ON favors
FOR EACH ROW
EXECUTE FUNCTION notify_new_favor();
```

### 2.3 Claim/Unclaim Triggers

```sql
-- Ride claimed trigger
CREATE OR REPLACE FUNCTION notify_ride_claimed()
RETURNS TRIGGER AS $$
DECLARE
    claimer_name TEXT;
BEGIN
    -- Only trigger when status changes to 'confirmed' (claimed)
    IF NEW.status = 'confirmed' AND (OLD.status IS NULL OR OLD.status != 'confirmed') THEN
        SELECT name INTO claimer_name FROM profiles WHERE id = NEW.claimed_by;
        
        -- Notify requestor
        INSERT INTO notifications (user_id, type, title, body, ride_id)
        VALUES (
            NEW.posted_by,
            'ride_claimed',
            'Your Ride Was Claimed!',
            claimer_name || ' is helping with your ride',
            NEW.id
        );
        
        -- Notify co-requestors
        INSERT INTO notifications (user_id, type, title, body, ride_id)
        SELECT 
            rp.user_id,
            'ride_claimed',
            'Ride Was Claimed!',
            claimer_name || ' is helping with the ride you''re on',
            NEW.id
        FROM ride_participants rp
        WHERE rp.ride_id = NEW.id
          AND rp.user_id != NEW.posted_by
          AND rp.user_id != NEW.claimed_by;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Similar triggers for unclaim, favor_claimed, favor_unclaimed
```

### 2.4 Q&A Activity Trigger

```sql
CREATE OR REPLACE FUNCTION notify_qa_activity()
RETURNS TRIGGER AS $$
DECLARE
    asker_name TEXT;
    request_title TEXT;
    request_owner UUID;
BEGIN
    SELECT name INTO asker_name FROM profiles WHERE id = NEW.user_id;
    
    -- Get request owner and title based on whether it's a ride or favor
    IF NEW.ride_id IS NOT NULL THEN
        SELECT posted_by, destination INTO request_owner, request_title 
        FROM rides WHERE id = NEW.ride_id;
        
        -- Only allow Q&A if ride is not claimed
        IF EXISTS (SELECT 1 FROM rides WHERE id = NEW.ride_id AND status = 'confirmed') THEN
            RETURN NEW; -- Skip notification, ride is claimed
        END IF;
    ELSIF NEW.favor_id IS NOT NULL THEN
        SELECT posted_by, title INTO request_owner, request_title 
        FROM favors WHERE id = NEW.favor_id;
        
        IF EXISTS (SELECT 1 FROM favors WHERE id = NEW.favor_id AND status = 'confirmed') THEN
            RETURN NEW; -- Skip notification, favor is claimed
        END IF;
    END IF;
    
    -- Notify requestor (if not the asker)
    IF request_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, title, body, ride_id, favor_id)
        VALUES (
            request_owner,
            'qa_activity',
            'New Question on Your Request',
            asker_name || ' asked: "' || LEFT(NEW.content, 40) || '..."',
            NEW.ride_id,
            NEW.favor_id
        );
    END IF;
    
    -- Notify co-requestors for rides
    IF NEW.ride_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, type, title, body, ride_id)
        SELECT 
            rp.user_id,
            'qa_activity',
            'New Question on Ride',
            asker_name || ' asked a question',
            NEW.ride_id
        FROM ride_participants rp
        WHERE rp.ride_id = NEW.ride_id
          AND rp.user_id != NEW.user_id
          AND rp.user_id != request_owner;
    END IF;
    
    -- Notify previous question askers (thread participants)
    INSERT INTO notifications (user_id, type, title, body, ride_id, favor_id)
    SELECT DISTINCT 
        qa.user_id,
        'qa_activity',
        'New Reply in Q&A Thread',
        asker_name || ' replied',
        NEW.ride_id,
        NEW.favor_id
    FROM request_qa qa
    WHERE (qa.ride_id = NEW.ride_id OR qa.favor_id = NEW.favor_id)
      AND qa.user_id != NEW.user_id
      AND qa.user_id != request_owner;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.5 Town Hall Post Trigger (with batching support)

```sql
-- Town Hall posts use a queue for batching
CREATE TABLE IF NOT EXISTS town_hall_notification_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES town_hall_posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed BOOLEAN DEFAULT false
);

CREATE OR REPLACE FUNCTION queue_town_hall_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Queue the notification for batch processing
    INSERT INTO town_hall_notification_queue (post_id)
    VALUES (NEW.id);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_town_hall_post_created
AFTER INSERT ON town_hall_posts
FOR EACH ROW
EXECUTE FUNCTION queue_town_hall_notification();
```

### 2.6 Town Hall Interaction Triggers

```sql
-- Comment trigger
CREATE OR REPLACE FUNCTION notify_town_hall_comment()
RETURNS TRIGGER AS $$
DECLARE
    commenter_name TEXT;
    post_owner UUID;
BEGIN
    SELECT name INTO commenter_name FROM profiles WHERE id = NEW.user_id;
    SELECT user_id INTO post_owner FROM town_hall_posts WHERE id = NEW.post_id;
    
    -- Notify post owner (if not the commenter)
    IF post_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, title, body, town_hall_post_id)
        VALUES (
            post_owner,
            'town_hall_comment',
            'New Comment on Your Post',
            commenter_name || ' commented: "' || LEFT(NEW.content, 40) || '..."',
            NEW.post_id
        );
    END IF;
    
    -- Notify others who interacted (voted or commented)
    INSERT INTO notifications (user_id, type, title, body, town_hall_post_id)
    SELECT DISTINCT user_id, 'town_hall_comment', 'New Comment on Post', commenter_name || ' also commented', NEW.post_id
    FROM (
        SELECT user_id FROM town_hall_comments WHERE post_id = NEW.post_id AND user_id != NEW.user_id AND user_id != post_owner
        UNION
        SELECT user_id FROM town_hall_votes WHERE post_id = NEW.post_id AND user_id != NEW.user_id AND user_id != post_owner
    ) AS interactors;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Vote trigger (similar pattern)
CREATE OR REPLACE FUNCTION notify_town_hall_vote()
RETURNS TRIGGER AS $$
DECLARE
    voter_name TEXT;
    post_owner UUID;
    vote_text TEXT;
BEGIN
    SELECT name INTO voter_name FROM profiles WHERE id = NEW.user_id;
    SELECT user_id INTO post_owner FROM town_hall_posts WHERE id = NEW.post_id;
    vote_text := CASE WHEN NEW.vote_type = 'upvote' THEN 'liked' ELSE 'reacted to' END;
    
    -- Only notify post owner
    IF post_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, title, body, town_hall_post_id)
        VALUES (
            post_owner,
            'town_hall_reaction',
            'Someone ' || vote_text || ' Your Post',
            voter_name || ' ' || vote_text || ' your post',
            NEW.post_id
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.7 Admin Approval Queue Trigger

```sql
CREATE OR REPLACE FUNCTION notify_admins_new_pending_user()
RETURNS TRIGGER AS $$
BEGIN
    -- When a new unapproved user is created, notify all admins
    IF NEW.approved = false THEN
        INSERT INTO notifications (user_id, type, title, body)
        SELECT 
            p.id,
            'pending_user_approval',
            'New User Awaiting Approval',
            NEW.name || ' (' || NEW.email || ') is waiting for approval',
        FROM profiles p
        WHERE p.is_admin = true
          AND p.approved = true;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_pending_user
AFTER INSERT ON profiles
FOR EACH ROW
EXECUTE FUNCTION notify_admins_new_pending_user();
```

### 2.8 User Approved Trigger

```sql
CREATE OR REPLACE FUNCTION notify_user_approved()
RETURNS TRIGGER AS $$
BEGIN
    -- When user is approved, send them a notification
    IF NEW.approved = true AND (OLD.approved = false OR OLD.approved IS NULL) THEN
        INSERT INTO notifications (user_id, type, title, body)
        VALUES (
            NEW.id,
            'user_approved',
            'Welcome to Naar''s Cars!',
            'Your account has been approved. Tap to enter the app.'
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_user_approved
AFTER UPDATE ON profiles
FOR EACH ROW
EXECUTE FUNCTION notify_user_approved();
```

---

## Phase 3: Unified Push Notification Edge Function

### 3.1 Architecture

Create a unified `send-notification` edge function that:
1. Listens for new rows in `notifications` table (via webhook)
2. Checks user notification preferences
3. Sends APNs push if appropriate
4. Updates notification record with push status

### 3.2 Webhook Configuration

Configure Supabase Database Webhook:
- Table: `notifications`
- Event: INSERT
- Target: `send-notification` edge function

### 3.3 Edge Function: send-notification

See `supabase/functions/send-notification/index.ts` for implementation.

Key features:
- Fetches user's push tokens
- Checks user preferences based on notification type
- Maps notification type to APNs payload
- Handles badge count calculation
- Supports actionable notifications (completion reminder)

---

## Phase 4: Supabase pg_cron for Completion Reminders

### 4.1 Enable pg_cron Extension

```sql
-- Enable pg_cron (requires Supabase Pro or self-hosted)
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

### 4.2 Completion Reminder Queue Table

```sql
CREATE TABLE completion_reminder_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID REFERENCES rides(id) ON DELETE CASCADE,
    favor_id UUID REFERENCES favors(id) ON DELETE CASCADE,
    claimer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    scheduled_for TIMESTAMPTZ NOT NULL,
    sent BOOLEAN DEFAULT false,
    snooze_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT one_request_type CHECK (
        (ride_id IS NOT NULL AND favor_id IS NULL) OR
        (ride_id IS NULL AND favor_id IS NOT NULL)
    )
);

CREATE INDEX idx_completion_reminders_scheduled ON completion_reminder_queue(scheduled_for) WHERE sent = false;
```

### 4.3 Trigger to Queue Completion Reminders

```sql
CREATE OR REPLACE FUNCTION queue_completion_reminder()
RETURNS TRIGGER AS $$
BEGIN
    -- When a ride/favor is claimed, queue a completion reminder for 1 hour after scheduled time
    IF NEW.status = 'confirmed' AND (OLD.status IS NULL OR OLD.status != 'confirmed') THEN
        
        -- For rides
        IF TG_TABLE_NAME = 'rides' THEN
            INSERT INTO completion_reminder_queue (ride_id, claimer_id, scheduled_for)
            VALUES (
                NEW.id,
                NEW.claimed_by,
                NEW.scheduled_time + INTERVAL '1 hour'
            );
        END IF;
        
        -- For favors
        IF TG_TABLE_NAME = 'favors' THEN
            INSERT INTO completion_reminder_queue (favor_id, claimer_id, scheduled_for)
            VALUES (
                NEW.id,
                NEW.claimed_by,
                NEW.scheduled_time + INTERVAL '1 hour'
            );
        END IF;
    END IF;
    
    -- If request is completed or unclaimed, remove from queue
    IF NEW.status IN ('completed', 'open') THEN
        DELETE FROM completion_reminder_queue 
        WHERE (ride_id = NEW.id OR favor_id = NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_ride_status_change_reminder
AFTER UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION queue_completion_reminder();

CREATE TRIGGER on_favor_status_change_reminder
AFTER UPDATE ON favors
FOR EACH ROW
EXECUTE FUNCTION queue_completion_reminder();
```

### 4.4 pg_cron Job to Process Reminders

```sql
-- Run every minute to check for due reminders
SELECT cron.schedule(
    'process-completion-reminders',
    '* * * * *', -- Every minute
    $$
    SELECT send_completion_reminders();
    $$
);

CREATE OR REPLACE FUNCTION send_completion_reminders()
RETURNS void AS $$
DECLARE
    reminder RECORD;
    request_title TEXT;
BEGIN
    FOR reminder IN
        SELECT * FROM completion_reminder_queue
        WHERE scheduled_for <= NOW()
          AND sent = false
    LOOP
        -- Get request title
        IF reminder.ride_id IS NOT NULL THEN
            SELECT destination INTO request_title FROM rides WHERE id = reminder.ride_id;
        ELSE
            SELECT title INTO request_title FROM favors WHERE id = reminder.favor_id;
        END IF;
        
        -- Create notification for claimer
        INSERT INTO notifications (user_id, type, title, body, ride_id, favor_id)
        VALUES (
            reminder.claimer_id,
            'completion_reminder',
            'Is This Request Complete?',
            'Did you complete: ' || request_title || '?',
            reminder.ride_id,
            reminder.favor_id
        );
        
        -- Mark as sent
        UPDATE completion_reminder_queue SET sent = true WHERE id = reminder.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4.5 Town Hall Batch Processing Job

```sql
-- Run every 3 minutes to batch Town Hall notifications
SELECT cron.schedule(
    'process-town-hall-notifications',
    '*/3 * * * *', -- Every 3 minutes
    $$
    SELECT process_town_hall_notification_queue();
    $$
);

CREATE OR REPLACE FUNCTION process_town_hall_notification_queue()
RETURNS void AS $$
DECLARE
    queue_count INT;
    post_ids UUID[];
BEGIN
    -- Get unprocessed posts from last 5 minutes (with some buffer)
    SELECT ARRAY_AGG(DISTINCT post_id), COUNT(DISTINCT post_id)
    INTO post_ids, queue_count
    FROM town_hall_notification_queue
    WHERE processed = false
      AND created_at >= NOW() - INTERVAL '5 minutes';
    
    IF queue_count = 0 THEN
        RETURN;
    END IF;
    
    -- Create batched notification for users who have town hall notifications enabled
    IF queue_count = 1 THEN
        -- Single post, normal notification
        INSERT INTO notifications (user_id, type, title, body, town_hall_post_id)
        SELECT 
            p.id,
            'town_hall_post',
            'New Post in Town Hall',
            author.name || ' posted in Town Hall',
            post_ids[1]
        FROM profiles p
        CROSS JOIN (
            SELECT user_id FROM town_hall_posts WHERE id = post_ids[1]
        ) poster
        LEFT JOIN profiles author ON poster.user_id = author.id
        WHERE p.approved = true
          AND p.notify_town_hall = true
          AND p.id != poster.user_id;
    ELSE
        -- Multiple posts, batched notification
        INSERT INTO notifications (user_id, type, title, body)
        SELECT 
            p.id,
            'town_hall_post',
            queue_count || ' New Posts in Town Hall',
            'Check out what''s new in the community'
        FROM profiles p
        WHERE p.approved = true
          AND p.notify_town_hall = true;
    END IF;
    
    -- Mark as processed
    UPDATE town_hall_notification_queue SET processed = true
    WHERE post_id = ANY(post_ids);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Phase 5: iOS Client - Actionable Notifications & Badge Updates

### 5.1 Register Notification Categories with Actions

In `AppDelegate.swift`:

```swift
func setupNotificationCategories() {
    let completeAction = UNNotificationAction(
        identifier: "COMPLETE_YES",
        title: "Yes, Completed",
        options: [.foreground]
    )
    
    let notCompleteAction = UNNotificationAction(
        identifier: "COMPLETE_NO",
        title: "Not Yet",
        options: []
    )
    
    let completionCategory = UNNotificationCategory(
        identifier: "COMPLETION_REMINDER",
        actions: [completeAction, notCompleteAction],
        intentIdentifiers: [],
        options: []
    )
    
    UNUserNotificationCenter.current().setNotificationCategories([completionCategory])
}
```

### 5.2 Handle Actionable Notification Response

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let userInfo = response.notification.request.content.userInfo
    
    switch response.actionIdentifier {
    case "COMPLETE_YES":
        // Mark request as completed
        if let rideId = userInfo["ride_id"] as? String {
            await markRideComplete(UUID(uuidString: rideId)!)
        } else if let favorId = userInfo["favor_id"] as? String {
            await markFavorComplete(UUID(uuidString: favorId)!)
        }
        
    case "COMPLETE_NO":
        // Snooze - reschedule reminder for 1 hour later
        await snoozeCompletionReminder(userInfo: userInfo)
        
    default:
        // Regular notification tap - navigate to relevant screen
        await handleNotificationTap(userInfo: userInfo)
    }
}

private func snoozeCompletionReminder(userInfo: [AnyHashable: Any]) async {
    // Call edge function or database function to reschedule
    let rideId = userInfo["ride_id"] as? String
    let favorId = userInfo["favor_id"] as? String
    
    try? await SupabaseService.shared.client
        .rpc("snooze_completion_reminder", params: [
            "p_ride_id": rideId,
            "p_favor_id": favorId
        ])
        .execute()
}
```

### 5.3 Update BadgeCountManager

Update to track all new notification types:

```swift
private func calculateRequestsBadgeCount(userId: UUID) async -> Int {
    do {
        let notifications = try await notificationService.fetchNotifications(userId: userId)
        
        // Count unread notifications for Requests tab
        let requestTypes: [NotificationType] = [
            .newRide, .newFavor,           // New requests
            .rideClaimed, .rideUnclaimed,   // Claim status changes
            .favorClaimed, .favorUnclaimed,
            .qaActivity,                     // Q&A
            .completionReminder              // Completion reminders
        ]
        
        return notifications
            .filter { !$0.read && requestTypes.contains($0.type) }
            .count
    } catch {
        return 0
    }
}

private func calculateCommunityBadgeCount(userId: UUID) async -> Int {
    // Track Town Hall post and interaction notifications
    let communityTypes: [NotificationType] = [
        .townHallPost, .townHallComment, .townHallReaction
    ]
    
    let notifications = try? await notificationService.fetchNotifications(userId: userId)
    return notifications?
        .filter { !$0.read && communityTypes.contains($0.type) }
        .count ?? 0
}
```

### 5.4 Admin Badge in Profile/Admin View

Update `AdminPanelView` to show badge on pending approvals section:

```swift
struct AdminPanelView: View {
    @StateObject var viewModel = AdminPanelViewModel()
    
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PendingUsersView()
                } label: {
                    HStack {
                        Label("Pending Approvals", systemImage: "person.badge.clock")
                        Spacer()
                        if viewModel.pendingCount > 0 {
                            Text("\(viewModel.pendingCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            // ... other sections
        }
    }
}
```

---

## Phase 6: Push Permission Flow & Approval Notification

### 6.1 Update PendingApprovalView

Add push notification permission request:

```swift
struct PendingApprovalView: View {
    @State private var hasRequestedPermission = false
    
    var body: some View {
        VStack(spacing: 32) {
            // ... existing UI ...
            
            if !hasRequestedPermission {
                VStack(spacing: 16) {
                    Text("Enable Notifications")
                        .font(.headline)
                    
                    Text("Get notified instantly when your account is approved!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Enable Notifications") {
                        Task {
                            let granted = await PushNotificationService.shared.requestPermission()
                            if granted {
                                // Register device token even though not approved yet
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                            hasRequestedPermission = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}
```

### 6.2 Allow Token Registration for Pending Users

Update RLS policy on `push_tokens` to allow unapproved users:

```sql
-- Allow authenticated users (even pending) to register push tokens
CREATE POLICY "push_tokens_insert_authenticated" ON push_tokens
FOR INSERT WITH CHECK (auth.uid() = user_id);
```

### 6.3 Auto-Transition on Approval

The existing periodic check in `PendingApprovalView` already handles this - when approval push arrives, the periodic check will detect the approved status and transition the user to the main app.

---

## Phase 7: Testing & Integration Verification

### 7.1 Test Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| New ride created | All users get in-app notification + push |
| New favor created | All users get in-app notification + push |
| Ride claimed | Requestor + co-requestors get notification |
| Q&A question posted (unclaimed) | Requestor + co-requestors + thread participants notified |
| Q&A question posted (claimed) | No notification (use messages) |
| Town Hall post | Batched notification to users with preference ON |
| Town Hall comment/vote | Post owner + interactors notified |
| User approved | User gets push + auto-transitions to app |
| New pending user | All admins get notification + badge |
| Completion reminder fires | Claimer gets actionable push |
| Completion reminder "No" | Reminder rescheduled +1 hour |
| Completion reminder "Yes" | Request marked complete, review prompt triggered |

### 7.2 Edge Cases

- User with notifications disabled at OS level
- User with no push token registered
- Multiple devices registered for same user
- Notification preferences respected per type
- Badge count accuracy after marking notifications read
- Deep link navigation from cold start vs warm start

---

## File Changes Summary

### New Files
- `supabase/functions/send-notification/index.ts` - Unified push notification edge function
- `database/076_notification_system_overhaul.sql` - All database migrations
- `NaarsCars/Core/Utilities/NotificationCategories.swift` - Actionable notification setup

### Modified Files
- `NaarsCars/Core/Models/AppNotification.swift` - New notification types
- `NaarsCars/Core/Models/Profile.swift` - Add `notifyTownHall` preference
- `NaarsCars/Core/Services/BadgeCountManager.swift` - Enhanced badge calculation
- `NaarsCars/Core/Services/PushNotificationService.swift` - Actionable notification handling
- `NaarsCars/App/AppDelegate.swift` - Register notification categories
- `NaarsCars/Features/Authentication/Views/PendingApprovalView.swift` - Push permission request
- `NaarsCars/Features/Admin/Views/AdminPanelView.swift` - Badge in admin panel

---

## Implementation Order

1. **Database migrations first** (can be rolled back if needed)
2. **Edge function deployment**
3. **iOS model updates** (NotificationType, AppNotification)
4. **iOS service updates** (BadgeCountManager, PushNotificationService)
5. **iOS view updates** (PendingApprovalView, AdminPanelView)
6. **Testing on simulator/device**
7. **Enable pg_cron jobs**

---

## Notes

- Communication Notifications (for Messages) deferred - requires additional Apple entitlements and SiriKit setup
- pg_cron requires Supabase Pro plan or self-hosted - will verify access before implementing
- All triggers use `SECURITY DEFINER` to bypass RLS when creating notifications for other users


