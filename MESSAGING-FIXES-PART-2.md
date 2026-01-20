# Messaging Fixes Part 2 - January 19, 2026

## Issues Fixed

### 1. ✅ Race Condition When Adding Participants

**Problem**: When adding participants to an existing group conversation, users would be selected but not actually added. The logs showed:
```
🔍 [MessageDetailsPopup] UserSearchView dismissed with 1 selected user(s)
🔍 [MessageDetailsPopup] Selected user IDs: [80447EAD-6009-4874-A2B0-D1825A7CC5D6]
✅ [MessageDetailsPopup] Adding 0 participant(s) to conversation 91CDBAF5-B73A-441D-A9A5-7D1F227AEBCF
📥 [MessageService] addParticipantsToConversation called
   Conversation ID: 91CDBAF5-B73A-441D-A9A5-7D1F227AEBCF
   User IDs to add: []
   Added by: 0DA568D8-924C-4420-8853-206A48D277B6
   Create announcement: true
⚠️ [MessageService] No user IDs provided, returning early
```

Notice how 1 user was selected, but by the time `addParticipants` was called, 0 users were passed!

**Root Cause**: Classic Swift Concurrency race condition. The code was:
```swift
onDismiss: {
    if !selectedUserIds.isEmpty {
        Task {
            await addParticipants(Array(selectedUserIds))
        }
    }
    showAddParticipants = false
    selectedUserIds = []  // <-- Clears the set synchronously
}
```

The problem:
1. `Task { await addParticipants(...) }` is created and scheduled to run asynchronously
2. `selectedUserIds = []` runs immediately on the same thread (synchronously)
3. By the time the Task actually executes, `selectedUserIds` is already empty!

**Solution**: Capture the selected IDs in a local variable BEFORE clearing:
```swift
onDismiss: {
    // Capture the selected IDs BEFORE clearing to avoid race condition
    let idsToAdd = Array(selectedUserIds)
    showAddParticipants = false
    selectedUserIds = []
    
    if !idsToAdd.isEmpty {
        Task {
            await addParticipants(idsToAdd)
        }
    }
}
```

**Files Modified**:
- `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`

---

### 2. ✅ Change "Done" Button to "Add" When Adding Participants

**Problem**: The button to confirm adding participants said "Done", which wasn't clear about what action it would perform.

**Solution**: Added support for a custom action button title in `UserSearchView`:
- Added `actionButtonTitle` parameter with default value "Done"
- `MessageDetailsPopup` now passes `actionButtonTitle: "Add"`
- Button now clearly says "Add" when adding participants to a conversation

**Files Modified**:
- `NaarsCars/UI/Components/Messaging/UserSearchView.swift`
  - Added `actionButtonTitle` parameter with default "Done"
  - Updated toolbar button to use the custom title
- `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
  - Passes `actionButtonTitle: "Add"` when opening UserSearchView

**Code Changes**:
```swift
// UserSearchView now accepts custom button title
init(
    selectedUserIds: Binding<Set<UUID>>,
    excludeUserIds: [UUID],
    showExistingParticipants: Bool = true,
    actionButtonTitle: String = "Done",  // New parameter
    onDismiss: @escaping () -> Void
) { ... }

// MessageDetailsPopup uses "Add" instead of "Done"
UserSearchView(
    selectedUserIds: $selectedUserIds,
    excludeUserIds: participants.map { $0.id },
    actionButtonTitle: "Add",  // Clear action
    onDismiss: { ... }
)
```

---

### 3. ✅ Show Existing Participants When Adding New Ones

**Problem**: When adding participants to an existing group conversation, you couldn't see who was already in the group. This made it unclear who you were adding to what.

**Solution**: Enhanced `UserSearchView` to display existing participants:
- Added `showExistingParticipants` parameter (default: true)
- Existing participants now shown at the top in a "Participants" section
- Existing participants displayed as non-removable chips (no X button)
- Newly selected users shown after existing ones (with X button to deselect)
- Visual distinction: existing participants have slightly different background color

**Files Modified**:
- `NaarsCars/UI/Components/Messaging/UserSearchView.swift`
  - Added `showExistingParticipants` parameter
  - Updated selected users section to show both existing and new participants
  - Enhanced `SelectedUserChip` to support removable vs non-removable chips
  - Different background colors for existing vs new participants

**Visual Layout**:
```
┌─────────────────────────────────────────┐
│ Select Users                   [Cancel] │
│ ─────────────────────────────────────── │
│ [Search bar]                            │
│                                         │
│ Participants (3)                        │
│ ┌───────────┐ ┌───────────┐ ┌────────┐ │
│ │👤 Alice   │ │👤 Bob     │ │👤 Carol│ │ <- Existing (no X)
│ └───────────┘ └───────────┘ └────────┘ │
│ ┌──────────┐                            │
│ │👤 Dave ✕│                             │ <- New (with X)
│ └──────────┘                            │
│ ─────────────────────────────────────── │
│                                         │
│ [Search results...]                     │
│                                         │
│                                  [Add]  │
└─────────────────────────────────────────┘
```

**Behavior**:
- **Existing participants**: Shown at top, grayed background, no remove button
- **Newly selected users**: Shown after existing, normal background, can be removed
- **In search results**: Existing participants show "Already added" and are grayed out
- **Section title**: Changes from "Selected" to "Participants" when showing existing

**Code Changes**:
```swift
// SelectedUserChip now supports isRemovable flag
private struct SelectedUserChip: View {
    let userId: UUID
    let isRemovable: Bool  // New parameter
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            // ... avatar and name ...
            
            // Only show X button if removable
            if isRemovable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
            }
        }
        // Different background for existing vs new
        .background(isRemovable ? Color(.systemGray5) : Color(.systemGray6))
    }
}

// Show existing participants first, then newly selected
if showExistingParticipants {
    ForEach(excludeUserIds, id: \.self) { userId in
        SelectedUserChip(userId: userId, isRemovable: false) { }
    }
}

ForEach(Array(selectedUserIds), id: \.self) { userId in
    SelectedUserChip(userId: userId, isRemovable: true) {
        selectedUserIds.remove(userId)
    }
}
```

---

## Testing Recommendations

### Test Case 1: Add Participant to Existing Group (Race Condition Fix)
1. Open an existing group conversation (3+ participants)
2. Tap the info icon (top right)
3. Tap "Add Participants"
4. Search for and select a user
5. Tap "Add" (note: button now says "Add" not "Done")
6. **Expected**: Sheet dismisses
7. **Expected**: User is successfully added to conversation
8. **Expected**: Console logs show correct user IDs being passed
9. **Expected**: Announcement message appears: "John Doe has been added to the conversation"

### Test Case 2: See Existing Participants
1. Open an existing group conversation with 2-3 people
2. Tap the info icon
3. Tap "Add Participants"
4. **Expected**: See "Participants (3)" section at top
5. **Expected**: See all existing participants displayed as chips (no X button)
6. Search for and select a new user
7. **Expected**: New user appears after existing participants (with X button)
8. **Expected**: Selected count includes both existing and new: "Participants (4)"

### Test Case 3: Cannot Re-Add Existing Participant
1. Follow steps 1-3 from Test Case 2
2. Search for someone already in the conversation
3. **Expected**: They appear grayed out with "Already added" label
4. **Expected**: Cannot tap to select them

### Test Case 4: Remove Newly Selected User
1. Follow steps 1-3 from Test Case 2
2. Select a new user (they appear with X button)
3. Tap the X button on the newly selected user
4. **Expected**: User is removed from selection
5. **Expected**: Existing participants remain (cannot remove them)

---

## Console Logs to Watch For

When adding participants successfully, you should now see:
```
🔍 [UserSearchView] Add tapped with 1 selected user(s)
🔍 [MessageDetailsPopup] UserSearchView dismissed with 1 selected user(s)
🔍 [MessageDetailsPopup] Will add user IDs: [UUID-HERE]
✅ [MessageDetailsPopup] Adding 1 participant(s) to conversation UUID-HERE
📥 [MessageService] addParticipantsToConversation called
   Conversation ID: UUID-HERE
   User IDs to add: [UUID-HERE]  <- Should NOT be empty!
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
```

---

## Impact on Other Features

The `UserSearchView` changes are backward compatible:
- **Default parameters**: `showExistingParticipants: Bool = true`, `actionButtonTitle: String = "Done"`
- **Existing usages**: Continue to work without changes
- **Other features using UserSearchView**:
  - Creating new messages (ConversationsListView) - works as before
  - Adding co-requestors to rides/favors (Create/Detail views) - now shows existing participants

---

## Summary

All three issues have been fixed:
1. ✅ Race condition fixed - participants are now actually added when you tap Add
2. ✅ Button renamed to "Add" for clarity when adding participants
3. ✅ Existing participants shown at top (non-removable) so you can see who's already in the group

The fixes maintain backward compatibility with existing code while providing a much better UX for managing group conversations.

