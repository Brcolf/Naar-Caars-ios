//
//  TownHallPostRow.swift
//  NaarsCars
//
//  Post row component for town hall feed
//

import SwiftUI

/// Post row component for town hall feed
struct TownHallPostRow: View {
    let post: TownHallPost
    let currentUserId: UUID?
    let onDelete: (() -> Void)?
    
    @State private var showDeleteAlert = false
    
    init(post: TownHallPost, currentUserId: UUID?, onDelete: (() -> Void)? = nil) {
        self.post = post
        self.currentUserId = currentUserId
        self.onDelete = onDelete
    }
    
    var isOwnPost: Bool {
        currentUserId == post.userId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar, name, timestamp, delete button
            HStack(alignment: .top, spacing: 12) {
                if let author = post.author {
                    UserAvatarLink(profile: author, size: 40)
                } else {
                    AvatarView(imageUrl: nil, name: "Unknown", size: 40)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let author = post.author {
                        Text(author.name)
                            .font(.naarsHeadline)
                            .foregroundColor(.primary)
                    } else {
                        Text("Unknown User")
                            .font(.naarsHeadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(post.createdAt.timeAgo)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isOwnPost, let onDelete = onDelete {
                    Button(action: {
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
            }
            
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
    ScrollView {
        VStack(spacing: 16) {
            TownHallPostRow(
                post: TownHallPost(
                    userId: UUID(),
                    content: "This is a test post with some content. It can be quite long and will wrap to multiple lines.",
                    author: Profile(
                        id: UUID(),
                        name: "John Doe",
                        email: "john@example.com"
                    )
                ),
                currentUserId: UUID()
            )
            
            TownHallPostRow(
                post: TownHallPost(
                    userId: UUID(),
                    content: "Another post with an image!",
                    imageUrl: "https://picsum.photos/400/300",
                    author: Profile(
                        id: UUID(),
                        name: "Jane Smith",
                        email: "jane@example.com"
                    )
                ),
                currentUserId: UUID()
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}


