//
//  TownHallFeedView.swift
//  NaarsCars
//
//  Town hall feed view showing community posts
//

import SwiftUI

/// Town hall feed view showing community posts
struct TownHallFeedView: View {
    @StateObject private var viewModel = TownHallFeedViewModel()
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(AppState.self) private var appState
    @State private var showCreatePost = false
    @State private var guestPromptReason: GuestRestrictionReason?
    @State private var highlightedPostId: UUID?
    @State private var highlightTask: Task<Void, Never>?
    @State private var openCommentsTarget: PostCommentsTarget?
    /// A comment was added or deleted in the sheet opened from a notification or deep link.
    @State private var openedCommentsChanged = false
    @State private var toastMessage: String? = nil

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if appState.isGuest {
                            guestPromptReason = .createPost
                        } else {
                            showCreatePost = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.naarsTitle3)
                    }
                    .accessibilityLabel("townhall_new_post".localized)
                }
            }
            .sheet(isPresented: $showCreatePost) {
                // CreatePostView writes straight to the network; pull the new post into the feed
                // only when one was actually created (a cancelled sheet triggers nothing).
                CreatePostView(onPosted: {
                    Task { await viewModel.refreshAfterPostCreated() }
                })
            }
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
            .task {
                await viewModel.loadPosts()
            }
            .toast(message: $toastMessage)
            // A failed vote, delete, next page or refresh keeps the loaded posts on screen.
            .errorBanner(message: $viewModel.bannerMessage)
            .trackScreen("TownHallFeed")
            .sheet(item: $openCommentsTarget, onDismiss: {
                // Same as the sheet a post card opens: refresh the card's comment count.
                if openedCommentsChanged {
                    openedCommentsChanged = false
                    Task { await viewModel.refreshAfterCommentsChanged() }
                }
            }) { target in
                PostCommentsView(postId: target.id, onChanged: { openedCommentsChanged = true })
                    .id("community.townHall.postCommentsSheet(\(target.id))")
            }
    }
    
    private var mainContent: some View {
        postsFeedContent
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var postsFeedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            skeletonLoadingView
        } else if let error = viewModel.error, viewModel.posts.isEmpty {
            // Full-screen error only when there is nothing to show; with posts loaded a failure
            // is reported by the banner instead.
            errorView(error)
        } else if viewModel.posts.isEmpty {
            emptyStateView
        } else {
            postsListView
        }
    }
    
    private var skeletonLoadingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView()
                }
            }
            .padding()
        }
        .background(Color.naarsBackground)
    }

    private func errorView(_ error: AppError) -> some View {
        ErrorView(
            error: error.localizedDescription,
            retryAction: {
                Task {
                    await viewModel.loadPosts()
                }
            }
        )
    }
    
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "message.fill",
            title: "townhall_no_posts_yet".localized,
            message: "townhall_be_first_to_share".localized,
            actionTitle: "townhall_create_post".localized,
            action: {
                if appState.isGuest {
                    guestPromptReason = .createPost
                } else {
                    showCreatePost = true
                }
            },
            customImage: "naars_community_icon"
        )
    }
    
    private var postsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        postCardView(for: post)
                            .id("community.townHall.postCard(\(post.id))")
                            .onAppear {
                                // Infinite scroll: load more when near bottom
                                if post.id == viewModel.posts.last?.id {
                                    Task {
                                        await viewModel.loadMore()
                                    }
                                }
                            }
                    }
                    
                    // Loading indicator for pagination
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refreshPosts()
            }
            .background(Color.naarsBackground)
            // initial: true also consumes a target that was set before this list existed (cold-start
            // push tap, first visit to the tab, Leaderboard segment showing, feed still loading);
            // onChange alone never fires for a value that is already there.
            .onChange(of: navigationCoordinator.pendingIntent, initial: true) { _, intent in
                guard case .townHallPost(let postId, let mode) = intent else { return }
                let anchorId = "community.townHall.postCard(\(postId))"
                // One main-actor turn later: on the initial pass the list has not been laid out
                // yet and a scroll requested now can be dropped.
                Task { @MainActor in
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(anchorId, anchor: .top)
                    }
                }

                switch mode {
                case .openComments:
                    openCommentsTarget = .init(id: postId)
                case .highlightPost:
                    highlightPost(postId)
                }

                navigationCoordinator.pendingIntent = nil
            }
        }
    }
    
    private func postCardView(for post: TownHallPost) -> some View {
        TownHallPostCard(
            post: post,
            currentUserId: AuthService.shared.currentUserId,
            onDelete: {
                Task {
                    let countBefore = viewModel.posts.count
                    await viewModel.deletePost(post)
                    if viewModel.posts.count < countBefore {
                        toastMessage = "toast_post_deleted".localized
                    }
                }
            },
            onComment: { postId in
                // Comment action is handled within TownHallPostCard
            },
            onVote: { postId, voteType in
                if appState.isGuest {
                    guestPromptReason = .voteOnPost
                } else {
                    Task { await viewModel.votePost(postId: postId, voteType: voteType) }
                }
            },
            onCommentsChanged: { _ in
                Task { await viewModel.refreshAfterCommentsChanged() }
            },
            onAuthorBlocked: { authorId in
                toastMessage = "profile_user_blocked".localized
                Task { await viewModel.handleAuthorBlocked(authorId) }
            },
            isHighlighted: highlightedPostId == post.id
        )
    }

    private func highlightPost(_ postId: UUID) {
        highlightTask?.cancel()
        highlightedPostId = postId
        highlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            highlightedPostId = nil
        }
    }
}

private struct PostCommentsTarget: Identifiable {
    let id: UUID
}

#Preview {
    TownHallFeedView()
}


