# Fix for conversation_participants RLS Infinite Recursion

## Problem
The RLS policy on `conversation_participants` was causing infinite recursion because it queried the same table it was protecting, triggering the policy again in an endless loop.

## Solution
Created a `SECURITY DEFINER` function that bypasses RLS to check participation without triggering recursion.

## How to Apply

1. **Open Supabase Dashboard**
   - Go to your Supabase project
   - Navigate to SQL Editor

2. **Run the Migration**
   - Copy the contents of `010_fix_conversation_participants_rls.sql`
   - Paste into SQL Editor
   - Click "Run" or press Cmd/Ctrl + Enter

3. **Verify the Fix**
   - Test a query: `SELECT * FROM conversation_participants LIMIT 10;`
   - Should work without "infinite recursion" errors
   - Test in your iOS app - conversations should load properly

## What Changed

- **Created function**: `is_conversation_participant()` - checks participation without RLS recursion
- **Updated SELECT policy**: Uses the function to avoid recursion
- **Added policies**: INSERT, UPDATE, DELETE policies for complete RLS coverage

## Security Note

The `SECURITY DEFINER` function runs with elevated privileges but is safe because:
- It only reads data (SELECT)
- It only checks existence (EXISTS)
- It doesn't modify any data
- It's used only within RLS policies

## Rollback (if needed)

If you need to rollback, you can restore the original policy:

```sql
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_participants.conversation_id
      AND cp.user_id = auth.uid()
    )
  );
```

(Note: This will restore the infinite recursion issue)
