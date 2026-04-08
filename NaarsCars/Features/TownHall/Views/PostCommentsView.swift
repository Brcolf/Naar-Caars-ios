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
    @Environment(AppState.self) private var appState
    @State private var newCommentText = ""
    @State private var replyingTo: UUID? // Comment ID we're replying to
    @FocusState private var isCommentFieldFocused: Bool
    @State private var toastMessage: String? = nil
    @State private var showGuestPrompt = false
    @State private var guestRestrictionReason: GuestRestrictionReason = .commentOnPost
    
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
                        title: "townhall_no_comments_yet".localized,
                        message: "townhall_be_first_to_comment".localized,
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
                                        if appState.isGuest {
                                            guestRestrictionReason = .commentOnPost
                                            showGuestPrompt = true
                                        } else {
                                            replyingTo = parentId
                                            isCommentFieldFocused = true
                                        }
                                    },
                                    onVote: { commentId, voteType in
                                        if appState.isGuest {
                                            guestRestrictionReason = .voteOnPost
                                            showGuestPrompt = true
                                        } else {
                                            Task {
                                                await viewModel.voteComment(commentId: commentId, voteType: voteType)
                                            }
                                        }
                                    },
                                    onDelete: { commentId in
                                        Task {
                                            let countBefore = viewModel.comments.count
                                            await viewModel.deleteComment(commentId: commentId)
                                            if viewModel.comments.count < countBefore || viewModel.error == nil {
                                                toastMessage = "toast_comment_deleted".localized
                                            }
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
                if appState.isGuest {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("guest_comment_banner".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("guest_prompt_log_in".localized) {
                            guestRestrictionReason = .commentOnPost
                            showGuestPrompt = true
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color.naarsBackgroundSecondary)
                } else {
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        if let replyingToId = replyingTo,
                           let parentComment = viewModel.findComment(id: replyingToId) {
                            HStack {
                                Text("townhall_replying_to".localized(with: parentComment.author?.name ?? "townhall_unknown".localized))
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("common_cancel".localized) {
                                    replyingTo = nil
                                    newCommentText = ""
                                }
                                .font(.naarsCaption)
                                .foregroundColor(.naarsPrimary)
                            }
                            .padding(.horizontal)
                            .padding(.top, Constants.Spacing.sm)
                        }

                        HStack(alignment: .bottom, spacing: 12) {
                            TextField(
                                replyingTo != nil ? "townhall_write_reply".localized : "townhall_write_comment".localized,
                                text: $newCommentText,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...5)
                            .focused($isCommentFieldFocused)

                            Button(action: {
                                Task {
                                    let isReply = replyingTo != nil
                                    if let parentId = replyingTo {
                                        await viewModel.addReply(to: parentId, content: newCommentText)
                                    } else {
                                        await viewModel.addComment(content: newCommentText)
                                    }
                                    if viewModel.error == nil {
                                        toastMessage = isReply ? "toast_reply_posted".localized : "toast_comment_posted".localized
                                    }
                                    newCommentText = ""
                                    replyingTo = nil
                                }
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .font(.naarsTitle3)
                                    .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .naarsTextSecondary : .blue)
                            }
                            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                        .id("community.townHall.postCommentsSheet.commentInput")
                    }
                    .background(Color.naarsBackgroundSecondary)
                }
            }
            .navigationTitle("townhall_comments".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common_done".localized) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadComments()
            }
            .toast(message: $toastMessage)
            .sheet(isPresented: $showGuestPrompt) {
                GuestSignInPromptView(
                    reason: guestRestrictionReason,
                    onSignUp: {
                        appState.isGuestMode = false
                        AppLaunchManager.shared.exitGuestMode()
                    },
                    onLogIn: {
                        appState.isGuestMode = false
                        AppLaunchManager.shared.exitGuestMode()
                    }
                )
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

    @Environment(AppState.self) private var appState
    @State private var showReplies = true
    @State private var showDeleteAlert = false
    @State private var showReportSheet = false
    @State private var showGuestPrompt = false
    @State private var hasReported = false
    
    private let maxDepth = 5 // Maximum nesting depth to prevent infinite recursion
    private var indent: CGFloat {
        CGFloat(min(depth, maxDepth)) * 16 // 16pt indent per level
    }
    
    var isOwnComment: Bool {
        currentUserId == comment.userId
    }

    private var showsHiddenPlaceholder: Bool {
        comment.isModerationHidden && isOwnComment
    }

    private var hidesContentCompletely: Bool {
        comment.isModerationHidden && !isOwnComment
    }
    
    var body: some View {
        Group {
            if hidesContentCompletely {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                        if depth > 0 {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 2)
                                .padding(.trailing, 4)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            authorAndTimeRow

                            if showsHiddenPlaceholder {
                                hiddenPlaceholderBody
                            } else {
                                regularCommentBody
                            }

                            if let replies = comment.replies, !replies.isEmpty {
                                Button(action: {
                                    showReplies.toggle()
                                }) {
                                    HStack(spacing: Constants.Spacing.xs) {
                                        Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                            .font(.naarsCaption)
                                        Text("\(replies.count) \(replies.count == 1 ? "townhall_reply_singular".localized : "townhall_reply_plural".localized)")
                                            .font(.naarsCaption)
                                    }
                                    .foregroundColor(.naarsPrimary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.top, 4)

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
                                        .padding(.top, Constants.Spacing.sm)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, Constants.Spacing.sm)
        .sheet(isPresented: $showReportSheet) {
            ReportContentSheet(
                context: .comment(
                    id: comment.id,
                    authorId: comment.userId,
                    preview: comment.content.prefix(100) + (comment.content.count > 100 ? "..." : "")
                ),
                onReported: { hasReported = true }
            )
        }
        .sheet(isPresented: $showGuestPrompt) {
            GuestSignInPromptView(
                reason: .reportContent,
                onSignUp: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                },
                onLogIn: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                }
            )
        }
        .alert("townhall_delete_comment".localized, isPresented: $showDeleteAlert) {
            Button("common_cancel".localized, role: .cancel) { }
            Button("common_delete".localized, role: .destructive) {
                onDelete(comment.id)
            }
        } message: {
            Text("townhall_delete_comment_confirmation".localized)
        }
    }

    @ViewBuilder
    private var authorAndTimeRow: some View {
        HStack(alignment: .center, spacing: 6) {
            if let author = comment.author {
                Text(author.name)
                    .font(.naarsCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            } else {
                Text("townhall_unknown".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            Text(comment.createdAt.localizedRelative)
                .font(.naarsCaption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private var hiddenPlaceholderBody: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.sm) {
            Image(systemName: "eye.slash")
                .font(.naarsCaption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("townhall_comment_hidden_title".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)

                // Keep the comment-row placeholder compact while still surfacing the moderator reason.
                if let hiddenReason = comment.hiddenReason, !hiddenReason.isEmpty {
                    Text("moderation_hidden_reason".localized(with: hiddenReason))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isOwnComment {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var regularCommentBody: some View {
        Text(comment.content)
            .font(.naarsBody)
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: Constants.Spacing.md) {
            if depth < maxDepth {
                Button(action: {
                    onReply(comment.id)
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.naarsCaption)
                        Text("townhall_reply".localized)
                            .font(.naarsCaption)
                    }
                    .foregroundColor(.naarsPrimary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Reply to comment")
                .accessibilityHint("Double-tap to reply")
            }

            if isOwnComment {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if !isOwnComment {
                if hasReported {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.naarsCaption)
                        Text("townhall_reported".localized)
                            .font(.naarsCaption)
                    }
                    .foregroundColor(.secondary.opacity(0.5))
                } else {
                    Button(action: {
                        if appState.isGuest {
                            showGuestPrompt = true
                        } else {
                            showReportSheet = true
                        }
                    }) {
                        Image(systemName: "flag")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Report comment")
                }
            }

            Spacer()

            HStack(spacing: Constants.Spacing.sm) {
                Button(action: {
                    if comment.userVote == .downvote {
                        onVote(comment.id, nil)
                    } else {
                        onVote(comment.id, .downvote)
                    }
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: "arrow.down")
                            .font(.naarsCaption)
                            .foregroundColor(comment.userVote == .downvote ? .blue : .secondary)
                        if comment.downvotes > 0 {
                            Text("\(comment.downvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Downvote comment")
                .accessibilityHint("Double-tap to downvote")

                Button(action: {
                    if comment.userVote == .upvote {
                        onVote(comment.id, nil)
                    } else {
                        onVote(comment.id, .upvote)
                    }
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: "arrow.up")
                            .font(.naarsCaption)
                            .foregroundColor(comment.userVote == .upvote ? .orange : .secondary)
                        if comment.upvotes > 0 {
                            Text("\(comment.upvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Upvote comment")
                .accessibilityHint("Double-tap to upvote")
            }
        }
        .padding(.top, 4)
    }
}

/// ViewModel for post comments
@MainActor
final class PostCommentsViewModel: ObservableObject {
    @Published var comments: [TownHallComment] = []
    @Published var isLoading = false
    @Published var error: String?
    
    let postId: UUID
    private let commentService: TownHallCommentService
    private let voteService: TownHallVoteService
    private let repository: TownHallRepository
    private let authService = AuthService.shared
    private var commentsCancellable: AnyCancellable?
    private var voteCancellable: AnyCancellable?
    private var commentVoteCache: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
    
    init(
        postId: UUID,
        repository: TownHallRepository? = nil,
        commentService: TownHallCommentService? = nil,
        voteService: TownHallVoteService? = nil
    ) {
        self.postId = postId
        self.repository = repository ?? .shared
        self.commentService = commentService ?? .shared
        self.voteService = voteService ?? .shared
        bindComments()
        bindVoteNotifications()
    }
    
    var topLevelComments: [TownHallComment] {
        comments.filter { $0.parentCommentId == nil }
    }
    
    func loadComments(for postId: UUID) async {
        error = nil
        let localComments = (try? repository.getComments(postId: postId)) ?? []
        if !localComments.isEmpty {
            isLoading = false
            comments = applyVoteCache(to: localComments)
            Task {
                await refreshFromNetwork(showLoading: false)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await commentService.fetchComments(for: postId)
            updateVoteCache(with: fetched)
            comments = applyVoteCache(to: fetched)
            try repository.upsertComments(fetched)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error loading comments: \(error.localizedDescription)")
        }
    }
    
    // Convenience method that uses stored postId
    func loadComments() async {
        await loadComments(for: postId)
    }
    
    func addComment(content: String) async {
        guard let userId = authService.currentUserId else {
            error = "townhall_must_be_logged_in_comment".localized
            return
        }
        
        do {
            _ = try await commentService.createComment(
                postId: postId,
                userId: userId,
                content: content
            )
            HapticManager.lightImpact()
            await refreshFromNetwork(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error adding comment: \(error.localizedDescription)")
        }
    }
    
    func addReply(to parentId: UUID, content: String) async {
        guard let userId = authService.currentUserId else {
            error = "townhall_must_be_logged_in_reply".localized
            return
        }
        
        do {
            _ = try await commentService.createReply(
                parentCommentId: parentId,
                userId: userId,
                content: content
            )
            HapticManager.lightImpact()
            await refreshFromNetwork(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error adding reply: \(error.localizedDescription)")
        }
    }
    
    func voteComment(commentId: UUID, voteType: VoteType?) async {
        guard let userId = authService.currentUserId else {
            error = "townhall_must_be_logged_in_vote".localized
            return
        }
        
        HapticManager.selectionChanged()
        
        do {
            try await commentService.voteComment(commentId: commentId, userId: userId, voteType: voteType)
            await refreshVoteCounts(for: [commentId])
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error voting on comment: \(error.localizedDescription)")
        }
    }
    
    func deleteComment(commentId: UUID) async {
        guard let userId = authService.currentUserId else {
            error = "townhall_must_be_logged_in_delete".localized
            return
        }
        
        do {
            try await commentService.deleteComment(commentId: commentId, userId: userId)
            HapticManager.success()
            await refreshFromNetwork(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error deleting comment: \(error.localizedDescription)")
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

    private func bindComments() {
        commentsCancellable = repository.getCommentsPublisher(postId: postId)
            .sink { [weak self] comments in
                guard let self else { return }
                self.comments = self.applyVoteCache(to: comments)
            }
    }

    private func bindVoteNotifications() {
        voteCancellable = NotificationCenter.default.publisher(for: .townHallCommentVotesDidChange)
            .compactMap { $0.object as? UUID }
            .sink { [weak self] commentId in
                Task { @MainActor in
                    await self?.refreshVoteCounts(for: [commentId])
                }
            }
    }

    private func refreshFromNetwork(showLoading: Bool) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }

        do {
            let fetched = try await commentService.fetchComments(for: postId)
            updateVoteCache(with: fetched)
            comments = applyVoteCache(to: fetched)
            try repository.upsertComments(fetched)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error refreshing comments: \(error.localizedDescription)")
        }
    }

    private func refreshVoteCounts(for commentIds: [UUID]) async {
        guard !commentIds.isEmpty else { return }
        let counts = await voteService.fetchCommentVoteCounts(
            commentIds: commentIds,
            userId: authService.currentUserId
        )
        for (commentId, data) in counts {
            commentVoteCache[commentId] = (data.upvotes, data.downvotes, data.userVote)
        }
        comments = applyVoteCache(to: comments)
    }

    private func updateVoteCache(with comments: [TownHallComment]) {
        for comment in flattenComments(comments) {
            commentVoteCache[comment.id] = (comment.upvotes, comment.downvotes, comment.userVote)
        }
    }

    private func applyVoteCache(to comments: [TownHallComment]) -> [TownHallComment] {
        comments.map { comment in
            var updated = comment
            if let cached = commentVoteCache[comment.id] {
                updated.upvotes = cached.upvotes
                updated.downvotes = cached.downvotes
                updated.userVote = cached.userVote
            }
            if let replies = updated.replies {
                updated.replies = applyVoteCache(to: replies)
            }
            return updated
        }
    }

    private func flattenComments(_ comments: [TownHallComment]) -> [TownHallComment] {
        var output: [TownHallComment] = []
        func walk(_ comment: TownHallComment) {
            output.append(comment)
            if let replies = comment.replies {
                replies.forEach(walk)
            }
        }
        comments.forEach(walk)
        return output
    }
}

#Preview {
    PostCommentsView(postId: UUID())
}

