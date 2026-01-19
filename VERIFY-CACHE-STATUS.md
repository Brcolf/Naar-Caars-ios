# Quick Cache Verification Checklist

## ✅ How to Verify Your Caching Changes

### Test 1: Console Logs (Most Important)
Run the app and watch the Xcode console:

1. **Open Messages Tab**
   ```
   Expected first time:
   🔄 [MessageService] Cache miss for conversations. Fetching from network...
   ✅ [MessageService] Fetched X conversations from network.
   ```

2. **Close and Reopen Messages (within 60s)**
   ```
   Expected:
   ✅ [MessageService] Cache hit for conversations. Returning X items.
   ```

3. **Open a Conversation**
   ```
   Expected first time:
   🔄 [MessageService] Cache miss for messages. Fetching from network...
   ✅ [MessageService] Fetched X messages from network.
   ```

4. **Back and Reopen Conversation (within 60s)**
   ```
   Expected:
   ✅ [MessageService] Cache hit for messages. Returning X items.
   ```

---

### Test 2: Speed Test

**Without Cache (First Load):**
- Conversations list loads in ~500ms (shows loading indicator)
- Messages load in ~200ms (shows loading indicator)

**With Cache (Subsequent Load < 60s):**
- Conversations list loads instantly (~0ms, no loading indicator)
- Messages load instantly (~0ms, no loading indicator)

**Try This:**
1. Open Messages → time it (should be slow first time)
2. Close and reopen → time it (should be instant)
3. Wait 61 seconds
4. Reopen → time it (should be slow again - cache expired)

---

### Test 3: Cache Invalidation

**After Sending Message:**
1. Send a message
2. Back to conversations list
3. Open the same conversation again
   ```
   Expected:
   🔄 [MessageService] Cache miss for messages. Fetching from network...
   (Cache was invalidated to show your new message)
   ```

**After Pull-to-Refresh:**
1. Pull down on conversations list
2. Let it reload
3. Check console
   ```
   Expected:
   🔄 [MessageService] Cache miss for conversations. Fetching from network...
   (Cache was manually invalidated)
   ```

---

### Test 4: Real-time Updates

**With Another User:**
1. Have another user send you a message
2. You should see the new message appear immediately
3. Check console
   ```
   Expected:
   🔄 [MessageService] Cache miss for messages. Fetching from network...
   (Real-time triggered a fresh fetch, bypassing cache)
   ```

---

## 🔍 Code Verification Points

### Check These Files Exist and Have Content:

✅ **CacheManager.swift** (Lines 181-204)
```swift
// MARK: - Messages Cache

/// Get cached messages for a conversation, returns nil if not cached or expired
func getCachedMessages(conversationId: UUID) -> [Message]? {
    guard let entry = messagesCache[conversationId], !entry.isExpired else {
        messagesCache.removeValue(forKey: conversationId)
        return nil
    }
    return entry.value
}

/// Cache messages for a conversation with 1-minute TTL
func cacheMessages(conversationId: UUID, _ messages: [Message]) {
    messagesCache[conversationId] = CacheEntry(
        value: messages,
        timestamp: Date(),
        ttl: 60 // 1 minute
    )
}
```

✅ **MessageService.swift** (Line 600-602)
```swift
// Check cache first
if let cached = await cacheManager.getCachedMessages(conversationId: conversationId), !cached.isEmpty {
    print("✅ [MessageService] Cache hit for messages. Returning \(cached.count) items.")
    return cached
}
```

✅ **MessageService.swift** (Line 687)
```swift
// Cache results (only cache if this is the initial load, not pagination)
if beforeMessageId == nil {
    await cacheManager.cacheMessages(conversationId: conversationId, messages)
}
```

✅ **ConversationDetailViewModel.swift** (Lines 169-191)
```swift
private func setupRealtimeSubscription() {
    Task {
        await realtimeManager.subscribe(
            channelName: "messages:\(conversationId.uuidString)",
            table: "messages",
            onInsert: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadMessages()  // Bypasses cache
                }
            }
        )
    }
}
```

---

## ✅ Success Indicators

Your caching is working correctly if you see:

1. ✅ **Cache hit logs** when reopening conversations/messages within 60s
2. ✅ **Instant loading** (no spinner) on cached data
3. ✅ **Cache miss logs** after sending messages (invalidation working)
4. ✅ **Real-time updates** still work (new messages appear immediately)
5. ✅ **Fresh data** after waiting > 60s (TTL working)

---

## ❌ Red Flags (Cache NOT Working)

If you see these, your changes may not have stuck:

1. ❌ **Always "Cache miss"** even when reopening quickly
2. ❌ **Always showing loading spinners** (cache never used)
3. ❌ **No cache logs in console** (caching disabled)
4. ❌ **Stale data after sending** (invalidation not working)
5. ❌ **Real-time not working** (over-aggressive caching)

---

## 🔧 Quick Fix Commands

### If Changes Didn't Stick:

1. **Clean Build Folder**
   ```
   Cmd+Shift+K (Clean Build Folder)
   Cmd+B (Build)
   ```

2. **Delete Derived Data**
   ```
   Xcode → Preferences → Locations → Derived Data → Delete
   ```

3. **Verify Files**
   ```bash
   # Check CacheManager exists
   ls -la NaarsCars/Core/Utilities/CacheManager.swift
   
   # Check for cache references in MessageService
   grep -n "cacheManager" NaarsCars/Core/Services/MessageService.swift
   ```

---

## 📊 Expected Behavior Summary

| Scenario | Expected Result | Cache Status |
|----------|----------------|--------------|
| First load of messages | ~200ms, shows spinner | Cache Miss |
| Reopen same conversation (< 60s) | ~0ms, instant | Cache Hit ✅ |
| Reopen after 61s | ~200ms, shows spinner | Cache Expired |
| After sending message | ~200ms, shows spinner | Cache Invalidated |
| Real-time message arrives | Instant, no spinner | Bypasses Cache |
| Pull-to-refresh | ~500ms, shows spinner | Cache Invalidated |

---

## 🎯 Bottom Line

**Your caching is working if:**
- Console shows cache hit/miss logs
- Reopening conversations is instant (< 60s)
- Data refreshes after sending messages
- Real-time updates still work

**Run the tests above and check the console!** 📱

