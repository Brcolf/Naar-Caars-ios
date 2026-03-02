//
//  MessageInteractionOverlay.swift
//  NaarsCars
//
//  iMessage-style long-press overlay with reaction bar and action buttons
//

import SwiftUI

/// Full-screen overlay shown on message long-press with reaction picker and action menu
struct MessageInteractionOverlay: View {
    let message: Message
    let messageFrame: CGRect
    let isFromCurrentUser: Bool
    let currentUserReaction: String?

    // Action callbacks
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let onUnsend: (() -> Void)?
    let onReport: (() -> Void)?
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Blurred background
            BlurView(style: .systemUltraThinMaterialDark)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { dismiss() }

            VStack(spacing: 8) {
                Spacer()

                // Reaction picker above message
                ReactionPicker(
                    currentUserReaction: currentUserReaction,
                    onReactionSelected: { reaction in
                        onReact(reaction)
                        dismiss()
                    },
                    onDismiss: { dismiss() }
                )
                .padding(.horizontal, 16)

                // Spacer for message position
                Spacer()
                    .frame(height: max(messageFrame.height, 40))

                // Action buttons below message
                actionButtons
                    .padding(.horizontal, 16)

                Spacer()
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
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
