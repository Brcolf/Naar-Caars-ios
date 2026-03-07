//
//  MessageInteractionOverlay.swift
//  NaarsCars
//
//  iMessage-style long-press overlay with reaction bar and action buttons
//

import SwiftUI

/// Overlay shown on message long-press with reaction picker and action menu.
/// Designed to be used as a ZStack layer on top of conversation content (NOT fullScreenCover).
struct MessageInteractionOverlay: View {
    let message: Message
    let messageContent: AnyView
    let isFromCurrentUser: Bool
    let currentUserReaction: String?

    let onReact: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let onUnsend: (() -> Void)?
    let onDeleteForMe: (() -> Void)?
    let onReport: (() -> Void)?
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Reaction picker
            ReactionPicker(
                currentUserReaction: currentUserReaction,
                onReactionSelected: { reaction in
                    onReact(reaction)
                    dismiss()
                },
                onDismiss: { dismiss() }
            )

            // Message preview
            messageContent
                .scaleEffect(appeared ? 1.02 : 0.98)

            // Action buttons
            actionButtons

            Spacer()
        }
        .padding(.horizontal, 16)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 0) {
            actionButton("Reply", icon: "arrowshape.turn.up.left") {
                onReply()
                dismiss()
            }

            if !message.text.isEmpty {
                Divider()
                actionButton("Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = message.text
                    HapticManager.selectionChanged()
                    onCopy()
                    dismiss()
                }
            }

            if let onEdit, isFromCurrentUser, !message.text.isEmpty, !message.isAudioMessage, !message.isLocationMessage {
                Divider()
                actionButton("Edit", icon: "pencil") {
                    onEdit()
                    dismiss()
                }
            }

            if let onUnsend, isFromCurrentUser, message.canUnsend {
                Divider()
                actionButton("Unsend", icon: "arrow.uturn.backward", isDestructive: true) {
                    onUnsend()
                    dismiss()
                }
            }

            if let onDeleteForMe {
                Divider()
                actionButton("messaging_delete_for_me".localized, icon: "eye.slash", isDestructive: true) {
                    onDeleteForMe()
                    dismiss()
                }
            }

            if let onReport, !isFromCurrentUser {
                Divider()
                actionButton("Report", icon: "exclamationmark.bubble", isDestructive: true) {
                    onReport()
                    dismiss()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.naarsBody)
                Spacer()
                Image(systemName: icon)
            }
            .foregroundColor(isDestructive ? .red : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - UIKit Blur Wrapper

/// GPU-accelerated blur using UIVisualEffectView (avoids main-thread overhead of SwiftUI .blur())
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
