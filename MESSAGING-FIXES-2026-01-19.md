# Messaging Fixes - January 19, 2026

## Issues Fixed

### 1. Pull-to-Refresh Cancellation Error ✅

**Problem**: When pulling down to refresh the ConversationListView, users would see an error: "processing error: cancelled. Please try again."

**Root Cause**: When SwiftUI's `.refreshable` modifier is used and a new refresh is triggered while a previous task is still running, the previous task gets cancelled. The error handler was treating cancellation as a regular error and displaying it to the user.

**Solution**: Added proper cancellation error handling in `ConversationsListViewModel`:
- Check for `Task.isCancelled`
- Check for `CancellationError` type
- Check if error message contains "cancel"
- If any of these are true, log the cancellation but don't show an error to the user

**Files Modified**:
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`
  - Updated `loadConversations()` method
  - Updated `loadMoreConversations()` method

**Code Changes**:
```swift
// Before:
catch {
    self.error = AppError.processingError(error.localizedDescription)
    print("🔴 Error loading conversations: \(error.localizedDescription)")
}

// After:
catch {
    // Don't show error if task was cancelled (happens during pull-to-refresh)
    if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
        print("ℹ️ Load conversations task was cancelled, ignoring error")
    } else {
        self.error = AppError.processingError(error.localizedDescription)
        print("🔴 Error loading conversations: \(error.localizedDescription)")
    }
}
```

---

### 2. Adding Participants to Existing Conversations ✅

**Problem**: Users could create new group messages by adding users, but couldn't add participants to existing message groups.

**Root Cause**: The `UserSearchView` component was calling `dismiss()` (the SwiftUI environment dismiss) but NOT calling the `onDismiss()` callback that was passed to it. This meant the parent view (`MessageDetailsPopup`) never received notification that users were selected, so the participant addition logic never ran.

**Solution**: 
1. Fixed `UserSearchView` to call the `onDismiss()` callback when "Done" or "Cancel" is tapped
2. Added comprehensive logging throughout the participant addition flow to help debug any future issues

**Files Modified**:
- `NaarsCars/UI/Components/Messaging/UserSearchView.swift`
  - Updated "Cancel" button to call `onDismiss()`
  - Updated "Done" button to call `onDismiss()`
  - Added logging to track user selections

- `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
  - Added logging when UserSearchView dismisses
  - Added logging to show selected user count and IDs

- `NaarsCars/Core/Services/MessageService.swift`
  - Added comprehensive logging to `addParticipantsToConversation()` method
  - Logs conversation details, permissions checks, existing participants, and insertion results

**Code Changes**:

```swift
// UserSearchView.swift - Before:
Button("Done") {
    dismiss()
}

// After:
Button("Done") {
    print("🔍 [UserSearchView] Done tapped with \(selectedUserIds.count) selected user(s)")
    onDismiss()
}
```

**Flow**:
1. User opens conversation details (info icon in group chat)
2. Taps "Add Participants"
3. Searches for and selects users in `UserSearchView`
4. Taps "Done"
5. `UserSearchView` calls `onDismiss()` callback
6. `MessageDetailsPopup` receives callback with selected user IDs
7. Calls `MessageService.addParticipantsToConversation()`
8. Service checks permissions (must be creator or existing participant)
9. Filters out users already in conversation
10. Inserts new participants
11. Creates announcement messages (if enabled)
12. Invalidates caches
13. Parent view reloads to show updated participant list

---

## Testing Recommendations

### Test Case 1: Pull-to-Refresh
1. Open Messages tab
2. Pull down to refresh multiple times rapidly
3. **Expected**: No error messages should appear
4. **Expected**: Conversations should load successfully after refresh completes

### Test Case 2: Add Participants to Existing Group
1. Open an existing group conversation (3+ participants)
2. Tap the info icon (top right)
3. Tap "Add Participants"
4. Search for a user
5. Select the user (checkmark should appear)
6. Tap "Done"
7. **Expected**: Sheet dismisses
8. **Expected**: Console shows logs from MessageService about adding participant
9. **Expected**: Conversation details view reloads and shows new participant
10. **Expected**: Announcement message appears in chat (e.g., "John Doe has been added to the conversation")

### Test Case 3: Add Multiple Participants
1. Follow steps 1-3 from Test Case 2
2. Select multiple users (search, select, search again, select)
3. Tap "Done"
4. **Expected**: All selected users are added
5. **Expected**: Multiple announcement messages appear

### Test Case 4: Add Already-Existing Participant
1. Follow steps 1-3 from Test Case 2
2. Try to select a user already in the conversation
3. **Expected**: User shows "Already added" and cannot be selected
4. Or if somehow selected, service should filter them out

---

## Console Logs to Watch For

When adding participants, you should see logs like:
```
🔍 [UserSearchView] Done tapped with 1 selected user(s)
🔍 [MessageDetailsPopup] UserSearchView dismissed with 1 selected user(s)
🔍 [MessageDetailsPopup] Selected user IDs: [UUID-HERE]
✅ [MessageDetailsPopup] Adding 1 participant(s) to conversation UUID-HERE
📥 [MessageService] addParticipantsToConversation called
   Conversation ID: UUID-HERE
   User IDs to add: [UUID-HERE]
   Added by: UUID-HERE
   Create announcement: true
🔍 [MessageService] Fetching conversation details...
✅ [MessageService] Conversation found, created by: UUID-HERE
✅ [MessageService] User is conversation creator, has permission
🔍 [MessageService] Existing participants: 3
🔍 [MessageService] New users to add (after filtering): 1
📤 [MessageService] Inserting 1 new participant(s)...
✅ [MessageService] Successfully inserted participants
📢 [MessageService] Creating announcement messages...
✅ [MessageDetailsPopup] Successfully added participants
```

---

## Known Limitations

1. **Removing Participants**: Currently not implemented. Users can leave conversations themselves, but cannot be removed by others.
2. **Participant Limit**: No hard limit enforced on number of participants in a conversation.
3. **Permissions**: Only conversation creator or existing participants can add new participants.

---

## Related Files

### View Models
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

### Views
- `NaarsCars/Features/Messaging/Views/ConversationsListView.swift`
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
- `NaarsCars/UI/Components/Messaging/UserSearchView.swift`

### Services
- `NaarsCars/Core/Services/MessageService.swift`

### Models
- `NaarsCars/Core/Models/Conversation.swift`
- `NaarsCars/Core/Models/Message.swift`

---

## Summary

Both issues have been fixed:
1. ✅ Pull-to-refresh no longer shows cancellation errors
2. ✅ Adding participants to existing conversations now works properly

The fixes include proper error handling for task cancellation and fixing the callback flow in the user selection UI. Comprehensive logging has been added to help debug any future issues with the messaging system.

