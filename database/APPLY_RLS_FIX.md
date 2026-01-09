# Complete RLS Fix Guide

## Problem
The RLS policies on `conversation_participants` and `conversations` are causing infinite recursion errors when querying conversations.

## Solution
We've created four SQL migrations that need to be applied in order:

1. **010_fix_conversation_participants_rls.sql** - Fixes the `conversation_participants` RLS policy
2. **012_fix_conversations_rls.sql** - Updates the `conversations` SELECT policy to use the helper function
3. **013_fix_all_conversation_rls.sql** - **CRITICAL**: Adds missing INSERT/UPDATE policies and fixes `messages` policies
4. **011_verify_rls_fix.sql** - Verification script (optional, for testing)

## Steps to Apply

### Step 1: Open Supabase SQL Editor
1. Go to https://supabase.com/dashboard
2. Select your project
3. Click "SQL Editor" in the left sidebar

### Step 2: Run Migration 1 (Required)
Copy and paste the entire contents of `010_fix_conversation_participants_rls.sql` and run it.

**What it does:**
- Creates `is_conversation_participant()` SECURITY DEFINER function
- Fixes the SELECT policy on `conversation_participants`
- Adds INSERT, UPDATE, DELETE policies

### Step 3: Run Migration 2 (Required)
Copy and paste the entire contents of `012_fix_conversations_rls.sql` and run it.

**What it does:**
- Updates the `conversations` SELECT policy to use the helper function
- Ensures consistency and avoids any recursion issues

### Step 4: Run Migration 3 (CRITICAL - Required)
Copy and paste the entire contents of `013_fix_all_conversation_rls.sql` and run it.

**What it does:**
- **Adds missing INSERT policy on `conversations`** - This is why conversation creation was failing!
- Adds UPDATE policy on `conversations`
- Fixes `messages` policies to use the helper function (prevents recursion)
- Ensures `conversation_participants` INSERT policy is correct

**This is the critical fix** - without the INSERT policy, you cannot create conversations!

### Step 5: Verify (Optional)
Run `011_verify_rls_fix.sql` to verify:
- The function exists
- All policies are in place
- Queries work without recursion

### Step 6: Test in Your App
1. Restart your iOS app
2. Sign in
3. Try to load conversations
4. The recursion errors should be gone

## Troubleshooting

### If you still see recursion errors:

1. **Check if the function exists:**
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'is_conversation_participant';
   ```
   Should return one row.

2. **Check if policies exist:**
   ```sql
   SELECT policyname FROM pg_policies WHERE tablename = 'conversation_participants';
   ```
   Should show: `participants_select_own_convos`, `participants_insert_creator_or_self`, `participants_update_own`, `participants_delete_own`

3. **Clear Supabase cache:**
   - Sometimes Supabase caches policies
   - Wait a few minutes and try again
   - Or restart your Supabase project

4. **Check for conflicting policies:**
   ```sql
   SELECT * FROM pg_policies WHERE tablename IN ('conversations', 'conversation_participants');
   ```
   Make sure there are no duplicate or conflicting policies.

## What Changed in the Code

The `MessageService.swift` has been updated to:
- Query `conversations` directly (no join with `conversation_participants`)
- Rely on RLS policies to filter conversations automatically
- This avoids triggering the recursion during query execution

## Security Note

The `SECURITY DEFINER` function is safe because:
- It only reads data (SELECT)
- It only checks existence (EXISTS)
- It doesn't modify any data
- It's used only within RLS policies

