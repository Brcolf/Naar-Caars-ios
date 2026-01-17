//
//  CacheManager.swift
//  NaarsCars
//
//  TTL-based caching utility for app data
//

import Foundation

/// Cache entry with timestamp for TTL checking
private struct CacheEntry<T: Sendable> {
    let value: T
    let timestamp: Date
    let ttl: TimeInterval
    
    nonisolated var isExpired: Bool {
        Date().timeIntervalSince(timestamp) >= ttl
    }
}

/// Actor-based cache manager with TTL support and size limits
/// Thread-safe implementation using Swift actors
/// 
/// TTL values per FR-042:
/// - Profiles: 5 minutes
/// - Rides/Favors: 2 minutes
/// - Conversations: 1 minute
actor CacheManager {
    /// Shared singleton instance
    static let shared = CacheManager()
    
    /// Maximum cache size in bytes (10 MB)
    private let maxCacheSize: Int = 10_000_000
    
    /// Current total cache size in bytes (approximate)
    private var totalCacheSize: Int = 0
    
    // Profile cache: [UUID: CacheEntry<Profile>]
    private var profileCache: [UUID: CacheEntry<Profile>] = [:]
    private var profileCacheSizes: [UUID: Int] = [:] // Track sizes
    
    // Rides cache: [CacheEntry<[Ride]>]
    private var ridesCache: CacheEntry<[Ride]>?
    private var ridesCacheSize: Int = 0
    
    // Favors cache: [CacheEntry<[Favor]>]
    private var favorsCache: CacheEntry<[Favor]>?
    private var favorsCacheSize: Int = 0
    
    // Conversations cache: [UUID: CacheEntry<Conversation>]
    private var conversationsCache: [UUID: CacheEntry<Conversation>] = [:]
    
    // Conversations list cache: [UUID: CacheEntry<[ConversationWithDetails]>] (keyed by userId)
    private var conversationsListCache: [UUID: CacheEntry<[ConversationWithDetails]>] = [:]
    
    // Messages cache: [UUID: CacheEntry<[Message]>] (keyed by conversationId)
    private var messagesCache: [UUID: CacheEntry<[Message]>] = [:]
    
    // Notifications cache: [UUID: CacheEntry<[AppNotification]>] (keyed by userId)
    private var notificationsCache: [UUID: CacheEntry<[AppNotification]>] = [:]
    
    // Town hall posts cache: CacheEntry<[TownHallPost]>
    private var townHallPostsCache: CacheEntry<[TownHallPost]>?
    
    private init() {}
    
    // MARK: - Profile Cache
    
    /// Get cached profile by ID, returns nil if not cached or expired
    func getCachedProfile(id: UUID) -> Profile? {
        guard let entry = profileCache[id], !entry.isExpired else {
            profileCache.removeValue(forKey: id)
            return nil
        }
        return entry.value
    }
    
    /// Cache a profile with 5-minute TTL
    func cacheProfile(_ profile: Profile) {
        // Estimate size
        let size = estimateProfileSize(profile)
        
        // Check if we need to evict before adding
        ensureCacheSpace(needed: size)
        
        // Remove old entry size if exists
        if let oldSize = profileCacheSizes[profile.id] {
            totalCacheSize -= oldSize
        }
        
        profileCache[profile.id] = CacheEntry(
            value: profile,
            timestamp: Date(),
            ttl: 300 // 5 minutes
        )
        profileCacheSizes[profile.id] = size
        totalCacheSize += size
        
        logCacheSize()
    }
    
    /// Invalidate a specific profile from cache
    func invalidateProfile(id: UUID) {
        if let size = profileCacheSizes[id] {
            totalCacheSize -= size
            profileCacheSizes.removeValue(forKey: id)
        }
        profileCache.removeValue(forKey: id)
    }
    
    // MARK: - Size Management Helpers
    
    /// Ensure cache has enough space by evicting if necessary
    /// - Parameter needed: Bytes needed for new entry
    private func ensureCacheSpace(needed: Int) {
        while totalCacheSize + needed > maxCacheSize {
            evictOldestProfile()
        }
    }
    
    /// Evict the oldest profile from cache (LRU)
    private func evictOldestProfile() {
        guard let oldest = profileCache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        
        if let size = profileCacheSizes[oldest.key] {
            totalCacheSize -= size
            print("🗑️ [Cache] Evicted profile \(oldest.key) to free \(size) bytes")
        }
        
        profileCache.removeValue(forKey: oldest.key)
        profileCacheSizes.removeValue(forKey: oldest.key)
    }
    
    /// Estimate size of a profile in bytes
    private func estimateProfileSize(_ profile: Profile) -> Int {
        var size = 0
        size += profile.name.utf8.count
        size += profile.email.utf8.count
        size += profile.car?.utf8.count ?? 0
        size += profile.avatarUrl?.utf8.count ?? 0
        size += 100 // Overhead for UUIDs, dates, bools
        return size
    }
    
    /// Log current cache size
    private func logCacheSize() {
        let sizeKB = totalCacheSize / 1024
        let maxKB = maxCacheSize / 1024
        if sizeKB > maxKB / 2 { // Log if over 50% capacity
            print("📊 [Cache] Size: \(sizeKB)KB / \(maxKB)KB (\(totalCacheSize * 100 / maxCacheSize)%)")
        }
    }
    
    // MARK: - Rides Cache
    
    /// Get cached rides, returns nil if not cached or expired
    func getCachedRides() -> [Ride]? {
        guard let entry = ridesCache, !entry.isExpired else {
            ridesCache = nil
            return nil
        }
        return entry.value
    }
    
    /// Cache rides with 2-minute TTL
    func cacheRides(_ rides: [Ride]) {
        ridesCache = CacheEntry(
            value: rides,
            timestamp: Date(),
            ttl: 120 // 2 minutes
        )
    }
    
    /// Invalidate rides cache
    func invalidateRides() {
        ridesCache = nil
    }
    
    // MARK: - Favors Cache
    
    /// Get cached favors, returns nil if not cached or expired
    func getCachedFavors() -> [Favor]? {
        guard let entry = favorsCache, !entry.isExpired else {
            favorsCache = nil
            return nil
        }
        return entry.value
    }
    
    /// Cache favors with 2-minute TTL
    func cacheFavors(_ favors: [Favor]) {
        favorsCache = CacheEntry(
            value: favors,
            timestamp: Date(),
            ttl: 120 // 2 minutes
        )
    }
    
    /// Invalidate favors cache
    func invalidateFavors() {
        favorsCache = nil
    }
    
    // MARK: - Conversations Cache
    
    /// Get cached conversation by ID, returns nil if not cached or expired
    func getCachedConversation(id: UUID) -> Conversation? {
        do {
            guard let entry = conversationsCache[id], !entry.isExpired else {
                conversationsCache.removeValue(forKey: id)
                print("💾 [CacheManager] Conversation cache MISS for id: \(id)")
                return nil
            }
            print("💾 [CacheManager] Conversation cache HIT for id: \(id)")
            return entry.value
        } catch {
            print("🔴 [CacheManager] Error accessing conversation cache for id \(id): \(error)")
            return nil
        }
    }
    
    /// Cache a conversation with 1-minute TTL
    func cacheConversation(_ conversation: Conversation) {
        do {
            conversationsCache[conversation.id] = CacheEntry(
                value: conversation,
                timestamp: Date(),
                ttl: 60 // 1 minute
            )
            print("💾 [CacheManager] Cached conversation: \(conversation.id)")
        } catch {
            print("🔴 [CacheManager] Error caching conversation \(conversation.id): \(error)")
        }
    }
    
    /// Invalidate a specific conversation from cache
    func invalidateConversation(id: UUID) {
        do {
            conversationsCache.removeValue(forKey: id)
            print("💾 [CacheManager] Invalidated conversation cache for id: \(id)")
        } catch {
            print("🔴 [CacheManager] Error invalidating conversation cache for id \(id): \(error)")
        }
    }
    
    /// Get cached conversations list for a user, returns nil if not cached or expired
    func getCachedConversations(userId: UUID) -> [ConversationWithDetails]? {
        do {
            guard let entry = conversationsListCache[userId], !entry.isExpired else {
                conversationsListCache.removeValue(forKey: userId)
                print("💾 [CacheManager] Conversations list cache MISS for userId: \(userId)")
                return nil
            }
            print("💾 [CacheManager] Conversations list cache HIT for userId: \(userId) (count: \(entry.value.count))")
            return entry.value
        } catch {
            print("🔴 [CacheManager] Error accessing conversations list cache for userId \(userId): \(error)")
            return nil
        }
    }
    
    /// Cache conversations list for a user with 1-minute TTL
    func cacheConversations(userId: UUID, _ conversations: [ConversationWithDetails]) {
        do {
            conversationsListCache[userId] = CacheEntry(
                value: conversations,
                timestamp: Date(),
                ttl: 60 // 1 minute
            )
            print("💾 [CacheManager] Cached \(conversations.count) conversations for userId: \(userId)")
        } catch {
            print("🔴 [CacheManager] Error caching conversations for userId \(userId): \(error)")
        }
    }
    
    /// Invalidate conversations list cache for a user
    func invalidateConversations(userId: UUID) {
        do {
            conversationsListCache.removeValue(forKey: userId)
            print("💾 [CacheManager] Invalidated conversations list cache for userId: \(userId)")
        } catch {
            print("🔴 [CacheManager] Error invalidating conversations cache for userId \(userId): \(error)")
        }
    }
    
    // MARK: - Messages Cache
    
    /// Get cached messages for a conversation, returns nil if not cached or expired
    func getCachedMessages(conversationId: UUID) -> [Message]? {
        do {
            guard let entry = messagesCache[conversationId], !entry.isExpired else {
                messagesCache.removeValue(forKey: conversationId)
                print("💾 [CacheManager] Messages cache MISS for conversationId: \(conversationId)")
                return nil
            }
            print("💾 [CacheManager] Messages cache HIT for conversationId: \(conversationId) (count: \(entry.value.count))")
            return entry.value
        } catch {
            print("🔴 [CacheManager] Error accessing messages cache for conversationId \(conversationId): \(error)")
            return nil
        }
    }
    
    /// Cache messages for a conversation with 1-minute TTL
    func cacheMessages(conversationId: UUID, _ messages: [Message]) {
        do {
            messagesCache[conversationId] = CacheEntry(
                value: messages,
                timestamp: Date(),
                ttl: 60 // 1 minute
            )
            print("💾 [CacheManager] Cached \(messages.count) messages for conversationId: \(conversationId)")
        } catch {
            print("🔴 [CacheManager] Error caching messages for conversationId \(conversationId): \(error)")
        }
    }
    
    /// Invalidate messages cache for a conversation
    func invalidateMessages(conversationId: UUID) {
        do {
            messagesCache.removeValue(forKey: conversationId)
            print("💾 [CacheManager] Invalidated messages cache for conversationId: \(conversationId)")
        } catch {
            print("🔴 [CacheManager] Error invalidating messages cache for conversationId \(conversationId): \(error)")
        }
    }
    
    // MARK: - Notifications Cache
    
    /// Get cached notifications for a user, returns nil if not cached or expired
    func getCachedNotifications(userId: UUID) -> [AppNotification]? {
        guard let entry = notificationsCache[userId], !entry.isExpired else {
            notificationsCache.removeValue(forKey: userId)
            return nil
        }
        return entry.value
    }
    
    /// Cache notifications for a user with 1-minute TTL
    func cacheNotifications(userId: UUID, _ notifications: [AppNotification]) {
        notificationsCache[userId] = CacheEntry(
            value: notifications,
            timestamp: Date(),
            ttl: 60 // 1 minute
        )
    }
    
    /// Invalidate notifications cache for a user
    func invalidateNotifications(userId: UUID) {
        notificationsCache.removeValue(forKey: userId)
    }
    
    // MARK: - Town Hall Posts Cache
    
    /// Get cached town hall posts, returns nil if not cached or expired
    func getCachedTownHallPosts() -> [TownHallPost]? {
        guard let entry = townHallPostsCache, !entry.isExpired else {
            townHallPostsCache = nil
            return nil
        }
        return entry.value
    }
    
    /// Cache town hall posts with 2-minute TTL
    func cacheTownHallPosts(_ posts: [TownHallPost]) {
        townHallPostsCache = CacheEntry(
            value: posts,
            timestamp: Date(),
            ttl: 120 // 2 minutes
        )
    }
    
    /// Invalidate town hall posts cache
    func invalidateTownHallPosts() {
        townHallPostsCache = nil
    }
    
    // MARK: - Clear All
    
    /// Clear all cached data (used on logout)
    func clearAll() {
        profileCache.removeAll()
        profileCacheSizes.removeAll()
        ridesCache = nil
        ridesCacheSize = 0
        favorsCache = nil
        favorsCacheSize = 0
        conversationsCache.removeAll()
        conversationsListCache.removeAll()
        messagesCache.removeAll()
        notificationsCache.removeAll()
        townHallPostsCache = nil
        totalCacheSize = 0
        print("🗑️ [Cache] Cleared all caches, size reset to 0")
    }
}

