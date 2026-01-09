//
//  TownHallService.swift
//  NaarsCars
//
//  Service for town hall operations
//

import Foundation
import Supabase

/// Service for town hall operations
/// Handles fetching, creating, and managing town hall posts
@MainActor
final class TownHallService {
    
    // MARK: - Singleton
    
    static let shared = TownHallService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Posts
    
    /// Fetch town hall posts with pagination
    /// - Parameters:
    ///   - limit: Maximum number of posts to fetch (default: 20)
    ///   - offset: Number of posts to skip (default: 0)
    /// - Returns: Array of posts ordered by createdAt descending
    /// - Throws: AppError if fetch fails
    func fetchPosts(limit: Int = 20, offset: Int = 0) async throws -> [TownHallPost] {
        // For first page (offset = 0), check cache first
        if offset == 0, let cached = await cacheManager.getCachedTownHallPosts(), !cached.isEmpty {
            print("✅ [TownHallService] Cache hit for town hall posts. Returning \(cached.count) items.")
            return cached
        }
        
        print("🔄 [TownHallService] Cache miss for town hall posts. Fetching from network...")
        
        let response = try await supabase
            .from("town_hall_posts")
            .select()
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
        
        // Decode posts with custom date decoder
        let decoder = createDateDecoder()
        var posts: [TownHallPost] = try decoder.decode([TownHallPost].self, from: response.data)
        
        // Enrich with author profiles
        posts = await enrichPostsWithProfiles(posts)
        
        // Cache first page only
        if offset == 0 {
            await cacheManager.cacheTownHallPosts(posts)
        }
        
        print("✅ [TownHallService] Fetched \(posts.count) posts from network.")
        return posts
    }
    
    // MARK: - Create Post
    
    /// Create a new town hall post
    /// - Parameters:
    ///   - userId: The user ID creating the post
    ///   - content: Post content (max 500 characters)
    ///   - imageUrl: Optional image URL
    /// - Returns: Created post
    /// - Throws: AppError if creation fails or rate limited
    func createPost(userId: UUID, content: String, imageUrl: String? = nil) async throws -> TownHallPost {
        // Validate content length
        guard content.count <= 500 else {
            throw AppError.invalidInput("Post content must be 500 characters or less")
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidInput("Post content cannot be empty")
        }
        
        // Rate limit check: 30 seconds between posts
        let rateLimitKey = "town_hall_post_\(userId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: 30.0
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait 30 seconds before posting again")
        }
        
        // Create post (title is required by database - use first line of content or truncated content)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = generateTitle(from: trimmedContent)
        
        let newPost = TownHallPost(
            userId: userId,
            content: trimmedContent,
            imageUrl: imageUrl,
            title: title,
            type: nil // Not stored in database
        )
        
        let response = try await supabase
            .from("town_hall_posts")
            .insert(newPost)
            .select()
            .single()
            .execute()
        
        // Decode created post
        let decoder = createDateDecoder()
        var post: TownHallPost = try decoder.decode(TownHallPost.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            post.author = author
        }
        
        // Invalidate cache
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallService] Created post: \(post.id)")
        return post
    }
    
    /// Create a system post for reviews/completions
    /// Used by review system to auto-post to town hall
    /// - Parameters:
    ///   - userId: The user ID (reviewer or completer)
    ///   - content: Formatted post content
    ///   - type: Post type (review or completion)
    /// - Returns: Created post
    /// - Throws: AppError if creation fails
    func createSystemPost(userId: UUID, content: String, type: PostType) async throws -> TownHallPost {
        // Generate title from content for system posts
        let title = generateTitle(from: content)
        
        let newPost = TownHallPost(
            userId: userId,
            content: content,
            imageUrl: nil,
            title: title,
            type: nil // Not stored in database
        )
        
        let response = try await supabase
            .from("town_hall_posts")
            .insert(newPost)
            .select()
            .single()
            .execute()
        
        // Decode created post
        let decoder = createDateDecoder()
        var post: TownHallPost = try decoder.decode(TownHallPost.self, from: response.data)
        
        // Enrich with author profile
        if let author = try? await ProfileService.shared.fetchProfile(userId: userId) {
            post.author = author
        }
        
        // Invalidate cache
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallService] Created system post: \(post.id)")
        return post
    }
    
    /// Delete a post (only by the author)
    /// - Parameters:
    ///   - postId: Post ID to delete
    ///   - userId: User ID attempting to delete (must be author)
    /// - Throws: AppError if deletion fails or user is not author
    func deletePost(postId: UUID, userId: UUID) async throws {
        // Verify user is the author
        let response = try await supabase
            .from("town_hall_posts")
            .select("user_id")
            .eq("id", value: postId.uuidString)
            .single()
            .execute()
        
        struct PostUserId: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let postUserId = try JSONDecoder().decode(PostUserId.self, from: response.data)
        
        guard postUserId.userId == userId else {
            throw AppError.permissionDenied("You can only delete your own posts")
        }
        
        // Delete the post
        try await supabase
            .from("town_hall_posts")
            .delete()
            .eq("id", value: postId.uuidString)
            .execute()
        
        // Invalidate cache
        await cacheManager.invalidateTownHallPosts()
        
        print("✅ [TownHallService] Deleted post: \(postId)")
    }
    
    // MARK: - Helper Methods
    
    /// Generate a title from post content
    /// Uses first line or first 100 characters of content
    private func generateTitle(from content: String) -> String {
        // Try to get first line (up to newline)
        let lines = content.components(separatedBy: .newlines)
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !firstLine.isEmpty {
            // Use first line, truncated to 100 characters
            return String(firstLine.prefix(100))
        }
        
        // Fallback: use first 100 characters of content
        return String(content.prefix(100))
    }
    
    /// Enrich posts with author profiles
    private func enrichPostsWithProfiles(_ posts: [TownHallPost]) async -> [TownHallPost] {
        // Collect all user IDs
        var userIds = Set<UUID>()
        for post in posts {
            userIds.insert(post.userId)
        }
        
        guard !userIds.isEmpty else { return posts }
        
        // Fetch all profiles in one query
        let response = try? await supabase
            .from("profiles")
            .select()
            .in("id", values: Array(userIds).map { $0.uuidString })
            .execute()
        
        guard let data = response?.data else { return posts }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profiles = (try? decoder.decode([Profile].self, from: data)) ?? []
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        // Enrich posts
        return posts.map { post in
            var enriched = post
            enriched.author = profileMap[post.userId]
            return enriched
        }
    }
    
    /// Create date decoder for town hall posts
    private func createDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
}

