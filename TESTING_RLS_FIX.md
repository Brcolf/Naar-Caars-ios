# Testing RLS Fix for Messaging

## Step 1: SQL Test (Optional)
Run `database/022_test_messaging_rls.sql` in Supabase SQL Editor to verify policies exist and basic queries work.

## Step 2: iOS App Test

### Test 1: Load Conversations
1. Open the app and sign in
2. Navigate to Messages tab
3. **Expected**: Conversations should load without "infinite recursion" errors
4. **Check logs**: Should see `✅ [MessageService] Fetched X conversations from network.`

### Test 2: Create Direct Message
1. Go to a user's profile
2. Tap "Send Message" button
3. **Expected**: Conversation should be created successfully
4. **Check logs**: Should see `✅ [MessageService] Created conversation with participants`
5. **Expected**: Should navigate to conversation detail view

### Test 3: Send a Message
1. In a conversation, type a message and send
2. **Expected**: Message should send successfully
3. **Check logs**: Should see `✅ [MessageService] Sent message: <id>`

### Test 4: Check for Errors
Look for these error patterns in logs:
- ❌ "infinite recursion" - Should NOT appear
- ❌ "RLS policy recursion detected" - Should NOT appear
- ✅ "Created conversation" - Should appear
- ✅ "Fetched X conversations" - Should appear

## Step 3: Verify RLS Policies

### In Supabase SQL Editor:
```sql
-- Check policies exist
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
ORDER BY tablename, policyname;

-- Should show:
-- conversations: conversations_insert_approved, conversations_select_participant, conversations_update_creator
-- conversation_participants: participants_delete_own, participants_insert_creator_or_self, participants_select_own_convos, participants_update_own
-- messages: messages_insert_participant, messages_select_participant
```

## Success Criteria

✅ Conversations load without recursion errors  
✅ Direct messages can be created  
✅ Messages can be sent  
✅ No "infinite recursion" errors in logs  
✅ All policies exist in database  

## If Tests Fail

1. **Check RLS policies**: Run the verification query above
2. **Check function exists**: `SELECT proname FROM pg_proc WHERE proname = 'is_conversation_participant';` (should return nothing - we removed the function)
3. **Re-run fix**: Run `021_complete_messaging_rls_fix.sql` again
4. **Check user approval**: User must be approved to create conversations


