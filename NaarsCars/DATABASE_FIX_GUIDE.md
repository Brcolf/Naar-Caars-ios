# 🔧 Database Row-Level Security (RLS) Fix Guide

## Problem Summary

You're experiencing the following issues:
- ❌ Cannot claim rides or favors
- ❌ Cannot create group messages
- ❌ Getting RLS policy violation errors

**Root Cause:** Your Supabase database has Row-Level Security enabled, but the policies are either missing or incorrectly configured. This is blocking legitimate operations.

---

## Error You're Seeing

```
🔴 [MessageService] Error creating conversation: PostgrestError(
    detail: nil, 
    hint: nil, 
    code: Optional("42501"), 
    message: "new row violates row-level security policy for table \"conversations\""
)
```

**Error Code 42501** means "insufficient privilege" - the database is blocking the operation.

---

## Why This Affects Multiple Features

### 1. **Claiming Rides/Favors**
When a user claims a ride or favor:
1. The app updates the `rides` or `favors` table (sets `claimed_by` and `status`)
2. The app creates a **conversation** between the poster and claimer
3. The app adds both users as **conversation_participants**

**If any of these steps fail due to RLS policies, the entire claim operation fails.**

### 2. **Creating Group Messages**
When creating a group message:
1. The app creates a **conversation** with a title
2. The app adds all selected users as **conversation_participants**

**If either step fails, you can't create group messages.**

---

## How to Fix

### Step 1: Open Supabase SQL Editor

1. Go to your Supabase project dashboard
2. Click **SQL Editor** in the left sidebar
3. Click **New query**

### Step 2: Run the Fix Script

I've created a complete SQL script for you at:
**`DATABASE_FIX_RLS_POLICIES.sql`**

Copy the entire contents of that file and paste it into the SQL editor, then click **Run**.

### Step 3: Verify the Fix

After running the script, verify the policies are active by running these queries:

```sql
-- Check conversations policies
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'conversations';

-- Check conversation_participants policies
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'conversation_participants';
```

You should see policies like:
- ✅ "Users can create conversations" (INSERT)
- ✅ "Users can view conversations they are part of" (SELECT)
- ✅ "Users can add participants when creating conversation" (INSERT)

---

## What the Fix Does

### Conversations Table
- ✅ Allows authenticated users to **create** conversations (they must be the `created_by` user)
- ✅ Allows users to **view** conversations they're participants in
- ✅ Allows conversation creators to **update** their conversations

### Conversation Participants Table
- ✅ Allows users to **add participants** when creating a conversation
- ✅ Allows users to **view participants** in conversations they're part of
- ✅ Allows conversation creators to **remove participants**

### Rides & Favors Tables
- ✅ Allows users to **create** rides/favors
- ✅ Allows users to **update** their own rides/favors
- ✅ Allows users to **claim** rides/favors (special UPDATE policy)
- ✅ Allows all authenticated users to **view** all rides/favors

### Messages Table
- ✅ Allows users to **view messages** in conversations they're part of
- ✅ Allows users to **send messages** in conversations they're part of

---

## Testing After the Fix

### Test 1: Claim a Ride or Favor
1. Find an unclaimed ride or favor in the app
2. Tap "Claim"
3. ✅ Should succeed and create a conversation

### Test 2: Create a Group Message
1. Go to Messages tab
2. Tap the "+" button
3. Select multiple users
4. ✅ Should create a group conversation

### Test 3: Send Messages
1. Open any conversation
2. Send a message
3. ✅ Should send successfully

---

## Common Issues After Running the Fix

### Issue: Still getting errors
**Solution:** Make sure you ran the **entire** SQL script. Some policies depend on others.

### Issue: "relation does not exist"
**Solution:** Check your table names in Supabase. The script assumes tables are named:
- `conversations`
- `conversation_participants`
- `messages`
- `rides`
- `favors`

If your tables have different names, update the script accordingly.

### Issue: "permission denied for schema"
**Solution:** Make sure you're running the script as the **database owner** or a user with sufficient privileges.

---

## Security Note

These policies are designed to:
- ✅ Allow users to access only their own data
- ✅ Prevent users from viewing conversations they're not part of
- ✅ Prevent unauthorized message reading
- ✅ Allow legitimate claiming and conversation creation

The policies use `auth.uid()` to verify the authenticated user's identity, ensuring security is maintained.

---

## Need More Help?

If you continue to see errors after running the fix:

1. **Check the Supabase logs:**
   - Go to Supabase Dashboard → Database → Logs
   - Look for specific error messages

2. **Verify the auth.uid() function:**
   ```sql
   SELECT auth.uid();
   ```
   This should return your current user's UUID when authenticated.

3. **Check if RLS is enabled:**
   ```sql
   SELECT tablename, rowsecurity 
   FROM pg_tables 
   WHERE schemaname = 'public' 
   AND tablename IN ('conversations', 'rides', 'favors', 'messages');
   ```
   All should show `rowsecurity = true`.

---

## Alternative: Temporarily Disable RLS (NOT RECOMMENDED FOR PRODUCTION)

If you need to test quickly and you're in a development environment:

```sql
-- ⚠️ DEVELOPMENT ONLY - DO NOT USE IN PRODUCTION
ALTER TABLE conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants DISABLE ROW LEVEL SECURITY;
ALTER TABLE messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE rides DISABLE ROW LEVEL SECURITY;
ALTER TABLE favors DISABLE ROW LEVEL SECURITY;
```

This will allow all operations but **removes all security**. Only do this temporarily in dev environments!

To re-enable:
```sql
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE favors ENABLE ROW LEVEL SECURITY;
```

---

## Summary

1. ✅ Copy the SQL from `DATABASE_FIX_RLS_POLICIES.sql`
2. ✅ Paste into Supabase SQL Editor
3. ✅ Click "Run"
4. ✅ Test claiming a ride/favor
5. ✅ Test creating a group message

This should resolve all your RLS-related issues!
