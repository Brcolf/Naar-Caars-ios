//
//  TownHallPostCard.swift
//  NaarsCars
//
//  Redesigned post-focused card component for Town Hall
//

import SwiftUI

/// Post-focused card component for Town Hall feed
struct TownHallPostCard: View {
    let post: TownHallPost
    let currentUserId: UUID?
    let onDelete: (() -> Void)?
    let onComment: ((UUID) -> Void)? // Post ID
    let onVote: ((UUID, VoteType?) -> Void)? // Post ID, Vote type (nil = remove vote)
    let isHighlighted: Bool
    
    @State private var showDeleteAlert = false
    @State private var showComments = false
    
    init(
        post: TownHallPost,
        currentUserId: UUID?,
        onDelete: (() -> Void)? = nil,
        onComment: ((UUID) -> Void)? = nil,
        onVote: ((UUID, VoteType?) -> Void)? = nil,
        isHighlighted: Bool = false
    ) {
        self.post = post
        self.currentUserId = currentUserId
        self.onDelete = onDelete
        self.onComment = onComment
        self.onVote = onVote
        self.isHighlighted = isHighlighted
    }
    
    var isOwnPost: Bool {
        currentUserId == post.userId
    }
    
    // Extract title from content (or use provided title)
    private var displayTitle: String {
        if let title = post.title, !title.isEmpty {
            return title
        }
        return PostTitleExtractor.extractTitle(from: post.content)
    }
    
    private var isAnnouncement: Bool {
        post.type == .announcement
    }

    private var isReview: Bool {
        post.type == .review
    }

    // Show stars if post is related to a review
    private var starRating: Int? {
        guard isReview, let review = post.review else { return nil }
        return review.rating
    }

    /// "Reviewed Jane Doe for a ride"
    private var reviewSubtitle: String? {
        guard isReview, let review = post.review else { return nil }
        var text = "Reviewed"
        if let name = review.fulfillerName {
            text += " \(name)"
        }
        if review.rideId != nil {
            text += " for a ride"
        } else if review.favorId != nil {
            text += " for a favor"
        }
        return text
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row with star rating (if review-related)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayTitle)
                    .font(.naarsTitle3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer()

                // Visual star rating for review posts
                if let rating = starRating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(star <= rating ? .yellow : .secondary.opacity(0.3))
                        }
                    }
                }
            }

            // Type badge row
            if isAnnouncement {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.caption2)
                    Text("Announcement")
                        .font(.naarsCaption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.naarsPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.naarsPrimary.opacity(0.1))
                .cornerRadius(6)
            } else if isReview {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                    Text("Review")
                        .font(.naarsCaption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Author and time row
            HStack(alignment: .center, spacing: 8) {
                // Avatar
                if let author = post.author {
                    AvatarView(
                        imageUrl: author.avatarUrl,
                        name: author.name,
                        size: 24
                    )
                } else {
                    AvatarView(imageUrl: nil, name: "townhall_unknown".localized, size: 24)
                }
                
                // Author name (same font as time)
                if let author = post.author {
                    Text(author.name)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                } else {
                    Text("townhall_unknown_user".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Pin icon for pinned announcements
                if post.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.naarsPrimary)
                }

                // Time ago (right-aligned)
                Text(post.createdAt.timeAgo)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            // Review subtitle: "Reviewed Jane Doe for a ride"
            if let subtitle = reviewSubtitle {
                Text(subtitle)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Divider()
            
            // Post content
            Text(post.content)
                .font(.naarsBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Image if present
            if let imageUrl = post.imageUrl, !imageUrl.isEmpty {
                CachedAsyncImage(
                    url: URL(string: imageUrl),
                    placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    },
                    errorView: {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color.naarsCardBackground)
                            .cornerRadius(8)
                    }
                )
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .cornerRadius(8)
            }
            
            Divider()
            
            // Action row: Comments on left, Voting on right
            HStack(alignment: .center, spacing: 16) {
                // Comments button on left
                Button(action: {
                    showComments = true
                    onComment?(post.id)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Delete button (if own post)
                if isOwnPost, let _ = onDelete {
                    Button(action: {
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.naarsCaption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Voting buttons on right
                HStack(spacing: 8) {
                    // Downvote button
                    Button(action: {
                        if post.userVote == .downvote {
                            onVote?(post.id, nil) // Remove vote
                        } else {
                            onVote?(post.id, .downvote)
                        }
                    }) {
                        HStack(spacing: Constants.Spacing.xs) {
                            Image(systemName: "arrow.down")
                                .font(.naarsCaption)
                                .foregroundColor(post.userVote == .downvote ? .blue : .secondary)
                            if post.downvotes > 0 {
                                Text("\(post.downvotes)")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(post.userVote == .downvote ? "Remove downvote" : "Downvote post")
                    .accessibilityHint(post.userVote == .downvote ? "Double-tap to remove your downvote" : "Double-tap to downvote this post")
                    
                    // Upvote button
                    Button(action: {
                        if post.userVote == .upvote {
                            onVote?(post.id, nil) // Remove vote
                        } else {
                            onVote?(post.id, .upvote)
                        }
                    }) {
                        HStack(spacing: Constants.Spacing.xs) {
                            Image(systemName: "arrow.up")
                                .font(.naarsCaption)
                                .foregroundColor(post.userVote == .upvote ? .orange : .secondary)
                            if post.upvotes > 0 {
                                Text("\(post.upvotes)")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(post.userVote == .upvote ? "Remove upvote" : "Upvote post")
                    .accessibilityHint(post.userVote == .upvote ? "Double-tap to remove your upvote" : "Double-tap to upvote this post")
                }
            }
            .padding(.top, Constants.Spacing.xs)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isAnnouncement ? Color.naarsPrimary.opacity(0.6) :
                    isHighlighted ? Color.naarsPrimary.opacity(0.6) : Color.clear,
                    lineWidth: (isAnnouncement || isHighlighted) ? 2 : 0
                )
        )
        .sheet(isPresented: $showComments) {
            PostCommentsView(postId: post.id)
        }
        .alert("townhall_delete_post".localized, isPresented: $showDeleteAlert) {
            Button("common_cancel".localized, role: .cancel) { }
            Button("common_delete".localized, role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("townhall_delete_post_confirmation".localized)
        }
    }
}

#Preview {
    let testUserId = UUID()
    let testAuthorId = UUID()
    
    ScrollView {
        VStack(spacing: 16) {
            TownHallPostCard(
                post: TownHallPost(
                    userId: testAuthorId,
                    content: "This is a test post with some content. It can be quite long and will wrap to multiple lines. The title should be extracted from this content automatically.",
                    author: Profile(
                        id: testAuthorId,
                        name: "John Doe",
                        email: "john@example.com",
                        isAdmin: false,
                        approved: true,
                        invitedBy: UUID()
                    ),
                    commentCount: 5,
                    upvotes: 10,
                    downvotes: 2
                ),
                currentUserId: testUserId
            )
            
            TownHallPostCard(
                post: TownHallPost(
                    userId: testAuthorId,
                    content: "Great experience! Highly recommend this service.",
                    type: .review,
                    author: Profile(
                        id: testAuthorId,
                        name: "Jane Smith",
                        email: "jane@example.com",
                        isAdmin: false,
                        approved: true,
                        invitedBy: UUID()
                    ),
                    review: Review(
                        reviewerId: testAuthorId,
                        fulfillerId: UUID(),
                        rating: 5,
                        comment: "Great experience!"
                    ),
                    commentCount: 3,
                    upvotes: 8,
                    downvotes: 0,
                    userVote: .upvote
                ),
                currentUserId: testUserId
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

