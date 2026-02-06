//
//  ConversationDisplayNameCache.swift
//  NaarsCars
//
//  Local-first cache for conversation display names
//  Persists conversation titles to avoid repeated participant lookups
//

import Foundation

/// Actor-based cache for conversation display names
/// Persists to UserDefaults for instant loading on app launch
actor ConversationDisplayNameCache {
    
    // MARK: - Singleton
    
    static let shared = ConversationDisplayNameCache()
    
    // MARK: - Properties
    
    private let userDefaultsKey = "conversationDisplayNames"
    private let maxCacheSize = 1000  // Maximum number of cached names
    private var cache: [String: String] = [:]  // conversationId.uuidString : displayName
    private var accessOrder: [String] = []  // Track access order for LRU (most recent at end)
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await loadFromDisk()
        }
    }
    
    // MARK: - Public Methods
    
    /// Get cached display name for a conversation
    func getDisplayName(for conversationId: UUID) -> String? {
        do {
            let key = conversationId.uuidString
            guard let name = cache[key] else {
                AppLogger.info("messaging", "Cache MISS for conversation: \(conversationId)")
                return nil
            }
            
            // Update access order (LRU)
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
            
            AppLogger.info("messaging", "Cache HIT for conversation: \(conversationId) -> '\(name)'")
            return name
        } catch {
            AppLogger.error("messaging", "Error getting display name for \(conversationId): \(error)")
            return nil
        }
    }
    
    /// Set display name for a conversation and persist
    func setDisplayName(_ name: String, for conversationId: UUID) {
        do {
            let key = conversationId.uuidString
            
            // Update cache
            cache[key] = name
            
            // Update access order (move to end = most recent)
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
            
            // Enforce size limit using LRU eviction
            while cache.count > maxCacheSize {
                if let oldestKey = accessOrder.first {
                    cache.removeValue(forKey: oldestKey)
                    accessOrder.removeFirst()
                    AppLogger.info("messaging", "Evicted oldest cache entry: \(oldestKey)")
                } else {
                    break
                }
            }
            
            saveToDisk()
            AppLogger.info("messaging", "Cached name for conversation \(conversationId): '\(name)' (cache size: \(cache.count))")
        } catch {
            AppLogger.error("messaging", "Error setting display name for \(conversationId): \(error)")
        }
    }
    
    /// Batch set display names
    func setDisplayNames(_ names: [UUID: String]) {
        do {
            for (conversationId, name) in names {
                let key = conversationId.uuidString
                cache[key] = name
                
                // Update access order
                if let index = accessOrder.firstIndex(of: key) {
                    accessOrder.remove(at: index)
                }
                accessOrder.append(key)
            }
            
            // Enforce size limit
            while cache.count > maxCacheSize {
                if let oldestKey = accessOrder.first {
                    cache.removeValue(forKey: oldestKey)
                    accessOrder.removeFirst()
                    AppLogger.info("messaging", "Evicted oldest cache entry: \(oldestKey)")
                } else {
                    break
                }
            }
            
            saveToDisk()
            AppLogger.info("messaging", "Cached \(names.count) conversation names (cache size: \(cache.count))")
        } catch {
            AppLogger.error("messaging", "Error batch setting display names: \(error)")
        }
    }
    
    /// Get all conversation IDs that have cached names
    func getCachedConversationIds() -> Set<UUID> {
        return Set(cache.keys.compactMap { UUID(uuidString: $0) })
    }
    
    /// Remove a cached name (e.g., when conversation is deleted)
    func removeDisplayName(for conversationId: UUID) {
        let key = conversationId.uuidString
        cache.removeValue(forKey: key)
        
        // Remove from access order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        
        saveToDisk()
        AppLogger.info("messaging", "Removed cached name for conversation \(conversationId)")
    }
    
    /// Clear all cached names
    func clearAll() {
        cache.removeAll()
        accessOrder.removeAll()
        saveToDisk()
        AppLogger.info("messaging", "Cleared all cached names")
    }
    
    // MARK: - Private Methods
    
    private func loadFromDisk() async {
        // Load cache dictionary
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            AppLogger.info("messaging", "No cached names found on disk")
            return
        }
        
        cache = decoded
        
        // Load access order
        if let orderData = UserDefaults.standard.data(forKey: userDefaultsKey + "_order"),
           let decodedOrder = try? JSONDecoder().decode([String].self, from: orderData) {
            accessOrder = decodedOrder
        } else {
            // No saved order - initialize with current keys
            accessOrder = Array(cache.keys)
        }
        
        AppLogger.info("messaging", "Loaded \(cache.count) cached names from disk")
    }
    
    private func saveToDisk() {
        // Save cache dictionary
        guard let data = try? JSONEncoder().encode(cache) else {
            AppLogger.error("messaging", "Failed to encode cache")
            return
        }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        
        // Save access order
        if let orderData = try? JSONEncoder().encode(accessOrder) {
            UserDefaults.standard.set(orderData, forKey: userDefaultsKey + "_order")
        }
    }
}
// MARK: - Display Name Computation

extension ConversationDisplayNameCache {
    
    /// Compute display name for a conversation
    /// Priority: 1) Group title, 2) Participant names, 3) nil (will show "Loading...")
    static func computeDisplayName(
        conversation: Conversation,
        otherParticipants: [Profile],
        currentUserId: UUID?
    ) -> String? {
        // Priority 1: Group title (if set)
        if let title = conversation.title, !title.isEmpty {
            return title
        }
        
        // Priority 2: Participant names (comma-separated)
        if !otherParticipants.isEmpty {
            let names = otherParticipants.map { $0.name }
            return ListFormatter.localizedString(byJoining: names)
        }
        
        // No data available - return nil so UI shows "Loading..."
        return nil
    }
}

