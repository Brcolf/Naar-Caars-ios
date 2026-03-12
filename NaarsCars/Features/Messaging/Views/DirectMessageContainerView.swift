//
//  DirectMessageContainerView.swift
//  NaarsCars
//
//  Container view for lazy DM creation — only creates the conversation
//  in the database when the first message is actually sent (iMessage-style).
//

import SwiftUI

/// Wraps ConversationDetailView with lazy conversation creation.
/// If an existing DM is found, immediately shows ConversationDetailView.
/// Otherwise, shows a pending input view and creates the conversation on first send.
struct DirectMessageContainerView: View {
    let otherUserId: UUID

    @State private var resolvedConversationId: UUID?
    @State private var isResolving = true
    @State private var otherUserName: String = ""
    @State private var otherUserAvatarUrl: String?
    @State private var pendingMessageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        if let conversationId = resolvedConversationId {
            ConversationDetailView(conversationId: conversationId)
        } else if isResolving {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .task {
                    await resolve()
                }
        } else {
            pendingView
        }
    }

    // MARK: - Pending View

    private var pendingView: some View {
        VStack(spacing: 0) {
            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.naarsFootnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Input bar — matches MessageInputBar styling
            HStack(spacing: 10) {
                TextField("messaging_placeholder".localized, text: $pendingMessageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .submitLabel(.return)
                    .focused($isInputFocused)
                    .accessibilityIdentifier("message.input")

                Button {
                    Task { await sendFirstMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(canSend ? .naarsPrimary : .gray)
                    }
                }
                .disabled(!canSend || isSending)
                .accessibilityIdentifier("message.send")
            }
            .padding()
            .background(Color.naarsBackgroundSecondary)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
        }
        .background(Color(.systemBackground))
        .navigationTitle(otherUserName.isEmpty ? "New Message" : otherUserName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(imageUrl: otherUserAvatarUrl, name: otherUserName.isEmpty ? "?" : otherUserName, size: 32)
                    Text(otherUserName.isEmpty ? "New Message" : otherUserName)
                        .font(.naarsSubheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private var canSend: Bool {
        !pendingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Resolution

    private func resolve() async {
        // Fetch other user's profile for display
        if let profile = try? await ProfileService.shared.fetchProfile(userId: otherUserId) {
            otherUserName = profile.name
            otherUserAvatarUrl = profile.avatarUrl
        }

        // Check for existing DM — if found, go straight to ConversationDetailView
        guard let currentUserId = AuthService.shared.currentUserId else {
            isResolving = false
            return
        }

        if let existingId = await ConversationService.shared.findExistingDirectConversation(
            userId: currentUserId,
            otherUserId: otherUserId
        ) {
            resolvedConversationId = existingId
            return
        }

        isResolving = false
    }

    // MARK: - First Message Send

    private func sendFirstMessage() async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        let text = pendingMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 5000 else {
            errorMessage = "Message is too long (max 5,000 characters)"
            return
        }

        isSending = true
        errorMessage = nil

        do {
            // Create conversation (will also find existing if race condition)
            let conversation = try await ConversationService.shared.getOrCreateDirectConversation(
                userId: currentUserId,
                otherUserId: otherUserId
            )

            // Send the message
            _ = try await MessageService.shared.sendMessage(
                conversationId: conversation.id,
                fromId: currentUserId,
                text: text
            )

            // Switch to full ConversationDetailView
            resolvedConversationId = conversation.id
        } catch {
            isSending = false
            errorMessage = "Failed to send message. Please try again."
            AppLogger.error("messaging", "DirectMessageContainerView: failed to create/send: \(error.localizedDescription)")
        }
    }
}
