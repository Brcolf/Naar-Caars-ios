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
        NavigationStack {
            VStack(spacing: 0) {
                // Post composer section
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
                
                Divider()
                
                // Posts feed
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    // Show skeleton loading
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonView()
                            }
                        }
                        .padding()
                    }
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error.localizedDescription,
                        retryAction: {
                            Task {
                                await viewModel.loadPosts()
                            }
                        }
                    )
                } else if viewModel.posts.isEmpty {
                    EmptyStateView(
                        icon: "message.fill",
                        title: "No Posts Yet",
                        message: "Be the first to share something with the community!",
                        actionTitle: "Create Post",
                        action: {
                            showCreatePost = true
                        }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.posts) { post in
                                TownHallPostRow(
                                    post: post,
                                    currentUserId: AuthService.shared.currentUserId,
                                    onDelete: {
                                        Task {
                                            await viewModel.deletePost(post)
                                        }
                                    }
                                )
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
            }
            .navigationTitle("Town Hall")
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
    }
}

#Preview {
    TownHallFeedView()
}


