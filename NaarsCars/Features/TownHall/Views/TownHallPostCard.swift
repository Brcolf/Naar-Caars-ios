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
    
    // Show stars if post is related to a review
    private var starRating: Int? {
        guard let type = post.type, type == .review else { return nil }
        if let review = post.review {
            return review.rating
        }
        return nil
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
                
                // Star rating for review posts
                if let rating = starRating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("\(rating)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
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
                    AvatarView(imageUrl: nil, name: "Unknown", size: 24)
                }
                
                // Author name (same font as time)
                if let author = post.author {
                    Text(author.name)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unknown User")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Time ago (right-aligned)
                Text(post.createdAt.timeAgo)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
            Divider()
            
            // Post content
            Text(post.content)
                .font(.naarsBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Image if present
            if let imageUrl = post.imageUrl, !imageUrl.isEmpty {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .cornerRadius(8)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    @unknown default:
                        EmptyView()
                    }
                }
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
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Delete button (if own post)
                if isOwnPost, let onDelete = onDelete {
                    Button(action: {
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
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
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .foregroundColor(post.userVote == .downvote ? .blue : .secondary)
                            if post.downvotes > 0 {
                                Text("\(post.downvotes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Upvote button
                    Button(action: {
                        if post.userVote == .upvote {
                            onVote?(post.id, nil) // Remove vote
                        } else {
                            onVote?(post.id, .upvote)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.caption)
                                .foregroundColor(post.userVote == .upvote ? .orange : .secondary)
                            if post.upvotes > 0 {
                                Text("\(post.upvotes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.naarsPrimary.opacity(0.6), lineWidth: isHighlighted ? 2 : 0)
        )
        .sheet(isPresented: $showComments) {
            PostCommentsView(postId: post.id)
        }
        .alert("Delete Post", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
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

