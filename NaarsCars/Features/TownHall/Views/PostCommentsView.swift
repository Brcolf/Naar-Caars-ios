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
    
    /// Called after a comment or reply is added or deleted, so the presenter can refresh the
    /// post's comment count when the sheet closes.
    private let onChanged: (() -> Void)?

    init(postId: UUID, onChanged: (() -> Void)? = nil) {
        self.postId = postId
        self.onChanged = onChanged
        _viewModel = StateObject(wrappedValue: PostCommentsViewModel(postId: postId))
    }
    @Environment(AppState.self) private var appState
    @State private var newCommentText = ""
    @State private var replyingTo: UUID? // Comment ID we're replying to
    @FocusState private var isCommentFieldFocused: Bool
    @State private var toastMessage: String? = nil
    @State private var isSending = false
    @State private var guestPromptReason: GuestRestrictionReason?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                if viewModel.isLoading && viewModel.topLevelComments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError = viewModel.loadError, viewModel.topLevelComments.isEmpty {
                    // A failed first load is not "No comments yet": say so and offer a retry.
                    ErrorView(
                        error: loadError,
                        retryAction: {
                            Task { await viewModel.loadComments() }
                        }
                    )
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
                                            guestPromptReason = .commentOnPost
                                        } else {
                                            replyingTo = parentId
                                            isCommentFieldFocused = true
                                        }
                                    },
                                    onVote: { commentId, voteType in
                                        if appState.isGuest {
                                            guestPromptReason = .voteOnPost
                                        } else {
                                            Task {
                                                await viewModel.voteComment(commentId: commentId, voteType: voteType)
                                            }
                                        }
                                    },
                                    onDelete: { commentId in
                                        Task {
                                            if await viewModel.deleteComment(commentId: commentId) {
                                                toastMessage = "toast_comment_deleted".localized
                                                onChanged?()
                                            }
                                        }
                                    },
                                    depth: 0, // Top-level comments start at depth 0
                                    onAuthorBlocked: { authorId in
                                        toastMessage = "profile_user_blocked".localized
                                        // The presenter refreshes the feed when the sheet closes,
                                        // which drops the blocked author's posts as well.
                                        onChanged?()
                                        Task { await viewModel.handleAuthorBlocked(authorId) }
                                    }
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
                            .font(.naarsSubheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("auth_sign_in_button".localized) {
                            guestPromptReason = .commentOnPost
                        }
                        .font(.naarsSubheadline)
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
                            .textFieldStyle(.plain)
                            .font(.naarsBody)
                            .lineLimit(1...5)
                            .focused($isCommentFieldFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.naarsInsetBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            Button(action: {
                                guard !isSending else { return }
                                isSending = true
                                // Read the field and the reply target now, not inside the Task: the
                                // Task starts a beat later, and text typed in between was sent as
                                // part of this comment and then wiped with it.
                                let sentText = newCommentText
                                let parentId = replyingTo
                                Task {
                                    defer { isSending = false }
                                    // The view model keeps its last error; clear it so an earlier
                                    // failure cannot make this send look failed.
                                    viewModel.error = nil
                                    if let parentId {
                                        await viewModel.addReply(to: parentId, content: sentText)
                                    } else {
                                        await viewModel.addComment(content: sentText)
                                    }
                                    // Only clear the field once the comment is in. A failed send
                                    // (offline, the 10-second limit) used to erase the text silently.
                                    guard viewModel.error == nil else { return }
                                    toastMessage = parentId != nil ? "toast_reply_posted".localized : "toast_comment_posted".localized
                                    onChanged?()
                                    // Remove only what was sent; keep anything typed since the tap.
                                    if newCommentText.hasPrefix(sentText) {
                                        newCommentText.removeFirst(sentText.count)
                                    }
                                    if replyingTo == parentId { replyingTo = nil }
                                }
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(.title, weight: .regular))
                                    .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .naarsDisabledContent : .naarsPrimary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(replyingTo != nil ? "townhall_send_reply_accessibility".localized : "townhall_send_comment_accessibility".localized)
                            .disabled(isSending || newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .errorBanner(message: $viewModel.error)
            .sheet(item: $guestPromptReason) { reason in
                GuestSignInPromptView(
                    reason: reason,
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
    /// Author ID. Called after the user blocked this comment's author from the report sheet.
    var onAuthorBlocked: ((UUID) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var showReplies = true
    @State private var showDeleteAlert = false
    @State private var showReportSheet = false
    @State private var showGuestPrompt = false
    @State private var hasReported = false
    /// Line height of the author name (caption text), which grows with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var authorNameHeight: CGFloat = 16

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
                                            depth: depth + 1,
                                            onAuthorBlocked: onAuthorBlocked
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
                onReported: { hasReported = true },
                onBlocked: { authorId in onAuthorBlocked?(authorId) }
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
                // The author opens their profile, which has Report and Block.
                NavigationLink(destination: PublicProfileView(userId: comment.userId)) {
                    Text(author.name)
                        .font(.naarsCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(authorNameHeight < 44 ? 1 : nil)
                        // A tap target of at least 44 pt around the name that takes no extra room
                        // in the row: the padding is given back after the shape is set. The
                        // vertical part shrinks as the text grows and is gone at accessibility sizes.
                        .padding(.horizontal, Constants.Spacing.ms)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .padding(.horizontal, -Constants.Spacing.ms)
                        .padding(.vertical, -max(0, (44 - authorNameHeight) / 2))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityHint("townhall_author_profile_hint".localized)
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
                        .foregroundColor(.naarsError)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("townhall_delete_comment".localized)
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

        // The 44-pt frames sit inside each Button's label: applied after the button they enlarge
        // the layout box but not the area that responds. Spacing is 0 because those frames now
        // keep the glyphs apart (they land where the old 16-pt spacing put them).
        HStack(spacing: 0) {
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("townhall_reply_comment_accessibility".localized)
                .accessibilityHint("townhall_reply_comment_hint".localized)
            }

            if isOwnComment {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        // With no Reply button before it, keep the glyph on the text edge
                        .frame(minWidth: 44, minHeight: 44, alignment: depth < maxDepth ? .center : .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("townhall_delete_comment".localized)
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
                    .padding(.leading, depth < maxDepth ? Constants.Spacing.md : 0)
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
                            .frame(minWidth: 44, minHeight: 44, alignment: depth < maxDepth ? .center : .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("townhall_report_comment_accessibility".localized)
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
                        // Filled when it is the user's vote, so the state does not rest on colour alone
                        Image(systemName: comment.userVote == .downvote ? "arrowshape.down.fill" : "arrowshape.down")
                            .font(.naarsCaption)
                            .foregroundColor(comment.userVote == .downvote ? .naarsPrimary : .secondary)
                        if comment.downvotes > 0 {
                            Text("\(comment.downvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(comment.userVote == .downvote ? "townhall_remove_downvote_accessibility".localized : "townhall_downvote_comment_accessibility".localized)
                // The explicit label replaces the count text, so say it as the value
                .accessibilityValue(String(comment.downvotes))
                .accessibilityHint(comment.userVote == .downvote ? "townhall_remove_downvote_hint".localized : "townhall_downvote_comment_hint".localized)
                .accessibilityAddTraits(comment.userVote == .downvote ? .isSelected : [])

                Button(action: {
                    if comment.userVote == .upvote {
                        onVote(comment.id, nil)
                    } else {
                        onVote(comment.id, .upvote)
                    }
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: comment.userVote == .upvote ? "arrowshape.up.fill" : "arrowshape.up")
                            .font(.naarsCaption)
                            .foregroundColor(comment.userVote == .upvote ? .naarsPrimary : .secondary)
                        if comment.upvotes > 0 {
                            Text("\(comment.upvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(comment.userVote == .upvote ? "townhall_remove_upvote_accessibility".localized : "townhall_upvote_comment_accessibility".localized)
                .accessibilityValue(String(comment.upvotes))
                .accessibilityHint(comment.userVote == .upvote ? "townhall_remove_upvote_hint".localized : "townhall_upvote_comment_hint".localized)
                .accessibilityAddTraits(comment.userVote == .upvote ? .isSelected : [])
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
    /// The first load failed with nothing cached. The view shows a retry screen for this rather
    /// than "No comments yet" over a thread that may have comments.
    @Published var loadError: String?

    let postId: UUID
    private let commentService: TownHallCommentService
    private let voteService: TownHallVoteService
    private let repository: TownHallRepository
    private let authService = AuthService.shared
    private let messageService: any MessageServiceProtocol
    private var commentsCancellable: AnyCancellable?
    private var voteCancellable: AnyCancellable?
    private var commentVoteCache: [UUID: (upvotes: Int, downvotes: Int, userVote: VoteType?)] = [:]
    /// Comments with a vote request in flight; further taps on them wait for it.
    private var votesInFlight: Set<UUID> = []
    /// Counts thread fetches so an older response cannot overwrite a newer one.
    private var fetchGeneration = 0

    init(
        postId: UUID,
        repository: TownHallRepository? = nil,
        commentService: TownHallCommentService? = nil,
        voteService: TownHallVoteService? = nil,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.postId = postId
        self.repository = repository ?? .shared
        self.commentService = commentService ?? .shared
        self.voteService = voteService ?? .shared
        self.messageService = messageService
        bindComments()
        bindVoteNotifications()
    }

    var topLevelComments: [TownHallComment] {
        comments.filter { $0.parentCommentId == nil }
    }

    func loadComments(for postId: UUID) async {
        error = nil
        loadError = nil
        let localComments = removingBlockedAuthors(from: (try? repository.getComments(postId: postId)) ?? [])
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
            try await fetchAndApplyComments()
        } catch {
            loadError = error.localizedDescription
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
        
        // One request per comment at a time. A second tap used to be computed from the stale vote
        // and either undid the first or failed on the unique vote index.
        guard !votesInFlight.contains(commentId) else { return }
        votesInFlight.insert(commentId)
        defer { votesInFlight.remove(commentId) }

        HapticManager.selectionChanged()

        // Show the vote straight away; the server counts replace it when the write returns.
        let previous = findComment(id: commentId).map {
            (upvotes: $0.upvotes, downvotes: $0.downvotes, userVote: $0.userVote)
        }
        if let previous {
            commentVoteCache[commentId] = VoteTally.applying(voteType, to: previous)
            comments = applyVoteCache(to: comments)
        }

        do {
            try await commentService.voteComment(commentId: commentId, userId: userId, voteType: voteType)
            await refreshVoteCounts(for: [commentId])
        } catch {
            if let previous {
                commentVoteCache[commentId] = previous
                comments = applyVoteCache(to: comments)
            }
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error voting on comment: \(error.localizedDescription)")
        }
    }

    /// - Returns: `true` when the server deleted the comment.
    @discardableResult
    func deleteComment(commentId: UUID) async -> Bool {
        guard let userId = authService.currentUserId else {
            error = "townhall_must_be_logged_in_delete".localized
            return false
        }

        do {
            try await commentService.deleteComment(commentId: commentId, userId: userId)
            HapticManager.success()
            // Take it out of the list and the cache now. The cache is never pruned by an upsert,
            // so without this the deleted comment came back from SwiftData on the next save.
            comments = removingComments(from: comments) { $0.id == commentId }
            try? repository.deleteComment(id: commentId)
            await refreshFromNetwork(showLoading: false)
            return true
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error deleting comment: \(error.localizedDescription)")
            return false
        }
    }

    /// Explicit user action (the user blocked `authorId` from a comment's report sheet). Their
    /// comments leave the thread immediately; the refresh then clears them from the cache.
    func handleAuthorBlocked(_ authorId: UUID) async {
        comments = removingComments(from: comments) { $0.userId == authorId }
        await refreshFromNetwork(showLoading: false)
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
                self.comments = self.applyVoteCache(to: self.removingBlockedAuthors(from: comments))
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
            try await fetchAndApplyComments()
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("townhall", "Error refreshing comments: \(error.localizedDescription)")
        }
    }

    /// Fetches the thread and applies it to the list and the cache. Throws when the fetch fails.
    private func fetchAndApplyComments() async throws {
        fetchGeneration += 1
        let generation = fetchGeneration
        let fetched = try await commentService.fetchComments(for: postId)
        // A newer fetch started while this one was in flight (for example the one that follows
        // posting a comment). Applying this older result would drop what the newer one adds.
        guard generation == fetchGeneration else { return }
        updateVoteCache(with: fetched)
        comments = applyVoteCache(to: fetched)
        loadError = nil
        pruneCachedComments(notIn: fetched)
        try repository.upsertComments(fetched)
    }

    /// `fetched` is the whole thread as the server returns it now, so a cached comment it no longer
    /// contains was deleted, hidden by a moderator, or written by someone the user has since
    /// blocked. `upsertComments` never deletes, and the repository publisher re-emits every cached
    /// row after a save, so those comments kept coming back. Call this only after a successful
    /// fetch: a failed one must not empty the cache.
    private func pruneCachedComments(notIn fetched: [TownHallComment]) {
        let serverIds = Set(flattenComments(fetched).map(\.id))
        let cached = flattenComments((try? repository.getComments(postId: postId)) ?? [])
        for comment in cached where !serverIds.contains(comment.id) {
            try? repository.deleteComment(id: comment.id)
        }
    }

    /// Cached rows are stored before a block and are not filtered by the service, so drop comments
    /// by blocked authors (and the replies under them) whenever the cache is read.
    private func removingBlockedAuthors(from comments: [TownHallComment]) -> [TownHallComment] {
        removingComments(from: comments) { messageService.isBlocked($0.userId) }
    }

    private func removingComments(
        from comments: [TownHallComment],
        where shouldRemove: (TownHallComment) -> Bool
    ) -> [TownHallComment] {
        comments.compactMap { comment in
            guard !shouldRemove(comment) else { return nil }
            var kept = comment
            kept.replies = comment.replies.map { removingComments(from: $0, where: shouldRemove) }
            return kept
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
        // A thread fetched while a vote is being written may predate it; keep the optimistic counts.
        for comment in flattenComments(comments) where !votesInFlight.contains(comment.id) {
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

