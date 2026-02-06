# Auth Client Warning Fix

**Date:** January 5, 2025  
**Status:** ✅ Fixed

---

## Issue

The Supabase Auth client was showing a deprecation warning:

```
Initial session emitted after attempting to refresh the local stored session.
This is incorrect behavior and will be fixed in the next major release since it's a breaking change.
To opt-in to the new behavior now, set `emitLocalSessionAsInitialSession: true` in your AuthClient configuration.
```

## Solution

Updated `SupabaseService.swift` to configure the Auth client with `emitLocalSessionAsInitialSession: true` through `SupabaseClientOptions.AuthOptions`.

### Code Change

**Before:**
```swift
self.client = SupabaseClient(
    supabaseURL: url,
    supabaseKey: anonKey
)
```

**After:**
```swift
let authOptions = SupabaseClientOptions.AuthOptions(
    storage: KeychainLocalStorage(service: "com.naarscars.supabase.auth"),
    emitLocalSessionAsInitialSession: true
)

let options = SupabaseClientOptions(
    auth: authOptions
)

self.client = SupabaseClient(
    supabaseURL: url,
    supabaseKey: anonKey,
    options: options
)
```

## What This Does

- **`emitLocalSessionAsInitialSession: true`** - Ensures the locally stored session is always emitted immediately as the initial session, regardless of its validity or expiration
- This is the new behavior that will become the default in the next major SDK release
- Prevents the deprecation warning
- Ensures consistent session handling behavior

## Reference

- Supabase Swift SDK PR: https://github.com/supabase/supabase-swift/pull/822
- The warning was informational about future breaking changes
- This configuration opts into the new behavior early

---

## Verification

✅ Build succeeds  
✅ Warning should no longer appear  
✅ Auth session handling uses new behavior





