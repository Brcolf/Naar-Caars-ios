//
//  PaginatedResponse.swift
//  NaarsCars
//
//  Paginated response types for various data models
//

import Foundation

/// Paginated response for messages
struct PaginatedMessages {
    let messages: [Message]
    let hasMore: Bool
    let endCursor: UUID?
}

/// Paginated response for conversations
struct PaginatedConversations {
    let conversations: [ConversationWithDetails]
    let hasMore: Bool
    let endCursor: UUID?
}

/// Paginated response for rides
struct PaginatedRides {
    let rides: [Ride]
    let hasMore: Bool
    let endCursor: UUID?
}

/// Paginated response for favors
struct PaginatedFavors {
    let favors: [Favor]
    let hasMore: Bool
    let endCursor: UUID?
}

/// Paginated response for town hall posts
struct PaginatedTownHallPosts {
    let posts: [TownHallPost]
    let hasMore: Bool
    let offset: Int
}

/// Paginated response for notifications
struct PaginatedNotifications {
    let notifications: [AppNotification]
    let hasMore: Bool
    let offset: Int
}
