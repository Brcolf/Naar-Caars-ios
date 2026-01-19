# Quick Test Guide - Multi-Select Fixes

## 🚀 Quick 2-Minute Test

### Test 1: Basic Multi-Select (30 seconds)
1. Open app → Messages tab
2. Tap "New Message" button (pencil icon)
3. **Verify:** Keyboard appears immediately (auto-focus ✅)
4. Type a user's name
5. Tap the user
6. **Verify:** Search clears automatically ✅
7. **Verify:** User appears as chip at top ✅
8. Type another user's name
9. Tap that user
10. **Verify:** Both users now in chips ✅
11. Tap "Done"
12. **Verify:** Navigates to conversation ✅

**Expected:** All 6 checkmarks pass

---

### Test 2: Existing Conversation (30 seconds)
1. Note the user from Test 1
2. Go back to conversations list
3. Tap "New Message" again
4. Search and select the SAME user
5. Tap "Done"
6. **Verify:** Opens EXISTING conversation (not new) ✅
7. **Verify:** No duplicate conversation created ✅

**Expected:** Navigates to existing conversation

---

### Test 3: Add Participants (30 seconds)
1. Open any conversation
2. Tap info button (top right)
3. Tap "Add Participants"
4. **Verify:** Keyboard appears immediately ✅
5. Search and select a user
6. **Verify:** Search clears ✅
7. Select another user
8. Tap "Done"
9. **Verify:** Both users added ✅
10. **Verify:** Announcement messages appear ✅

**Expected:** All checkmarks pass

---

### Test 4: Cancel (15 seconds)
1. Tap "New Message"
2. Select 2 users
3. Tap "Cancel"
4. **Verify:** Returns to conversations list ✅
5. **Verify:** No conversation created ✅
6. Tap "New Message" again
7. **Verify:** No users pre-selected ✅

**Expected:** Clean state after cancel

---

## ✅ Success Criteria

All tests should pass with these behaviors:

| Feature | Expected Behavior |
|---------|-------------------|
| Auto-focus | Keyboard appears immediately |
| Auto-clear | Search clears after each selection |
| Multi-select | Multiple users shown as chips |
| Navigation | Opens conversation after "Done" |
| Existing | Navigates to existing, not duplicate |
| Add participants | All selected users added |
| Cancel | Clean state, no conversation created |

---

## 🐛 If Something Fails

### Issue: Keyboard doesn't appear
**Fix:** Clean build (Cmd+Shift+K) and rebuild

### Issue: Search doesn't clear
**Fix:** Verify you're on latest code, check `UserSearchView.swift` lines 97-105

### Issue: "Done" doesn't navigate
**Fix:** Check console for errors, verify `ConversationsListView.swift` lines 115-132

### Issue: Duplicate conversations created
**Fix:** Check `findExistingGroupConversation` method is present

---

## 📊 Console Output to Expect

When creating/navigating to conversation, you should see:

```
🔍 [ConversationsListView] Looking for existing conversation with 1 user(s)
📱 [ConversationsListView] Creating/finding direct message
✅ [ConversationsListView] Navigating to conversation: <UUID>
```

Or for groups:

```
🔍 [ConversationsListView] Looking for existing conversation with 2 user(s)
👥 [ConversationsListView] Looking for group with participants: 3 total
✅ [ConversationsListView] Found existing group conversation: <UUID>
✅ [ConversationsListView] Navigating to conversation: <UUID>
```

---

## 🎯 Bottom Line

**All 4 tests should complete in ~2 minutes.**

If all pass → ✅ **Everything works!**

If any fail → Check console logs and refer to `MULTI-SELECT-IMPROVEMENTS.md` for details.

