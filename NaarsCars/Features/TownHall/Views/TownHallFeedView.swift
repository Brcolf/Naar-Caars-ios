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
    @State private var showCreatePost = false
    
    var body: some View {
        mainContent
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreatePost = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreatePost) {
                CreatePostView()
            }
            .task {
                await viewModel.loadPosts()
            }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            postComposerSection
            Divider()
            postsFeedContent
        }
    }
    
    // MARK: - View Components
    
    private var postComposerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share with the Community")
                .font(.naarsHeadline)
                .padding(.horizontal)
                .padding(.top)
            
            HStack(spacing: 12) {
                Text("What's on your mind?")
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onTapGesture {
                        showCreatePost = true
                    }
                
                Button {
                    showCreatePost = true
                } label: {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundColor(.naarsPrimary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var postsFeedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            skeletonLoadingView
        } else if let error = viewModel.error {
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
            title: "No Posts Yet",
            message: "Be the first to share something with the community!",
            actionTitle: "Create Post",
            action: {
                showCreatePost = true
            }
        )
    }
    
    private var postsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.posts) { post in
                    postCardView(for: post)
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
    }
    
    private func postCardView(for post: TownHallPost) -> some View {
        TownHallPostCard(
            post: post,
            currentUserId: AuthService.shared.currentUserId,
            onDelete: {
                Task {
                    await viewModel.deletePost(post)
                }
            },
            onComment: { postId in
                // Comment action is handled within TownHallPostCard
            },
            onVote: { postId, voteType in
                Task {
                    await viewModel.votePost(postId: postId, voteType: voteType)
                }
            }
        )
    }
}

#Preview {
    TownHallFeedView()
}


