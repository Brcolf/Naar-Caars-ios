//
//  PostCommentsView.swift
//  NaarsCars
//
//  View for displaying and managing comments on a post (with nested replies)
//

import SwiftUI
internal import Combine

/// View for displaying comments on a post with nested replies support
struct PostCommentsView: View {
    let postId: UUID
    @StateObject private var viewModel: PostCommentsViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(postId: UUID) {
        self.postId = postId
        _viewModel = StateObject(wrappedValue: PostCommentsViewModel(postId: postId))
    }
    @State private var newCommentText = ""
    @State private var replyingTo: UUID? // Comment ID we're replying to
    @FocusState private var isCommentFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                if viewModel.isLoading && viewModel.topLevelComments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.topLevelComments.isEmpty {
                    EmptyStateView(
                        icon: "bubble.left",
                        title: "No Comments Yet",
                        message: "Be the first to comment on this post!",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.topLevelComments) { comment in
                                CommentRow(
                                    comment: comment,
                                    currentUserId: AuthService.shared.currentUserId,
                                    onReply: { parentId in
                                        replyingTo = parentId
                                        isCommentFieldFocused = true
                                    },
                                    onVote: { commentId, voteType in
                                        Task {
                                            await viewModel.voteComment(commentId: commentId, voteType: voteType)
                                        }
                                    },
                                    onDelete: { commentId in
                                        Task {
                                            await viewModel.deleteComment(commentId: commentId)
                                        }
                                    },
                                    depth: 0 // Top-level comments start at depth 0
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                Divider()
                
                // Comment input section
                VStack(alignment: .leading, spacing: 8) {
                    if let replyingToId = replyingTo,
                       let parentComment = viewModel.findComment(id: replyingToId) {
                        HStack {
                            Text("Replying to \(parentComment.author?.name ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Cancel") {
                                replyingTo = nil
                                newCommentText = ""
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField(
                            replyingTo != nil ? "Write a reply..." : "Write a comment...",
                            text: $newCommentText,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($isCommentFieldFocused)
                        
                        Button(action: {
                            Task {
                                if let parentId = replyingTo {
                                    await viewModel.addReply(to: parentId, content: newCommentText)
                                } else {
                                    await viewModel.addComment(content: newCommentText)
                                }
                                newCommentText = ""
                                replyingTo = nil
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                                .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                    .id("community.townHall.postCommentsSheet.commentInput")
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadComments()
            }
        }
    }
}

/// Individual comment row with nested replies (Reddit-style)
struct CommentRow: View {
    let comment: TownHallComment
    let currentUserId: UUID?
    let onReply: (UUID) -> Void
    let onVote: (UUID, VoteType?) -> Void
    let onDelete: (UUID) -> Void
    let depth: Int // Nesting depth (0 = top-level, 1+ = replies)
    
    @State private var showReplies = true
    @State private var showDeleteAlert = false
    
    private let maxDepth = 5 // Maximum nesting depth to prevent infinite recursion
    private var indent: CGFloat {
        CGFloat(min(depth, maxDepth)) * 16 // 16pt indent per level
    }
    
    var isOwnComment: Bool {
        currentUserId == comment.userId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Comment content
            HStack(alignment: .top, spacing: 8) {
                // Indentation for nested comments
                if depth > 0 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .padding(.trailing, 4)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Author and time
                    HStack(alignment: .center, spacing: 6) {
                        if let author = comment.author {
                            Text(author.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        } else {
                            Text("Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(comment.createdAt.localizedRelative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    // Comment content
                    Text(comment.content)
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Actions: Reply, Delete, Vote
                    HStack(spacing: 16) {
                        // Reply button
                        if depth < maxDepth {
                            Button(action: {
                                onReply(comment.id)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrowshape.turn.up.left")
                                        .font(.caption)
                                    Text("Reply")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Delete button (if own comment)
                        if isOwnComment {
                            Button(action: {
                                showDeleteAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        // Voting buttons on right
                        HStack(spacing: 8) {
                            // Downvote
                            Button(action: {
                                if comment.userVote == .downvote {
                                    onVote(comment.id, nil)
                                } else {
                                    onVote(comment.id, .downvote)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .font(.caption)
                                        .foregroundColor(comment.userVote == .downvote ? .blue : .secondary)
                                    if comment.downvotes > 0 {
                                        Text("\(comment.downvotes)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Upvote
                            Button(action: {
                                if comment.userVote == .upvote {
                                    onVote(comment.id, nil)
                                } else {
                                    onVote(comment.id, .upvote)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.caption)
                                        .foregroundColor(comment.userVote == .upvote ? .orange : .secondary)
                                    if comment.upvotes > 0 {
                                        Text("\(comment.upvotes)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                    
                    // Show replies toggle (if has replies)
                    if let replies = comment.replies, !replies.isEmpty {
                        Button(action: {
                            showReplies.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                Text("\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 4)
                        
                        // Nested replies (if expanded)
                        if showReplies {
                            ForEach(replies) { reply in
                                CommentRow(
                                    comment: reply,
                                    currentUserId: currentUserId,
                                    onReply: onReply,
                                    onVote: onVote,
                                    onDelete: onDelete,
                                    depth: depth + 1
                                )
                                .padding(.leading, indent)
                                .padding(.top, 8)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Delete Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(comment.id)
            }
        } message: {
            Text("Are you sure you want to delete this comment? This action cannot be undone.")
        }
    }
}

/// ViewModel for post comments
@MainActor
final class PostCommentsViewModel: ObservableObject {
    @Published var comments: [TownHallComment] = []
    @Published var isLoading = false
    @Published var error: String?
    
    let postId: UUID
    private let commentService = TownHallCommentService.shared
    private let authService = AuthService.shared
    
    init(postId: UUID) {
        self.postId = postId
    }
    
    var topLevelComments: [TownHallComment] {
        comments.filter { $0.parentCommentId == nil }
    }
    
    func loadComments(for postId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            comments = try await commentService.fetchComments(for: postId)
        } catch {
            self.error = error.localizedDescription
            print("🔴 Error loading comments: \(error.localizedDescription)")
        }
    }
    
    // Convenience method that uses stored postId
    func loadComments() async {
        await loadComments(for: postId)
    }
    
    func addComment(content: String) async {
        guard let userId = authService.currentUserId else {
            error = "You must be logged in to comment"
            return
        }
        
        do {
            _ = try await commentService.createComment(
                postId: postId,
                userId: userId,
                content: content
            )
            // Reload comments to get nested structure
            await loadComments(for: postId)
        } catch {
            self.error = error.localizedDescription
            print("🔴 Error adding comment: \(error.localizedDescription)")
        }
    }
    
    func addReply(to parentId: UUID, content: String) async {
        guard let userId = authService.currentUserId else {
            error = "You must be logged in to reply"
            return
        }
        
        do {
            _ = try await commentService.createReply(
                parentCommentId: parentId,
                userId: userId,
                content: content
            )
            // Reload comments to get nested structure
            await loadComments(for: postId)
        } catch {
            self.error = error.localizedDescription
            print("🔴 Error adding reply: \(error.localizedDescription)")
        }
    }
    
    func voteComment(commentId: UUID, voteType: VoteType?) async {
        guard let userId = authService.currentUserId else {
            error = "You must be logged in to vote"
            return
        }
        
        do {
            try await commentService.voteComment(commentId: commentId, userId: userId, voteType: voteType)
            // Reload comments to get updated vote counts
            await loadComments(for: postId)
        } catch {
            self.error = error.localizedDescription
            print("🔴 Error voting on comment: \(error.localizedDescription)")
        }
    }
    
    func deleteComment(commentId: UUID) async {
        guard let userId = authService.currentUserId else {
            error = "You must be logged in to delete comments"
            return
        }
        
        do {
            try await commentService.deleteComment(commentId: commentId, userId: userId)
            // Reload comments
            await loadComments(for: postId)
        } catch {
            self.error = error.localizedDescription
            print("🔴 Error deleting comment: \(error.localizedDescription)")
        }
    }
    
    func findComment(id: UUID) -> TownHallComment? {
        func search(in comments: [TownHallComment]) -> TownHallComment? {
            for comment in comments {
                if comment.id == id {
                    return comment
                }
                if let replies = comment.replies, let found = search(in: replies) {
                    return found
                }
            }
            return nil
        }
        return search(in: comments)
    }
}

#Preview {
    PostCommentsView(postId: UUID())
}

