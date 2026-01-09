//
//  ConversationsListView.swift
//  NaarsCars
//
//  View for displaying list of conversations
//

import SwiftUI

/// View for displaying list of conversations
struct ConversationsListView: View {
    @StateObject private var viewModel = ConversationsListViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @EnvironmentObject var appState: AppState
    @State private var showNewMessage = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var navigateToConversation: UUID?
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    // Skeleton loading
                    List {
                        ForEach(0..<5) { _ in
                            SkeletonConversationRow()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error.localizedDescription,
                        retryAction: { Task { await viewModel.loadConversations() } }
                    )
                } else if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        icon: "message.fill",
                        title: "No Conversations Yet",
                        message: "Start a conversation by claiming a request or messaging a user.",
                        actionTitle: "New Message",
                        action: {
                            showNewMessage = true
                        }
                    )
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversationDetail in
                            NavigationLink(destination: ConversationDetailView(conversationId: conversationDetail.conversation.id)) {
                                ConversationRow(conversationDetail: conversationDetail)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refreshConversations()
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewMessage = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showNewMessage) {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: [],
                    onDismiss: {
                        if !selectedUserIds.isEmpty, let userId = selectedUserIds.first {
                            Task {
                                await createDirectConversation(with: userId)
                            }
                        }
                        showNewMessage = false
                        selectedUserIds = []
                    }
                )
            }
            .navigationDestination(item: $navigateToConversation) { conversationId in
                ConversationDetailView(conversationId: conversationId)
            }
            .onChange(of: navigationCoordinator.navigateToConversation) { _, conversationId in
                if let conversationId = conversationId {
                    navigateToConversation = conversationId
                    // Reset coordinator after navigation is triggered
                    navigationCoordinator.navigateToConversation = nil
                }
            }
            .task {
                await viewModel.loadConversations()
            }
        }
    }
    
    private func createDirectConversation(with userId: UUID) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            let conversation = try await MessageService.shared.getOrCreateDirectConversation(
                userId: currentUserId,
                otherUserId: userId
            )
            navigateToConversation = conversation.id
            // Reload conversations to show the new one
            await viewModel.loadConversations()
        } catch {
            print("🔴 Error creating direct conversation: \(error.localizedDescription)")
        }
    }
}

/// Conversation row component
struct ConversationRow: View {
    let conversationDetail: ConversationWithDetails
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.naarsPrimary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversationTitle)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let lastMessage = conversationDetail.lastMessage {
                        Text(lastMessage.createdAt.timeAgoString)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lastMessage = conversationDetail.lastMessage {
                    Text(lastMessage.text)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No messages yet")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            if conversationDetail.unreadCount > 0 {
                VStack {
                    Text("\(conversationDetail.unreadCount)")
                        .font(.naarsCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.naarsPrimary)
                        .cornerRadius(12)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var conversationTitle: String {
        if let title = conversationDetail.conversation.title, !title.isEmpty {
            return title
        }
        
        if !conversationDetail.otherParticipants.isEmpty {
            return conversationDetail.otherParticipants.map { $0.name }.joined(separator: ", ")
        }
        
        if conversationDetail.conversation.isActivityBased {
            return conversationDetail.conversation.rideId != nil ? "Ride Conversation" : "Favor Conversation"
        }
        
        return "Conversation"
    }
}

#Preview {
    ConversationsListView()
        .environmentObject(AppState())
}



