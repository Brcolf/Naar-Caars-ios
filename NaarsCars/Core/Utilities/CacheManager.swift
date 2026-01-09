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

/// Actor-based cache manager with TTL support
/// Thread-safe implementation using Swift actors
/// 
/// TTL values per FR-042:
/// - Profiles: 5 minutes
/// - Rides/Favors: 2 minutes
/// - Conversations: 1 minute
actor CacheManager {
    /// Shared singleton instance
    static let shared = CacheManager()
    
    // Profile cache: [UUID: CacheEntry<Profile>]
    private var profileCache: [UUID: CacheEntry<Profile>] = [:]
    
    // Rides cache: [CacheEntry<[Ride]>]
    private var ridesCache: CacheEntry<[Ride]>?
    
    // Favors cache: [CacheEntry<[Favor]>]
    private var favorsCache: CacheEntry<[Favor]>?
    
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
        profileCache[profile.id] = CacheEntry(
            value: profile,
            timestamp: Date(),
            ttl: 300 // 5 minutes
        )
    }
    
    /// Invalidate a specific profile from cache
    func invalidateProfile(id: UUID) {
        profileCache.removeValue(forKey: id)
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
        guard let entry = conversationsCache[id], !entry.isExpired else {
            conversationsCache.removeValue(forKey: id)
            return nil
        }
        return entry.value
    }
    
    /// Cache a conversation with 1-minute TTL
    func cacheConversation(_ conversation: Conversation) {
        conversationsCache[conversation.id] = CacheEntry(
            value: conversation,
            timestamp: Date(),
            ttl: 60 // 1 minute
        )
    }
    
    /// Invalidate a specific conversation from cache
    func invalidateConversation(id: UUID) {
        conversationsCache.removeValue(forKey: id)
    }
    
    /// Get cached conversations list for a user, returns nil if not cached or expired
    func getCachedConversations(userId: UUID) -> [ConversationWithDetails]? {
        guard let entry = conversationsListCache[userId], !entry.isExpired else {
            conversationsListCache.removeValue(forKey: userId)
            return nil
        }
        return entry.value
    }
    
    /// Cache conversations list for a user with 1-minute TTL
    func cacheConversations(userId: UUID, _ conversations: [ConversationWithDetails]) {
        conversationsListCache[userId] = CacheEntry(
            value: conversations,
            timestamp: Date(),
            ttl: 60 // 1 minute
        )
    }
    
    /// Invalidate conversations list cache for a user
    func invalidateConversations(userId: UUID) {
        conversationsListCache.removeValue(forKey: userId)
    }
    
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
    
    /// Invalidate messages cache for a conversation
    func invalidateMessages(conversationId: UUID) {
        messagesCache.removeValue(forKey: conversationId)
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
        ridesCache = nil
        favorsCache = nil
        conversationsCache.removeAll()
        conversationsListCache.removeAll()
        messagesCache.removeAll()
        notificationsCache.removeAll()
        townHallPostsCache = nil
    }
}

